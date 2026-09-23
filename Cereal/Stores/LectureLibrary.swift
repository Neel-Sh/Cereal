import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class LectureLibrary {
    private(set) var lectures: [Lecture] = []
    private(set) var isRecording = false
    private(set) var isStarting = false
    private(set) var isStopping = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var waveformLevels: [Float] = []
    private(set) var generatingIDs: Set<UUID> = []
    private(set) var canRetrySaving = false
    private(set) var isRecovering = false
    var selectedID: UUID?
    var seekRequest: SeekRequest?
    var showRecorder = false
    var errorMessage: String?
    var draftTitle = ""
    var draftNotes = ""
    var draftCourse = ""
    var draftTopic = ""
    var draftTemplate: NoteTemplate = .lecture
    var captureMode: CaptureMode = .microphone
    private(set) var isPaused = false
    private(set) var chats: [String: [ChatExchange]] = [:]
    let liveTranscriber = LiveTranscriber()
    let calendar = CalendarContext()

    private let storage: LectureStorage
    private let recorder = MicrophoneRecorder()
    private let meetingRecorder = MeetingRecorder()
    private let transcriber = LectureTranscriber()
    private let intelligence = LectureIntelligence()
    private var meterTimer: Timer?
    private var recordingID: UUID?
    private var recordingStartedAt: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private(set) var activeCaptureMode: CaptureMode = .microphone

    var canPause: Bool { isRecording && !isStopping }
    var isBusy: Bool { isRecording || isStarting || isStopping || canRetrySaving || isRecovering }

    init(storage: LectureStorage? = nil) {
        self.storage = storage ?? LectureStorage()
        do {
            lectures = try self.storage.load()
            selectedID = lectures.first?.id
            for lecture in lectures where lecture.transcriptionState == .processing {
                Task { await transcribe(id: lecture.id) }
            }
        } catch {
            errorMessage = "Saved lectures could not be loaded: \(error.localizedDescription)"
        }
        do {
            if let draft = try self.storage.loadDraft(), !draft.isEmpty {
                draftTitle = draft.title
                draftNotes = draft.notes
                draftCourse = draft.course
                draftTopic = draft.topic
                draftTemplate = draft.template ?? .lecture
                showRecorder = true
                if let id = draft.recordingID, !lectures.contains(where: { $0.id == id }) {
                    if FileManager.default.fileExists(atPath: self.storage.audioURL(for: id).path) {
                        recover(draft, id: id)
                    } else if draft.captureMode == .online, self.storage.hasSpeakerTracks(for: id) {
                        recordingID = id
                        recordingStartedAt = draft.startedAt
                        activeCaptureMode = .online
                        isRecovering = true
                        Task { await recoverOnline(draft, id: id) }
                    }
                }
            }
        } catch {
            errorMessage = "Saved draft could not be loaded: \(error.localizedDescription)"
        }
    }

    var selectedLecture: Lecture? {
        lectures.first { $0.id == selectedID }
    }

    func startRecording() async {
        guard !isRecording && !isStarting && !canRetrySaving && !isRecovering else { return }
        isStarting = true
        defer { isStarting = false }

        do {
            let id = UUID()
            let sources: [(speaker: Speaker?, feed: LiveAudioFeed)]
            if captureMode == .online {
                sources = [(.me, LiveAudioFeed()), (.them, LiveAudioFeed())]
                try await meetingRecorder.start(microphoneURL: storage.trackURL(for: id, speaker: .me),
                                                systemURL: storage.trackURL(for: id, speaker: .them),
                                                microphoneFeed: sources[0].feed, systemFeed: sources[1].feed)
            } else {
                sources = [(nil, LiveAudioFeed())]
                try await recorder.start(at: storage.audioURL(for: id), feed: sources[0].feed)
            }
            activeCaptureMode = captureMode
            recordingID = id
            recordingStartedAt = .now
            pausedAt = nil
            pausedDuration = 0
            isPaused = false
            persistDraft()
            elapsed = 0
            waveformLevels = []
            isRecording = true
            showRecorder = true
            liveTranscriber.reset()
            Task { await liveTranscriber.start(sources: sources) }
            meterTimer?.invalidate()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.refreshMeter() }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard isRecording, !isStopping, let id = recordingID, let startedAt = recordingStartedAt else { return }
        isStopping = true
        Task { await finishRecording(id: id, startedAt: startedAt) }
    }

    func togglePause() {
        guard canPause else { return }
        if isPaused {
            do {
                if activeCaptureMode == .online { try meetingRecorder.resume() } else { try recorder.resume() }
                if let pausedAt { pausedDuration += Date().timeIntervalSince(pausedAt) }
                pausedAt = nil
                isPaused = false
            } catch {
                errorMessage = "Recording could not resume: \(error.localizedDescription)"
            }
        } else {
            if activeCaptureMode == .online { meetingRecorder.pause() } else { recorder.pause() }
            pausedAt = .now
            isPaused = true
        }
    }

    func retrySaving() {
        guard canRetrySaving, !isStopping,
              let id = recordingID, let startedAt = recordingStartedAt else { return }
        isStopping = true
        Task { await finishRecording(id: id, startedAt: startedAt) }
    }

    private func finishRecording(id: UUID, startedAt: Date) async {
        meterTimer?.invalidate()
        meterTimer = nil
        await liveTranscriber.stop()
        let duration: TimeInterval
        do {
            if activeCaptureMode == .online {
                meetingRecorder.stop()
                duration = try await MeetingRecorder.mix(microphoneURL: storage.trackURL(for: id, speaker: .me),
                                                         systemURL: storage.trackURL(for: id, speaker: .them),
                                                         to: storage.audioURL(for: id))
            } else {
                duration = recorder.stop()
            }
        } catch {
            isStopping = false
            isRecording = false
            canRetrySaving = activeCaptureMode == .online && storage.hasSpeakerTracks(for: id)
            errorMessage = "Could not finish recording: \(error.localizedDescription)"
            return
        }
        isRecording = false
        isStopping = false
        isPaused = false
        pausedAt = nil
        canRetrySaving = false
        waveformLevels = []
        elapsed = 0
        recordingID = nil
        recordingStartedAt = nil

        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let lecture = Lecture(id: id, title: title.isEmpty ? Self.defaultTitle(for: startedAt) : title, recordedAt: startedAt, duration: duration, notes: draftNotes, course: draftCourse.trimmingCharacters(in: .whitespacesAndNewlines), topic: draftTopic.trimmingCharacters(in: .whitespacesAndNewlines), template: draftTemplate)
        lectures.insert(lecture, at: 0)
        selectedID = id
        showRecorder = false

        do {
            try storage.save(lectures)
        } catch {
            showRecorder = true
            errorMessage = "The recording was saved, but its details could not be indexed: \(error.localizedDescription)"
            return
        }
        draftTitle = ""
        draftNotes = ""
        draftCourse = ""
        draftTopic = ""
        persistDraft()
        liveTranscriber.reset()
        Task { await transcribe(id: id) }
    }

    func updateTitle(_ title: String, for id: UUID) {
        update(id) { $0.title = title }
    }

    func updateTemplate(_ template: NoteTemplate, for id: UUID) {
        update(id) { $0.template = template }
    }

    func togglePin(_ id: UUID) {
        update(id) { $0.isPinned.toggle() }
    }

    func toggleActionItem(_ itemID: UUID, for id: UUID) {
        update(id) { lecture in
            guard let index = lecture.actionItems.firstIndex(where: { $0.id == itemID }) else { return }
            lecture.actionItems[index].isDone.toggle()
        }
    }

    func updateActionItem(_ itemID: UUID, text: String, for id: UUID) {
        update(id) { lecture in
            guard let index = lecture.actionItems.firstIndex(where: { $0.id == itemID }) else { return }
            lecture.actionItems[index].text = text
        }
    }

    func addActionItem(for id: UUID) {
        update(id) { $0.actionItems.append(ActionItem(text: "")) }
    }

    func removeActionItem(_ itemID: UUID, for id: UUID) {
        update(id) { $0.actionItems.removeAll { $0.id == itemID } }
    }

    func updateSummary(_ summary: String, for id: UUID) {
        update(id) { $0.summary = summary }
    }

    func applyCalendarEvent(_ event: CalendarEvent) {
        draftTitle = event.title
        persistDraft()
    }

    /// Starts a computer-audio recording with the Meeting template, named after the calendar event
    /// or the calling app unless the user already typed a title.
    func startCallRecording(appName: String?) async {
        guard !isBusy else { return }
        calendar.refresh()
        captureMode = .online
        draftTemplate = .meeting
        if draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let event = calendar.currentEvent {
                draftTitle = event.title
            } else if let appName {
                draftTitle = "\(appName) call"
            }
        }
        showRecorder = true
        persistDraft()
        await startRecording()
    }

    func chat(for key: String) -> [ChatExchange] { chats[key] ?? [] }

    func clearChat(for key: String) { chats[key] = nil }

    func ask(_ question: String, in lectures: [Lecture], key: String) async {
        let history = chat(for: key).compactMap { exchange in
            exchange.answer.map { ChatTurn(question: exchange.question, answer: $0.text) }
        }
        let exchange = ChatExchange(question: question)
        chats[key, default: []].append(exchange)
        do {
            let answer = try await intelligence.answer(question, from: lectures, history: history)
            updateExchange(exchange.id, key: key) { $0.answer = answer }
        } catch {
            updateExchange(exchange.id, key: key) { $0.errorMessage = error.localizedDescription }
        }
    }

    private func updateExchange(_ id: UUID, key: String, change: (inout ChatExchange) -> Void) {
        guard let index = chats[key]?.firstIndex(where: { $0.id == id }) else { return }
        change(&chats[key]![index])
    }

    static func defaultTitle(for date: Date) -> String {
        "Note · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private static func isDefaultTitle(_ title: String) -> Bool {
        title.isEmpty || title.hasPrefix("Note · ") || title.hasPrefix("Lecture · ") || title == "Recovered lecture"
    }

    func persistDraft() {
        do {
            try storage.saveDraft(LectureDraft(title: draftTitle, notes: draftNotes,
                                               course: draftCourse, topic: draftTopic,
                                               template: draftTemplate,
                                               recordingID: recordingID,
                                               startedAt: recordingStartedAt,
                                               captureMode: recordingID == nil ? nil : activeCaptureMode))
        } catch {
            errorMessage = "Draft notes could not be saved: \(error.localizedDescription)"
        }
    }

    func updateNotes(_ notes: String, for id: UUID) {
        update(id) { $0.notes = notes }
    }

    func updateCourse(_ course: String, for id: UUID) {
        update(id) { $0.course = course }
    }

    func updateTopic(_ topic: String, for id: UUID) {
        update(id) { $0.topic = topic }
    }

    func updateEnhancedNotes(_ notes: String, for id: UUID) {
        update(id) { $0.enhancedNotes = notes }
    }

    func updateEnhancedBlock(_ blockID: UUID, text: String, for id: UUID) {
        update(id) { lecture in
            guard let index = lecture.enhancedBlocks.firstIndex(where: { $0.id == blockID }) else { return }
            lecture.enhancedBlocks[index].text = text
            lecture.enhancedBlocks[index].wasEdited = true
            lecture.enhancedNotes = lecture.enhancedBlocks.map(\.text).joined(separator: "\n\n")
        }
    }

    func enhance(_ id: UUID) async {
        guard let lecture = lectures.first(where: { $0.id == id }),
              lecture.transcriptionState == .complete,
              !generatingIDs.contains(id) else { return }
        generatingIDs.insert(id)
        defer { generatingIDs.remove(id) }
        do {
            let result = try await intelligence.enhance(lecture)
            update(id) {
                if Self.isDefaultTitle($0.title) && !result.title.isEmpty { $0.title = result.title }
                $0.summary = result.summary
                $0.enhancedNotes = result.notes
                $0.enhancedBlocks = result.blocks
                let finished = Set($0.actionItems.filter(\.isDone).map { $0.text.lowercased() })
                $0.actionItems = result.actionItems.map { item in
                    var item = item
                    item.isDone = finished.contains(item.text.lowercased())
                    return item
                }
                $0.studyItems = result.items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func jump(to lectureID: UUID, time: TimeInterval) {
        selectedID = lectureID
        showRecorder = false
        seekRequest = SeekRequest(lectureID: lectureID, time: time)
    }

    func consumeSeekRequest(for lectureID: UUID) -> TimeInterval? {
        guard seekRequest?.lectureID == lectureID else { return nil }
        let time = seekRequest?.time
        seekRequest = nil
        return time
    }

    func retryTranscription(for id: UUID) {
        update(id) { $0.transcriptionState = .processing }
        Task { await transcribe(id: id) }
    }

    func audioURL(for id: UUID) -> URL { storage.audioURL(for: id) }

    func delete(_ id: UUID) {
        guard let index = lectures.firstIndex(where: { $0.id == id }) else { return }
        let removed = lectures.remove(at: index)
        do {
            try storage.save(lectures)
            storage.deleteAudio(for: id)
            if selectedID == id { selectedID = lectures.first?.id }
        } catch {
            lectures.insert(removed, at: index)
            errorMessage = "Could not delete this lecture: \(error.localizedDescription)"
        }
    }

    private func refreshMeter() {
        let now = pausedAt ?? Date()
        elapsed = recordingStartedAt.map { now.timeIntervalSince($0) - pausedDuration } ?? 0
        waveformLevels = activeCaptureMode == .online ? meetingRecorder.levels : recorder.levels
    }

    private func update(_ id: UUID, change: (inout Lecture) -> Void) {
        guard let index = lectures.firstIndex(where: { $0.id == id }) else { return }
        let old = lectures[index]
        change(&lectures[index])
        do {
            try storage.save(lectures)
        } catch {
            lectures[index] = old
            errorMessage = "Changes could not be saved: \(error.localizedDescription)"
        }
    }

    private func transcribe(id: UUID) async {
        do {
            let segments = storage.hasSpeakerTracks(for: id)
                ? try await transcriber.transcribeCall(microphone: storage.trackURL(for: id, speaker: .me),
                                                       system: storage.trackURL(for: id, speaker: .them))
                : try await transcriber.transcribe(storage.audioURL(for: id))
            update(id) {
                $0.transcriptSegments = segments
                $0.transcript = segments.map(\.text).joined(separator: " ")
                $0.summary = ""
                $0.enhancedNotes = ""
                $0.enhancedBlocks = []
                $0.actionItems = []
                $0.studyItems = []
                $0.transcriptionState = .complete
            }
        } catch {
            update(id) { $0.transcriptionState = .unavailable }
            errorMessage = "Audio saved. Transcription could not finish: \(error.localizedDescription)"
        }
    }

    private func recoverOnline(_ draft: LectureDraft, id: UUID) async {
        defer { isRecovering = false }
        do {
            _ = try await MeetingRecorder.mix(microphoneURL: storage.trackURL(for: id, speaker: .me),
                                              systemURL: storage.trackURL(for: id, speaker: .them),
                                              to: storage.audioURL(for: id))
            var currentDraft = draft
            currentDraft.title = draftTitle
            currentDraft.notes = draftNotes
            currentDraft.course = draftCourse
            currentDraft.topic = draftTopic
            recover(currentDraft, id: id)
        } catch {
            errorMessage = "Recovered your notes, but the interrupted online audio could not be finalized: \(error.localizedDescription)"
        }
    }

    private func recover(_ draft: LectureDraft, id: UUID) {
        guard !lectures.contains(where: { $0.id == id }) else { return }
        let duration = (try? AVAudioPlayer(contentsOf: storage.audioURL(for: id)))?.duration ?? 0
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lecture = Lecture(id: id,
                              title: title.isEmpty ? "Recovered lecture" : title,
                              recordedAt: draft.startedAt ?? .now,
                              duration: duration,
                              notes: draft.notes, course: draft.course, topic: draft.topic,
                              template: draft.template ?? .lecture)
        lectures.insert(lecture, at: 0)
        selectedID = id
        showRecorder = false
        do {
            try storage.save(lectures)
            draftTitle = ""
            draftNotes = ""
            draftCourse = ""
            draftTopic = ""
            recordingID = nil
            recordingStartedAt = nil
            persistDraft()
            Task { await transcribe(id: id) }
        } catch {
            showRecorder = true
            errorMessage = "Recovered audio and notes, but could not index them: \(error.localizedDescription)"
        }
    }
}

struct ChatExchange: Identifiable {
    let id = UUID()
    let question: String
    var answer: LectureAnswer?
    var errorMessage: String?

    var isPending: Bool { answer == nil && errorMessage == nil }
}

struct SeekRequest: Equatable {
    let lectureID: UUID
    let time: TimeInterval
}

enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case microphone, online
    var id: Self { self }
    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .online: "Computer + microphone"
        }
    }
}
