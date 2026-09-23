import AVFoundation
import Foundation

/// Receives realtime audio buffers, writes mono AAC, meters level, and forwards audio to live transcription.
nonisolated final class AudioTrackSink: @unchecked Sendable {
    private let lock = NSLock()
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let feed: LiveAudioFeed?
    private var framesWritten: AVAudioFramePosition = 0
    private var waveformLevels: [Float] = []
    private var meterSum: Float = 0
    private var meterFrames = 0
    private var paused = false
    private let framesPerBar: Int
    private static let barCount = 24

    init(url: URL, inputFormat: AVAudioFormat, feed: LiveAudioFeed?) throws {
        let sampleRate = min(inputFormat.sampleRate, 48_000)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioTrackError.unsupportedFormat
        }
        converter.downmix = true
        self.converter = converter
        self.feed = feed
        framesPerBar = max(1, Int(sampleRate * 0.08))
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    /// Recent 80 ms RMS measurements, oldest first. Silence has a measured level of zero.
    var levels: [Float] {
        lock.lock(); defer { lock.unlock() }
        return waveformLevels
    }

    var isPaused: Bool {
        get { lock.lock(); defer { lock.unlock() }; return paused }
        set { lock.lock(); paused = newValue; lock.unlock() }
    }

    var duration: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return Double(framesWritten) / converter.outputFormat.sampleRate
    }

    func process(_ buffer: AVAudioPCMBuffer) {
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
            for index in 0..<Int(mono.frameLength) {
                meterSum += samples[index] * samples[index]
                meterFrames += 1
                if meterFrames == framesPerBar {
                    let rms = sqrt(meterSum / Float(meterFrames))
                    let decibels = 20 * log10(max(rms, 0.000_01))
                    let level = max(0, min(1, (decibels + 50) / 50))
                    waveformLevels.append(level)
                    if waveformLevels.count > Self.barCount { waveformLevels.removeFirst() }
                    meterSum = 0
                    meterFrames = 0
                }
            }
        }
        feed?.append(mono)
    }
}

nonisolated enum AudioTrackError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? { "The audio format could not be recorded." }
}
