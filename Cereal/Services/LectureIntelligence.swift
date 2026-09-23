import Foundation
import FoundationModels
import NaturalLanguage

@Generable
private struct GeneratedStudyPoint {
    @Guide(description: "One of: takeaway, concept, definition, example, question")
    var kind: String
    @Guide(description: "A short, specific title or question")
    var title: String
    @Guide(description: "A concise explanation or answer supported by the cited transcript passage")
    var detail: String
    @Guide(description: "The zero-based index of the supporting transcript passage")
    var sourceIndex: Int
}

@Generable
private struct GeneratedStudyQuestion {
    @Guide(description: "A clear question about a fact or concept in the transcript")
    var question: String
    @Guide(description: "The correct answer, directly supported by the cited transcript passage")
    var answer: String
    @Guide(description: "The zero-based index of the supporting transcript passage")
    var sourceIndex: Int
}

@Generable
private struct GeneratedOverviewPoint {
    @Guide(description: "One concise, useful lecture note sentence supported by one transcript passage")
    var text: String
    @Guide(description: "The zero-based index of the supporting transcript passage")
    var sourceIndex: Int
}

@Generable
private struct GeneratedActionItem {
    @Guide(description: "An assignment, reading, deadline, exam date, or follow-up task explicitly mentioned, written as a short imperative")
    var task: String
    @Guide(description: "The zero-based index of the supporting transcript passage")
    var sourceIndex: Int
}

@Generable
private struct GeneratedStudySection {
    @Guide(description: "A short heading of two to five words naming what this part of the session covers")
    var heading: String
    @Guide(description: "Two to four concise enhanced note points, each with a source passage index")
    var overviewPoints: [GeneratedOverviewPoint]
    @Guide(description: "Tasks, assignments, readings, or deadlines explicitly stated in these passages; empty if none were mentioned")
    var actionItems: [GeneratedActionItem]
    @Guide(description: "Three to six useful takeaways, concepts, definitions, or examples with source passage indices")
    var points: [GeneratedStudyPoint]
    @Guide(description: "One or two question-and-answer flashcards based on the passage")
    var flashcards: [GeneratedStudyQuestion]
    @Guide(description: "One or two practice quiz questions with answers based on the passage")
    var quizQuestions: [GeneratedStudyQuestion]
}

@Generable
private struct GeneratedAnswer {
    @Guide(description: "A direct answer grounded in the provided passages; say when the passages do not answer the question")
    var answer: String
    @Guide(description: "Indices of the passages supporting the answer; empty if the answer is unavailable")
    var sourceIndices: [Int]
}

@Generable
private struct GeneratedOverview {
    @Guide(description: "A specific title of three to eight words describing the session's main subject")
    var title: String
    @Guide(description: "Two or three sentences summarizing what the session covered and why it matters")
    var summary: String
}

struct StudyResult {
    let title: String
    let summary: String
    let notes: String
    let blocks: [EnhancedNoteBlock]
    let actionItems: [ActionItem]
    let items: [StudyItem]
}

struct ChatTurn {
    let question: String
    let answer: String
}

struct AnswerSource: Identifiable {
    let id: Int
    let lectureID: UUID
    let lectureTitle: String
    let segmentIndex: Int
    let start: TimeInterval
    let text: String
}

struct LectureAnswer {
    let text: String
    let sources: [AnswerSource]
}

