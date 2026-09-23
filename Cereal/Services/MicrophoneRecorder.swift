import AVFoundation
import Foundation

@MainActor
final class MicrophoneRecorder {
    private var engine: AVAudioEngine?
    private var sink: AudioTrackSink?

    var levels: [Float] { sink?.levels ?? [] }
    var isPaused: Bool { sink?.isPaused ?? false }
    var isActive: Bool { engine != nil }

    func start(at url: URL, feed: LiveAudioFeed?) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw RecorderError.microphoneDenied
        }
        try LectureStorage().prepareAudioDirectory()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.couldNotStart }
        let sink = try AudioTrackSink(url: url, inputFormat: inputFormat, feed: feed)
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat, block: Self.tapBlock(for: sink))
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

    nonisolated private static func tapBlock(for sink: AudioTrackSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.process(buffer) }
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
