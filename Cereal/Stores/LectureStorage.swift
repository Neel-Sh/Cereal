import Foundation

struct LectureStorage {
    private let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
            return
        }
        #if DEBUG
        if let debugRoot = DebugSnapshot.storageRoot {
            self.root = debugRoot
            return
        }
        #endif
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = applicationSupport.appendingPathComponent("Cereal", isDirectory: true)
    }

    func audioURL(for id: UUID) -> URL {
        root.appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension("m4a")
    }

    /// Separate microphone ("me") and computer audio ("them") tracks kept for call recordings.
    func trackURL(for id: UUID, speaker: Speaker) -> URL {
        root.appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).\(speaker == .me ? "mic" : "system").m4a")
    }

    func hasSpeakerTracks(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: trackURL(for: id, speaker: .them).path)
    }

    func load() throws -> [Lecture] {
        let index = root.appendingPathComponent("lectures.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        let data = try Data(contentsOf: index)
        return try JSONDecoder().decode([Lecture].self, from: data)
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func loadDraft() throws -> LectureDraft? {
        let url = root.appendingPathComponent("draft.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(LectureDraft.self, from: Data(contentsOf: url))
    }

    func saveDraft(_ draft: LectureDraft) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: root.appendingPathComponent("draft.json"), options: .atomic)
    }

    func save(_ lectures: [Lecture]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(lectures)
        try data.write(to: root.appendingPathComponent("lectures.json"), options: .atomic)
    }

    func prepareAudioDirectory() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Recordings", isDirectory: true), withIntermediateDirectories: true)
    }

    func deleteAudio(for id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(for: id))
        try? FileManager.default.removeItem(at: trackURL(for: id, speaker: .me))
        try? FileManager.default.removeItem(at: trackURL(for: id, speaker: .them))
    }
}

struct LectureDraft: Codable {
    var title: String
    var notes: String
    var course: String
    var topic: String
    var template: NoteTemplate? = nil
    var recordingID: UUID? = nil
    var startedAt: Date? = nil
    var captureMode: CaptureMode? = nil

    var isEmpty: Bool {
        title.isEmpty && notes.isEmpty && course.isEmpty && topic.isEmpty && recordingID == nil
    }
}