struct LectureIntelligence {
    var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    func enhance(_ lecture: Lecture) async throws -> StudyResult {
        try ensureAvailable()
        guard !lecture.transcriptSegments.isEmpty else { throw IntelligenceError.timestampsRequired }
        let segments = sourceSegments(for: lecture)
        guard !segments.isEmpty else { throw IntelligenceError.emptyTranscript }
        let chunks = chunked(segments)
        var blocks: [EnhancedNoteBlock] = []
        var actionItems: [ActionItem] = []
        var items: [StudyItem] = []

        for (number, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let session = LanguageModelSession(instructions: """
                You help a student study one recorded session. Use only the supplied transcript and the student's rough notes.
                \(lecture.template.guidance)
                Preserve the student's emphasis when it is supported by the transcript. Never invent a fact, definition, or example.
                Each point must cite a supplied passage index. Make useful study outputs, including concepts, definitions,
                examples, at least one flashcard, and at least one practice quiz question when the material supports them.
                Only list action items that the speaker explicitly assigned or announced.
                \(lecture.transcriptSegments.contains { $0.speaker != nil } ? "Passages labeled \"Me\" were spoken by the note taker; \"Them\" is the other people on the call. Say who owns each action item." : "")
                """)
            let passageText = chunk.map { "[\($0.index)] \($0.segment.labeledText)" }.joined(separator: "\n")
            let roughNotes = String(lecture.notes.prefix(1800))
            let response = try await session.respond(
                to: "Lecture: \(lecture.title)\nStudent's rough notes: \(roughNotes)\nPart \(number + 1) of \(chunks.count).\nTranscript passages:\n\(passageText)",
                generating: GeneratedStudySection.self
            )
            let output = response.content
            let validIndices = Set(chunk.map(\.index))
            let heading = output.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            blocks += output.overviewPoints.compactMap { point in
                let text = point.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard validIndices.contains(point.sourceIndex), !text.isEmpty else { return nil }
                return EnhancedNoteBlock(text: text, sourceIndex: point.sourceIndex,
                                         section: heading.isEmpty ? nil : heading)
            }
            actionItems += output.actionItems.compactMap { item in
                let text = item.task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return ActionItem(text: text, sourceIndex: validIndices.contains(item.sourceIndex) ? item.sourceIndex : nil)
            }
            items += output.points.compactMap { point in
                guard validIndices.contains(point.sourceIndex),
                      let kind = StudyKind(rawValue: point.kind.lowercased()),
                      !point.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !point.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return StudyItem(kind: kind, title: point.title, detail: point.detail, sourceIndex: point.sourceIndex)
            }
            for (kind, questions) in [(StudyKind.flashcard, output.flashcards), (.quiz, output.quizQuestions)] {
                items += questions.compactMap { question in
                    guard validIndices.contains(question.sourceIndex),
                          !question.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !question.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    return StudyItem(kind: kind, title: question.question,
                                     detail: question.answer, sourceIndex: question.sourceIndex)
                }
            }
        }

        let overview = try await overview(for: lecture, blocks: blocks)
        return StudyResult(title: overview.title, summary: overview.summary,
                           notes: blocks.map(\.text).joined(separator: "\n\n"), blocks: blocks,
                           actionItems: deduplicated(actionItems), items: items)
    }

