import SwiftUI

enum ChatScope: String, Hashable {
    case current, course, all
}

/// Conversation with your notes. Answers cite transcript passages you can jump to.
struct ChatPanel: View {
    @Bindable var library: LectureLibrary
    let currentLecture: Lecture?
    let openSource: (AnswerSource) -> Void

    @State private var scope: ChatScope
    @State private var question = ""
    @FocusState private var inputFocused: Bool

    init(library: LectureLibrary, currentLecture: Lecture?, openSource: @escaping (AnswerSource) -> Void) {
        self.library = library
        self.currentLecture = currentLecture
        self.openSource = openSource
        _scope = State(initialValue: currentLecture == nil ? .all : .current)
    }

    private var course: String? {
        guard let course = currentLecture?.course, !course.isEmpty else { return nil }
        return course
    }

    private var key: String {
        switch scope {
        case .current: "note:\(currentLecture?.id.uuidString ?? "")"
        case .course: "course:\(course ?? "")"
        case .all: "all"
        }
    }

    private var scopeTitle: String {
        switch scope {
        case .current: "This note"
        case .course: course ?? "Course"
        case .all: "All notes"
        }
    }

    private var scopedLectures: [Lecture] {
        switch scope {
        case .all: return library.lectures
        case .current: return currentLecture.map { [$0] } ?? library.lectures
        case .course: return library.lectures.filter { $0.course == course }
        }
    }

    private var exchanges: [ChatExchange] { library.chat(for: key) }
    private var isAsking: Bool { exchanges.last?.isPending == true }

    private var suggestions: [String] {
        switch scope {
        case .current:
            ["Summarize this in five bullets", "What’s most likely to be on the exam?",
             "Explain the hardest idea simply", "What did my notes miss?", "Quiz me with three questions"]
        case .course:
            ["What are the recurring themes in this course?", "What should I review before the exam?",
             "Which ideas build on earlier sessions?"]
        case .all:
            ["What did I cover this week?", "Where was a definition first introduced?",
             "What assignments were mentioned recently?"]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Search in", selection: $scope) {
                        if currentLecture != nil { Label("This note", systemImage: "doc.text").tag(ChatScope.current) }
                        if let course { Label(course, systemImage: "folder").tag(ChatScope.course) }
                        Label("All notes", systemImage: "tray.full").tag(ChatScope.all)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(scopeTitle, systemImage: "scope").labelStyle(ChipLabelStyle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .glassEffect(.regular.interactive(), in: .capsule)
                .help("Choose what to search")
                Spacer()
                if !exchanges.isEmpty {
                    Button {
                        library.clearChat(for: key)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("New conversation")
                    .disabled(isAsking)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if exchanges.isEmpty {
                            suggestionList
                        } else {
                            ForEach(exchanges) { exchange in
                                ExchangeView(exchange: exchange, showsLectureTitle: scope != .current) { source in
                                    openSource(source)
                                }
                                .id(exchange.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .onChange(of: exchanges.count) { _, _ in
                    if let last = exchanges.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            HStack(spacing: 8) {
                TextField("Ask anything", text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { ask(question) }
                Button {
                    ask(question)
                } label: {
                    Image(systemName: isAsking ? "ellipsis" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(.white)
                        .background(canSend ? Color.accentColor : Color.secondary.opacity(0.4), in: Circle())
                        .symbolEffect(.variableColor.iterative, isActive: isAsking)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityLabel("Send question")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 19))
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .onAppear { inputFocused = true }
    }

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAsking && !scopedLectures.isEmpty
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "Try asking")
                .padding(.top, 4)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    ask(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        Text(suggestion)
                            .font(.system(size: 13))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            }
        }
    }

    private func ask(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isAsking, !scopedLectures.isEmpty else { return }
        question = ""
        let lectures = scopedLectures
        let key = key
        Task { await library.ask(prompt, in: lectures, key: key) }
    }
}

private struct ExchangeView: View {
    let exchange: ChatExchange
    let showsLectureTitle: Bool
    let openSource: (AnswerSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 40)
                Text(exchange.question)
                    .font(.system(size: 13, weight: .medium))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.25)), in: .rect(cornerRadius: 14))
            }

            if let answer = exchange.answer {
                Text(answer.text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                if !answer.sources.isEmpty {
                    FlowSources(sources: answer.sources, showsLectureTitle: showsLectureTitle, openSource: openSource)
                }
            } else if let error = exchange.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading your notes…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct FlowSources: View {
    let sources: [AnswerSource]
    let showsLectureTitle: Bool
    let openSource: (AnswerSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources) { source in
                Button {
                    openSource(source)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(source.start.formattedDuration)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            if showsLectureTitle {
                                Text(source.lectureTitle)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(source.text)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .help("Open in transcript")
            }
        }
    }
}

/// Library-wide chat, opened from the toolbar outside a note.
struct GlobalChatSheet: View {
    @Bindable var library: LectureLibrary
    let openSource: (AnswerSource) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PageTitle(text: "Ask your notes")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            ChatPanel(library: library, currentLecture: nil) { source in
                openSource(source)
                dismiss()
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }
}
