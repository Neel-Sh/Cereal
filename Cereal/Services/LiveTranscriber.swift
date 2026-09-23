import AVFoundation
import Foundation
import Observation
import Speech

/// Streams recorder audio into the on-device speech model so notes can follow along while recording.
/// The saved recording is still transcribed again afterwards for timestamped, higher-quality text.
@MainActor @Observable
final class LiveTranscriber {
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    private(set) var isListening = false
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var feed: LiveAudioFeed?
    private var generation = 0

    var hasText: Bool { !finalizedText.isEmpty || !volatileText.isEmpty }

    func start(feed: LiveAudioFeed) async {
        await stop()
        let session = generation
        finalizedText = ""
        volatileText = ""
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { return }
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            if let download = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await download.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]),
                  session == generation else { return }
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let analyzer = SpeechAnalyzer(modules: [module])
            try await analyzer.start(inputSequence: stream)
            guard session == generation else {
                continuation.finish()
                await analyzer.cancelAndFinishNow()
                return
            }
            self.analyzer = analyzer
            self.feed = feed
            isListening = true
            resultsTask = Task { [weak self] in
                do {
                    for try await result in module.results {
                        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let self else { return }
                        if result.isFinal {
                            if !text.isEmpty {
                                self.finalizedText += self.finalizedText.isEmpty ? text : " " + text
                            }
                            self.volatileText = ""
                        } else {
                            self.volatileText = text
                        }
                    }
                } catch {}
            }
            feed.connect(to: format, continuation: continuation)
        } catch {
            isListening = false
        }
    }

    func stop() async {
        generation += 1
        feed?.disconnect()
        feed = nil
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil
        resultsTask = nil
        isListening = false
    }

    func reset() {
        finalizedText = ""
        volatileText = ""
    }
}

/// Thread-safe bridge between realtime audio callbacks and the speech analyzer input stream.
nonisolated final class LiveAudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?

    func connect(to format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        lock.lock()
        defer { lock.unlock() }
        targetFormat = format
        converter = nil
        self.continuation = continuation
    }

    func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        continuation?.finish()
        continuation = nil
        targetFormat = nil
        converter = nil
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation, let targetFormat, buffer.frameLength > 0 else { return }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converter?.downmix = true
        }
        guard let converter, let output = AudioConversion.convert(buffer, using: converter) else { return }
        continuation.yield(AnalyzerInput(buffer: output))
    }
}

nonisolated enum AudioConversion {
    static func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let format = converter.outputFormat
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}

