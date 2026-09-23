import AVFoundation
import Foundation

@MainActor
final class MicrophoneRecorder {
    private var engine: AVAudioEngine?
    private var sink: MicrophoneSink?

    var level: Float { sink?.level ?? 0 }
    var isPaused: Bool { sink?.isPaused ?? false }

    func start(at url: URL, feed: LiveAudioFeed?) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw RecorderError.microphoneDenied
        }
        try LectureStorage().prepareAudioDirectory()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.couldNotStart }
        let sink = try MicrophoneSink(url: url, inputFormat: inputFormat, feed: feed)
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat, block: sink.makeTapBlock())
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.couldNotStart
        }
        self.engine = engine
        self.sink = sink
    }

    func pause() {
        guard let engine, let sink, !sink.isPaused else { return }
        sink.isPaused = true
        engine.pause()
    }

    func resume() throws {
        guard let engine, let sink, sink.isPaused else { return }
        try engine.start()
        sink.isPaused = false
    }

    func stop() -> TimeInterval {
        guard let engine, let sink else { return 0 }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        let duration = sink.duration
        self.engine = nil
        self.sink = nil
        return duration
    }
}

/// Receives realtime microphone buffers, writes mono AAC, meters level, and forwards audio to live transcription.
nonisolated private final class MicrophoneSink: @unchecked Sendable {
    private let lock = NSLock()
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let feed: LiveAudioFeed?
    private var framesWritten: AVAudioFramePosition = 0
    private var currentLevel: Float = 0
    private var paused = false

    init(url: URL, inputFormat: AVAudioFormat, feed: LiveAudioFeed?) throws {
        let sampleRate = min(inputFormat.sampleRate, 48_000)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.couldNotStart
        }
        converter.downmix = true
        self.converter = converter
        self.feed = feed
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    var level: Float {
        lock.lock(); defer { lock.unlock() }
        return paused ? 0 : currentLevel
    }

    var isPaused: Bool {
        get { lock.lock(); defer { lock.unlock() }; return paused }
        set { lock.lock(); paused = newValue; lock.unlock() }
    }

    var duration: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return Double(framesWritten) / converter.outputFormat.sampleRate
    }

    func makeTapBlock() -> AVAudioNodeTapBlock {
        { [self] buffer, _ in process(buffer) }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !paused, let mono = AudioConversion.convert(buffer, using: converter) else { return }
        do {
            try file.write(from: mono)
            framesWritten += AVAudioFramePosition(mono.frameLength)
        } catch {
            return
        }
        if let samples = mono.floatChannelData?[0] {
            var sum: Float = 0
            for index in 0..<Int(mono.frameLength) { sum += samples[index] * samples[index] }
            let rms = sqrt(sum / Float(max(mono.frameLength, 1)))
            let decibels = 20 * log10(max(rms, 0.000_01))
            currentLevel = max(0, min(1, (decibels + 55) / 55))
        }
        feed?.append(mono)
    }
}

nonisolated private enum RecorderError: LocalizedError {
    case microphoneDenied
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Allow microphone access in System Settings → Privacy & Security → Microphone."
        case .couldNotStart: "The microphone could not start recording. Check that an input device is connected."
        }
    }
}
