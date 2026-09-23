import Foundation

struct Lecture: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    let recordedAt: Date
    var duration: TimeInterval
    var transcript: String
    var transcriptSegments: [TranscriptSegment]
    var notes: String
    var course: String
    var topic: String
    var template: NoteTemplate
    var summary: String
    var enhancedNotes: String
    var enhancedBlocks: [EnhancedNoteBlock]
    var actionItems: [ActionItem]
    var studyItems: [StudyItem]
    var isPinned: Bool
    var transcriptionState: TranscriptionState

    enum TranscriptionState: String, Codable {
        case processing
        case complete
        case unavailable
    }

    init(id: UUID = UUID(), title: String, recordedAt: Date = .now, duration: TimeInterval = 0, transcript: String = "", transcriptSegments: [TranscriptSegment] = [], notes: String = "", course: String = "", topic: String = "", template: NoteTemplate = .lecture, summary: String = "", enhancedNotes: String = "", enhancedBlocks: [EnhancedNoteBlock] = [], actionItems: [ActionItem] = [], studyItems: [StudyItem] = [], isPinned: Bool = false, transcriptionState: TranscriptionState = .processing) {
        self.id = id
        self.title = title
        self.recordedAt = recordedAt
        self.duration = duration
        self.transcript = transcript
        self.transcriptSegments = transcriptSegments
        self.notes = notes
        self.course = course
        self.topic = topic
        self.template = template
        self.summary = summary
        self.enhancedNotes = enhancedNotes
        self.enhancedBlocks = enhancedBlocks
        self.actionItems = actionItems
        self.studyItems = studyItems
        self.isPinned = isPinned
        self.transcriptionState = transcriptionState
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, recordedAt, duration, transcript, transcriptSegments, notes, course, topic, template, summary, enhancedNotes, enhancedBlocks, actionItems, studyItems, isPinned, transcriptionState
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        transcript = try values.decode(String.self, forKey: .transcript)
        transcriptSegments = try values.decodeIfPresent([TranscriptSegment].self, forKey: .transcriptSegments) ?? []
        notes = try values.decode(String.self, forKey: .notes)
        course = try values.decodeIfPresent(String.self, forKey: .course) ?? ""
        topic = try values.decodeIfPresent(String.self, forKey: .topic) ?? ""
        template = (try? values.decodeIfPresent(NoteTemplate.self, forKey: .template)) ?? .lecture
        summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
        enhancedNotes = try values.decodeIfPresent(String.self, forKey: .enhancedNotes) ?? ""
        enhancedBlocks = try values.decodeIfPresent([EnhancedNoteBlock].self, forKey: .enhancedBlocks) ?? []
        actionItems = try values.decodeIfPresent([ActionItem].self, forKey: .actionItems) ?? []
        studyItems = try values.decodeIfPresent([StudyItem].self, forKey: .studyItems) ?? []
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        transcriptionState = try values.decode(TranscriptionState.self, forKey: .transcriptionState)
    }

    var displayTitle: String { title.isEmpty ? "Untitled note" : title }

    var hasEnhancedContent: Bool {
        !summary.isEmpty || !enhancedBlocks.isEmpty || !enhancedNotes.isEmpty || !actionItems.isEmpty
    }

    var canEnhance: Bool { transcriptionState == .complete && !transcriptSegments.isEmpty }
}

struct TranscriptSegment: Codable, Hashable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

struct EnhancedNoteBlock: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    let sourceIndex: Int
    var wasEdited: Bool
    var section: String?

    init(text: String, sourceIndex: Int, section: String? = nil, wasEdited: Bool = false) {
        id = UUID()
        self.text = text
        self.sourceIndex = sourceIndex
        self.section = section
        self.wasEdited = wasEdited
    }
}

struct ActionItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var isDone: Bool
    var sourceIndex: Int?

    init(text: String, isDone: Bool = false, sourceIndex: Int? = nil) {
        id = UUID()
        self.text = text
        self.isDone = isDone
        self.sourceIndex = sourceIndex
    }
}

struct StudyItem: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: StudyKind
    var title: String
    var detail: String
    var sourceIndex: Int

    init(kind: StudyKind, title: String, detail: String, sourceIndex: Int) {
        id = UUID()
        self.kind = kind
        self.title = title
        self.detail = detail
        self.sourceIndex = sourceIndex
    }
}

enum StudyKind: String, Codable, CaseIterable {
    case takeaway, concept, definition, example, question, flashcard, quiz

    var title: String { rawValue.capitalized }
}

enum NoteTemplate: String, Codable, CaseIterable, Identifiable {
    case lecture, seminar, lab, studyGroup, officeHours, meeting, interview

    var id: Self { self }

    var title: String {
        switch self {
        case .lecture: "Lecture"
        case .seminar: "Seminar"
        case .lab: "Lab"
        case .studyGroup: "Study group"
        case .officeHours: "Office hours"
        case .meeting: "Meeting"
        case .interview: "Interview"
        }
    }

    var symbol: String {
        switch self {
        case .lecture: "graduationcap"
        case .seminar: "bubble.left.and.bubble.right"
        case .lab: "flask"
        case .studyGroup: "person.3"
        case .officeHours: "person.crop.circle.badge.questionmark"
        case .meeting: "person.2"
        case .interview: "mic"
        }
    }

    /// Structure the model follows when writing enhanced notes.
    var guidance: String {
        switch self {
        case .lecture:
            "This is a lecture. Organize notes by the concepts taught, capture definitions, formulas, and worked examples, and flag anything the lecturer said will be on an exam."
        case .seminar:
            "This is a seminar or discussion. Capture the central arguments, the positions different people took, supporting evidence, and open questions."
        case .lab:
            "This is a lab session. Capture the procedure steps, equipment or setup, safety notes, expected results, and what must be submitted."
        case .studyGroup:
            "This is a study group. Capture the topics reviewed, explanations that clarified confusion, remaining questions, and who is covering what."
        case .officeHours:
            "This is office hours. Capture each question asked, the instructor's answer, hints for assignments, and follow-ups."
        case .meeting:
            "This is a meeting. Capture decisions made, key discussion points, owners, and next steps."
        case .interview:
            "This is an interview. Capture the questions asked, the key points of each answer, notable quotes, and impressions."
        }
    }

    var actionItemsTitle: String {
        switch self {
        case .meeting, .interview: "Next steps"
        default: "To-dos & deadlines"
        }
    }
}
