import AVFoundation
import CoreMedia
import Foundation
import Speech

struct LectureTranscriber {
    /// Transcribes a call's microphone and computer-audio tracks and interleaves them as "Me" and "Them".
    func transcribeCall(microphone: URL, system: URL) async throws -> [TranscriptSegment] {
        let them = try await transcribe(system, speaker: .them)
        let me = FileManager.default.fileExists(atPath: microphone.path)
            ? try await transcribe(microphone, speaker: .me) : []
        return Self.merge(me: me, them: them)
    }

    /// Without headphones the microphone also hears the other side, so drop "Me" passages that
    /// mostly repeat words from an overlapping "Them" passage.
    static func merge(me: [TranscriptSegment], them: [TranscriptSegment]) -> [TranscriptSegment] {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let theirWords = them.map { words($0.text) }
        let mine = me.filter { segment in
            let spoken = words(segment.text)
            guard !spoken.isEmpty else { return false }
            return !them.indices.contains { index in
                let other = them[index]
                guard other.start < segment.end + 2, other.end > segment.start - 2 else { return false }
                return Double(spoken.intersection(theirWords[index]).count) / Double(spoken.count) >= 0.6
            }
        }
        return (mine + them).sorted { $0.start < $1.start }
    }

    func transcribe(_ url: URL, speaker: Speaker? = nil) async throws -> [TranscriptSegment] {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw TranscriptionError.unsupportedLanguage
        }

        let module = SpeechTranscriber(locale: locale, preset: .timeIndexedTranscriptionWithAlternatives)
        if let download = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await download.downloadAndInstall()
        }

        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [module])
        async let transcript = module.results.reduce(into: [TranscriptSegment]()) { segments, result in
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let start = max(0, result.range.start.seconds)
            let end = max(start, result.range.end.seconds)
            segments.append(TranscriptSegment(start: start, end: end, text: text))
        }

        do {
            if let lastSample = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return groupIntoPassages(try await transcript.sorted { $0.start < $1.start }, speaker: speaker)
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private func groupIntoPassages(_ fragments: [TranscriptSegment], speaker: Speaker?) -> [TranscriptSegment] {
        var passages: [TranscriptSegment] = []
        var start: TimeInterval?
        var end: TimeInterval = 0
        var words: [String] = []

        func flush() {
            guard let start, !words.isEmpty else { return }
            passages.append(TranscriptSegment(start: start, end: end, text: words.joined(separator: " "), speaker: speaker))
            words.removeAll()
        }

        for fragment in fragments {
            if start == nil { start = fragment.start }
            end = fragment.end
            words.append(fragment.text)
            let sentenceEnded = fragment.text.hasSuffix(".") || fragment.text.hasSuffix("?") || fragment.text.hasSuffix("!")
            let passageTooLong = words.joined(separator: " ").count >= 220 || end - (start ?? end) >= 12
            if sentenceEnded || passageTooLong {
                flush()
                start = nil
            }
        }
        flush()
        return passages
    }
}

private enum TranscriptionError: LocalizedError {
    case unsupportedLanguage

    var errorDescription: String? {
        "On-device transcription is not available for your Mac’s current language. Your audio is still saved."
    }
}
