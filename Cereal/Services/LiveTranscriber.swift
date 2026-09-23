import AVFoundation
import Foundation
import Observation
import Speech

/// Streams recorder audio into the on-device speech model so notes can follow along while recording.
/// The saved recording is still transcribed again afterwards for timestamped, higher-quality text.
@MainActor @Observable
final class LiveTranscriber {
    /// Finalized passages in the order they were heard. Consecutive text from one speaker is joined.
    private(set) var lines: [LiveLine] = []
    /// In-progress text per source; a nil speaker means a single unlabeled source.
    private(set) var volatileText: [Speaker?: String] = [:]
    private(set) var isListening = false
    private var sessions: [(analyzer: SpeechAnalyzer, feed: LiveAudioFeed)] = []
    private var resultsTasks: [Task<Void, Never>] = []
    private var generation = 0

    var hasText: Bool { !lines.isEmpty || volatileText.values.contains { !$0.isEmpty } }
    var isLabeled: Bool { lines.contains { $0.speaker != nil } || volatileText.keys.contains { $0 != nil } }

    func start(feed: LiveAudioFeed) async {
        await start(sources: [(nil, feed)])
    }

    func start(sources: [(speaker: Speaker?, feed: LiveAudioFeed)]) async {
        await stop()
        let session = generation
        lines = []
        volatileText = [:]
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { return }
        for source in sources {
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
                sessions.append((analyzer, source.feed))
                isListening = true
                let speaker = source.speaker
                resultsTasks.append(Task { [weak self] in
                    do {
                        for try await result in module.results {
                            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard let self else { return }
                            if result.isFinal {
                                self.volatileText[speaker] = nil
                                if !text.isEmpty { self.append(text, from: speaker) }
                            } else {
                                self.volatileText[speaker] = text
                            }
                        }
                    } catch {}
                })
                source.feed.connect(to: format, continuation: continuation)
            } catch {
                continue
            }
        }
    }

    private func append(_ text: String, from speaker: Speaker?) {
        if let last = lines.indices.last, lines[last].speaker == speaker {
            lines[last].text += " " + text
        } else {
            lines.append(LiveLine(speaker: speaker, text: text))
        }
    }

    func stop() async {
        generation += 1
        let finishing = sessions
        sessions = []
        for session in finishing {
            session.feed.disconnect()
            try? await session.analyzer.finalizeAndFinishThroughEndOfInput()
        }
        resultsTasks = []
        isListening = false
    }

    func reset() {
        lines = []
        volatileText = [:]
    }
}

struct LiveLine: Identifiable {
    let id = UUID()
    let speaker: Speaker?
    var text: String
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

