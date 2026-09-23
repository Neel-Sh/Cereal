import AVFoundation
import CoreMedia
import Foundation
import Speech

struct LectureTranscriber {
    func transcribe(_ url: URL) async throws -> [TranscriptSegment] {
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
            return groupIntoPassages(try await transcript.sorted { $0.start < $1.start })
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private func groupIntoPassages(_ fragments: [TranscriptSegment]) -> [TranscriptSegment] {
        var passages: [TranscriptSegment] = []
        var start: TimeInterval?
        var end: TimeInterval = 0
        var words: [String] = []

        func flush() {
            guard let start, !words.isEmpty else { return }
            passages.append(TranscriptSegment(start: start, end: end, text: words.joined(separator: " ")))
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