    private func overview(for lecture: Lecture, blocks: [EnhancedNoteBlock]) async throws -> (title: String, summary: String) {
        guard !blocks.isEmpty else { return ("", "") }
        let session = LanguageModelSession(instructions: """
            Write a title and a brief summary for a student's session notes. Use only the supplied notes.
            \(lecture.template.guidance)
            """)
        let notes = String(blocks.map { "- \($0.text)" }.joined(separator: "\n").prefix(5_000))
        let response = try await session.respond(
            to: "Course: \(lecture.course)\nTopic: \(lecture.topic)\nNotes:\n\(notes)",
            generating: GeneratedOverview.self
        )
        return (response.content.title.trimmingCharacters(in: .whitespacesAndNewlines),
                response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func deduplicated(_ items: [ActionItem]) -> [ActionItem] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.text.lowercased()).inserted }
    }

    func answer(_ question: String, from lectures: [Lecture], history: [ChatTurn] = []) async throws -> LectureAnswer {
        try ensureAvailable()
        let retrievalQuery = ([history.last?.question].compactMap { $0 } + [question]).joined(separator: " ")
        let sources = rankedSources(for: retrievalQuery, lectures: lectures)
        guard !sources.isEmpty else { throw IntelligenceError.emptyTranscript }
        let session = LanguageModelSession(instructions: """
            Answer the student's question using only the supplied lecture passages. Be direct and concise.
            Do not claim a fact without a supporting passage. If the material does not answer the question, say so.
            Cite the passage indices that directly support your answer.
            """)
        let context = sources.map { "[\($0.id)] \($0.lectureTitle), \(Int($0.start))s: \($0.text)" }.joined(separator: "\n")
        let conversation = history.suffix(3).map { "Student: \($0.question)\nYou: \($0.answer)" }.joined(separator: "\n")
        let response = try await session.respond(
            to: "\(conversation.isEmpty ? "" : "Earlier conversation:\n\(conversation)\n\n")Question: \(question)\nLecture passages:\n\(context)",
            generating: GeneratedAnswer.self
        )
        let cited = Set(response.content.sourceIndices)
        let matched = sources.filter { cited.contains($0.id) }
        guard !matched.isEmpty else {
            return LectureAnswer(text: "I couldn't find a supported answer in these lectures.", sources: [])
        }
        return LectureAnswer(text: response.content.answer, sources: matched)
    }

    private func sourceSegments(for lecture: Lecture) -> [(index: Int, segment: TranscriptSegment)] {
        if !lecture.transcriptSegments.isEmpty {
            return Array(lecture.transcriptSegments.enumerated()).map { (index: $0.offset, segment: $0.element) }
        }
        let text = lecture.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let source = text as NSString
        var passages: [String] = []
        var current = ""
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .bySentences) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            if current.count + sentence.count > 300 && !current.isEmpty {
                passages.append(current)
                current = ""
            }
            current += current.isEmpty ? sentence : " " + sentence
        }
        if !current.isEmpty { passages.append(current) }
        if passages.isEmpty { passages = [text] }
        return passages.enumerated().map {
            (index: $0.offset, segment: TranscriptSegment(start: 0, end: lecture.duration, text: $0.element))
        }
    }

    private func chunked(_ segments: [(index: Int, segment: TranscriptSegment)]) -> [[(index: Int, segment: TranscriptSegment)]] {
        var chunks: [[(index: Int, segment: TranscriptSegment)]] = []
        var current: [(index: Int, segment: TranscriptSegment)] = []
        var count = 0
        for segment in segments {
            if count + segment.segment.text.count > 4_500 && !current.isEmpty {
                chunks.append(current)
                current = []
                count = 0
            }
            current.append(segment)
            count += segment.segment.text.count
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func rankedSources(for question: String, lectures: [Lecture]) -> [AnswerSource] {
        let ignored = Set(["what", "when", "where", "who", "how", "why", "the", "and", "was", "were", "did", "does", "for", "from", "with", "this", "that", "lecture", "professor", "about"])
        let terms = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map(String.init).filter { $0.count > 2 && !ignored.contains($0) })
        let language = NLLanguage(rawValue: Locale.current.language.languageCode?.identifier ?? "en")
        let embedding = NLEmbedding.sentenceEmbedding(for: language)
        var scored: [(source: AnswerSource, score: Double, date: Date)] = []
        for lecture in lectures {
            for entry in sourceSegments(for: lecture) {
                let text = entry.segment.text.lowercased()
                let passageTerms = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
                let lexical = Double(terms.intersection(passageTerms).count) * 2
                let distance = embedding?.distance(between: question, and: entry.segment.text) ?? .infinity
                let semantic = distance.isFinite ? max(0, 1.5 - distance) * 2 : 0
                let score = lexical + semantic
                let source = AnswerSource(id: 0, lectureID: lecture.id,
                                          lectureTitle: lecture.title,
                                          segmentIndex: entry.index,
                                          start: entry.segment.start,
                                          text: entry.segment.labeledText)
                scored.append((source, score, lecture.recordedAt))
            }
        }
        scored.sort { $0.score == $1.score ? $0.date > $1.date : $0.score > $1.score }
        return Array(scored.prefix(12)).enumerated().map { offset, item in
            AnswerSource(id: offset, lectureID: item.source.lectureID,
                         lectureTitle: item.source.lectureTitle,
                         segmentIndex: item.source.segmentIndex,
                         start: item.source.start,
                         text: item.source.text)
        }
    }

    private func ensureAvailable() throws {
        guard isAvailable else { throw IntelligenceError.unavailable }
    }
}

private enum IntelligenceError: LocalizedError {
    case unavailable, emptyTranscript, timestampsRequired

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Intelligence is unavailable on this Mac. Enable it in System Settings to generate study notes and answers."
        case .emptyTranscript: "Transcribe a lecture before generating study notes or asking questions."
        case .timestampsRequired: "Add timestamps to this transcript before generating source-linked notes."
        }
    }
}
