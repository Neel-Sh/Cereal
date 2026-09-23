import SwiftUI
import UniformTypeIdentifiers

struct LectureDetailView: View {
    @Bindable var library: LectureLibrary
    let lecture: Lecture
    @Binding var sidePanel: SidePanel?
    @State private var playback = AudioPlayback()
    @State private var selectedPane: DetailPane = .notes
    @State private var exportDocument: LectureExportDocument?
    @State private var exportType: UTType = .markdown
    @State private var showingExport = false
    @State private var confirmingDelete = false
    @FocusState private var titleFocused: Bool

    private var isGenerating: Bool { library.generatingIDs.contains(lecture.id) }

    private var courses: [String] {
        Array(Set(library.lectures.map(\.course).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        PageColumn {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 12)
                    .padding(.bottom, 22)
                paneContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .toolbar { toolbarContent }
        .inspector(isPresented: Binding(
            get: { sidePanel != nil },
            set: { if !$0 { sidePanel = nil } }
        )) {
            SidePanelView(library: library, lecture: lecture, playback: playback, panel: $sidePanel)
                .inspectorColumnWidth(min: 340, ideal: 400, max: 520)
        }
        .defaultFocus($titleFocused, false)
        .onAppear {
            DispatchQueue.main.async { titleFocused = false }
            playback.load(library.audioURL(for: lecture.id))
            if let time = library.consumeSeekRequest(for: lecture.id) { playback.seek(to: time) }
            if lecture.hasEnhancedContent { selectedPane = .enhanced }
            #if DEBUG
            if DebugSnapshot.scene.contains("notes") { selectedPane = .notes }
            if DebugSnapshot.scene.contains("study") { selectedPane = .study }
            if DebugSnapshot.scene.contains("run-enhance") { Task { await library.enhance(lecture.id) } }
            if DebugSnapshot.scene.contains("run-ask") {
                sidePanel = .ask
                let key = "note:\(lecture.id.uuidString)"
                Task {
                    await library.ask("What is due next Friday?", in: [lecture], key: key)
                    await library.ask("And what should I read before then?", in: [lecture], key: key)
                }
            }
            #endif
        }
        .onChange(of: library.seekRequest) { _, request in
            if request?.lectureID == lecture.id,
               let time = library.consumeSeekRequest(for: lecture.id) { playback.seek(to: time) }
        }
        .onChange(of: isGenerating) { _, generating in
            if generating { selectedPane = .enhanced }
        }
        .onDisappear { playback.stop() }
        .alert("Playback unavailable", isPresented: Binding(
            get: { playback.errorMessage != nil },
            set: { if !$0 { playback.dismissError() } }
        )) {
            Button("OK") { playback.dismissError() }
        } message: {
            Text(playback.errorMessage ?? "")
        }
        .confirmationDialog("Delete this note and its recording?", isPresented: $confirmingDelete) {
            Button("Delete Note", role: .destructive) { library.delete(lecture.id) }
        } message: {
            Text("This cannot be undone.")
        }
        .fileExporter(isPresented: $showingExport, document: exportDocument,
                      contentType: exportType, defaultFilename: lecture.displayTitle) { result in
            if case .failure(let error) = result { library.errorMessage = error.localizedDescription }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Untitled note", text: Binding(
                get: { lecture.title },
                set: { library.updateTitle($0, for: lecture.id) }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 30, weight: .regular, design: .serif))
            .lineLimit(1...3)
            .focused($titleFocused)
            .onSubmit { titleFocused = false }
            .accessibilityLabel("Note title")

            GlassEffectContainer(spacing: 6) {
                FlowLayout(spacing: 6) {
                    MetaChip(symbol: "calendar",
                             text: lecture.recordedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    MetaChip(symbol: "clock", text: lecture.duration.formattedDuration)
                    EditableChip(symbol: "folder", placeholder: "Course", text: Binding(
                        get: { lecture.course },
                        set: { library.updateCourse($0, for: lecture.id) }
                    ), suggestions: courses)
                    EditableChip(symbol: "number", placeholder: "Topic", text: Binding(
                        get: { lecture.topic },
                        set: { library.updateTopic($0, for: lecture.id) }
                    ))
                    TemplateChip(template: Binding(
                        get: { lecture.template },
                        set: { library.updateTemplate($0, for: lecture.id) }
                    ))
                    if lecture.transcriptionState == .processing {
                        MetaChip(symbol: "waveform", text: "Transcribing…", tint: .orange)
                    }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $selectedPane) {
                ForEach(DetailPane.allCases) { pane in
                    Text(pane.title).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 270)
            .background {
                ForEach(Array(DetailPane.allCases.enumerated()), id: \.element) { offset, pane in
                    Button("") { selectedPane = pane }
                        .keyboardShortcut(KeyEquivalent(Character("\(offset + 1)")), modifiers: .command)
                        .hidden()
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Copy Notes", systemImage: "doc.on.doc") {
                    LectureExport.copyToPasteboard(LectureExport.notesText(lecture))
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Copy Transcript", systemImage: "text.quote") {
                    LectureExport.copyToPasteboard(lecture.transcriptSegments.isEmpty
                        ? lecture.transcript
                        : lecture.transcriptSegments.map { "[\($0.start.formattedDuration)] \($0.labeledText)" }.joined(separator: "\n"))
                }
                .disabled(lecture.transcript.isEmpty)
                ShareLink(item: LectureExport.notesText(lecture), subject: Text(lecture.displayTitle)) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button("Export as Markdown…", systemImage: "doc.plaintext") {
                    exportType = .markdown
                    exportDocument = LectureExportDocument(data: LectureExport.markdown(lecture))
                    showingExport = true
                }
                Button("Export as PDF…", systemImage: "doc.richtext") {
                    guard let data = LectureExport.pdf(lecture) else { return }
                    exportType = .pdf
                    exportDocument = LectureExportDocument(data: data)
                    showingExport = true
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .menuIndicator(.hidden)
            .help("Share and export")

            Menu {
                Button(lecture.hasEnhancedContent ? "Regenerate Enhanced Notes" : "Enhance Notes", systemImage: "sparkles") {
                    Task { await library.enhance(lecture.id) }
                }
                .disabled(!lecture.canEnhance || isGenerating)
                .keyboardShortcut("e", modifiers: .command)
                Button(lecture.isPinned ? "Unpin" : "Pin to Top", systemImage: lecture.isPinned ? "pin.slash" : "pin") {
                    library.togglePin(lecture.id)
                }
                if lecture.transcriptionState != .processing {
                    Button("Retranscribe", systemImage: "arrow.clockwise") {
                        library.retryTranscription(for: lecture.id)
                    }
                }
                Divider()
                Button("Delete Note…", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .help("More")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button {
                sidePanel = sidePanel == nil ? .transcript : nil
            } label: {
                Label("Side Panel", systemImage: "sidebar.right")
            }
            .help(sidePanel == nil ? "Show transcript" : "Hide side panel")
        }
    }

    // MARK: Panes

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .notes:
            NotesEditor(text: Binding(
                get: { lecture.notes },
                set: { library.updateNotes($0, for: lecture.id) }
            ))
        case .enhanced:
            EnhancedNotesView(library: library, lecture: lecture, isGenerating: isGenerating, openSource: openSource)
        case .study:
            StudyItemsView(items: lecture.studyItems, segments: lecture.transcriptSegments,
                           canEnhance: lecture.canEnhance && !isGenerating,
                           enhance: { Task { await library.enhance(lecture.id) } },
                           openSource: openSource)
        }
    }

    private func openSource(_ time: TimeInterval) {
        playback.seek(to: time)
        sidePanel = .transcript
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        let compact = sidePanel != nil
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        playback.toggle()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playback.isPlaying ? "Pause recording" : "Play recording")
                    .disabled(playback.duration == 0)
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                    Text(compact ? "\(playback.position.formattedDuration) / \(playback.duration.formattedDuration)" : playback.position.formattedDuration)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    if !compact {
                        Slider(value: Binding(
                            get: { playback.position },
                            set: { playback.seek(to: $0) }
                        ), in: 0...max(playback.duration, 1))
                        .controlSize(.small)
                        .frame(width: 110)
                        .accessibilityLabel("Recording position")

                        Text(playback.duration.formattedDuration)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .frame(height: 40)
                .glassEffect(.regular.interactive(), in: .capsule)

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Enhancing…")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .glassEffect(.regular, in: .capsule)
                } else if !lecture.hasEnhancedContent && lecture.canEnhance {
                    Button {
                        Task { await library.enhance(lecture.id) }
                    } label: {
                        Label("Enhance", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                    .help("Enhance notes with Apple Intelligence (⌘E)")
                }

                if sidePanel != .ask {
                    Button {
                        sidePanel = .ask
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "sparkle")
                            if !compact {
                                Text("Ask anything")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, compact ? 13 : 16)
                        .frame(height: 40)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .keyboardShortcut("j", modifiers: .command)
                    .help("Ask about this note (⌘J)")
                    .disabled(lecture.transcriptionState != .complete)
                }
            }
        }
        .animation(.snappy, value: sidePanel)
        .padding(.bottom, 22)
        .padding(.top, 8)
    }
}

enum DetailPane: String, CaseIterable, Identifiable {
    case notes, enhanced, study
    var id: Self { self }
    var title: String {
        switch self {
        case .notes: "My notes"
        case .enhanced: "Enhanced"
        case .study: "Study"
        }
    }
}

// MARK: - Enhanced notes

private struct EnhancedNotesView: View {
    @Bindable var library: LectureLibrary
    let lecture: Lecture
    let isGenerating: Bool
    let openSource: (TimeInterval) -> Void

    private var sections: [(title: String?, blocks: [EnhancedNoteBlock])] {
        var result: [(title: String?, blocks: [EnhancedNoteBlock])] = []
        for block in lecture.enhancedBlocks {
            if let last = result.last, last.title == block.section {
                result[result.count - 1].blocks.append(block)
            } else {
                result.append((block.section, [block]))
            }
        }
        return result
    }

    var body: some View {
        if isGenerating && !lecture.hasEnhancedContent {
            EmptyPane(symbol: "sparkles", title: "Enhancing your notes",
                      message: "Apple Intelligence is reading the transcript on this Mac.") {
                ProgressView().controlSize(.small)
            }
        } else if !lecture.hasEnhancedContent {
            EmptyPane(symbol: "sparkles", title: "No enhanced notes yet", message: emptyMessage) {
                if lecture.canEnhance {
                    Button {
                        Task { await library.enhance(lecture.id) }
                    } label: {
                        Label("Enhance with \(lecture.template.title) template", systemImage: "sparkles")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if !lecture.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeading(text: "Summary")
                            TextField("Summary", text: Binding(
                                get: { lecture.summary },
                                set: { library.updateSummary($0, for: lecture.id) }
                            ), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .lineSpacing(5)
                        }
                    }

                    ActionItemsView(library: library, lecture: lecture, openSource: openSource)

                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 10) {
                            if let title = section.title {
                                Text(title)
                                    .font(.system(size: 18, weight: .semibold, design: .serif))
                            }
                            ForEach(section.blocks) { block in
                                EnhancedBlockRow(library: library, lecture: lecture, block: block, openSource: openSource)
                            }
                        }
                    }

                    if lecture.enhancedBlocks.isEmpty && !lecture.enhancedNotes.isEmpty {
                        NotesEditor(text: Binding(
                            get: { lecture.enhancedNotes },
                            set: { library.updateEnhancedNotes($0, for: lecture.id) }
                        ))
                        .frame(minHeight: 300)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
            .bottomFade()
        }
    }

    private var emptyMessage: String {
        switch lecture.transcriptionState {
        case .processing: "The transcript is still being prepared. Enhance becomes available when it’s done."
        case .unavailable: "A transcript is needed first. Retranscribe from the ••• menu."
        case .complete:
            lecture.transcriptSegments.isEmpty
                ? "Retranscribe this recording from the ••• menu to add timestamps."
                : "Turn your rough notes and the transcript into a summary, organized notes, and to-dos."
        }
    }
}

private struct EnhancedBlockRow: View {
    @Bindable var library: LectureLibrary
    let lecture: Lecture
    let block: EnhancedNoteBlock
    let openSource: (TimeInterval) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(.secondary)
                .frame(width: 4, height: 4)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            TextField("Note", text: Binding(
                get: { lecture.enhancedBlocks.first(where: { $0.id == block.id })?.text ?? block.text },
                set: { library.updateEnhancedBlock(block.id, text: $0, for: lecture.id) }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .lineSpacing(4)
            if lecture.transcriptSegments.indices.contains(block.sourceIndex) {
                SourceButton(time: lecture.transcriptSegments[block.sourceIndex].start, edited: block.wasEdited) {
                    openSource(lecture.transcriptSegments[block.sourceIndex].start)
                }
                .opacity(isHovering ? 1 : 0.35)
            }
        }
        .onHover { isHovering = $0 }
    }
}

private struct ActionItemsView: View {
    @Bindable var library: LectureLibrary
    let lecture: Lecture
    let openSource: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeading(text: lecture.template.actionItemsTitle)
                Spacer()
                Button {
                    library.addActionItem(for: lecture.id)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add a to-do")
            }
            if lecture.actionItems.isEmpty {
                Text("Nothing was assigned.")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            ForEach(lecture.actionItems) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        library.toggleActionItem(item.id, for: lecture.id)
                    } label: {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isDone ? Color.accentColor : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.isDone ? "Mark not done" : "Mark done")
                    TextField("To-do", text: Binding(
                        get: { lecture.actionItems.first(where: { $0.id == item.id })?.text ?? item.text },
                        set: { library.updateActionItem(item.id, text: $0, for: lecture.id) }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                    if let index = item.sourceIndex, lecture.transcriptSegments.indices.contains(index) {
                        SourceButton(time: lecture.transcriptSegments[index].start) {
                            openSource(lecture.transcriptSegments[index].start)
                        }
                    }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        library.removeActionItem(item.id, for: lecture.id)
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct EmptyPane<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .glassEffect(in: .circle)
            Text(title)
                .font(.system(size: 18, weight: .regular, design: .serif))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            actions.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }
}

// MARK: - Study

private struct StudyItemsView: View {
    let items: [StudyItem]
    let segments: [TranscriptSegment]
    let canEnhance: Bool
    let enhance: () -> Void
    let openSource: (TimeInterval) -> Void

    private var cards: [StudyItem] { items.filter { $0.kind == .flashcard || $0.kind == .quiz || $0.kind == .question } }
    private var reference: [StudyItem] { items.filter { $0.kind != .flashcard && $0.kind != .quiz && $0.kind != .question } }

    var body: some View {
        if items.isEmpty {
            EmptyPane(symbol: "books.vertical", title: "No study material yet",
                      message: "Enhance this note to generate key concepts, definitions, flashcards, and practice questions.") {
                if canEnhance {
                    Button("Enhance notes", systemImage: "sparkles", action: enhance)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if !cards.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(text: "Practice · \(cards.count) cards")
                            Text("Click a card to reveal the answer.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                                ForEach(cards) { item in
                                    Flashcard(item: item, time: time(for: item), openSource: openSource)
                                }
                            }
                        }
                    }
                    ForEach(StudyKind.allCases, id: \.self) { kind in
                        let section = reference.filter { $0.kind == kind }
                        if !section.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeading(text: kind.title + (section.count == 1 ? "" : "s"))
                                ForEach(section) { item in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(item.title).font(.system(size: 15, weight: .semibold))
                                            Spacer()
                                            if let time = time(for: item) {
                                                SourceButton(time: time) { openSource(time) }
                                            }
                                        }
                                        Text(item.detail)
                                            .font(.system(size: 14))
                                            .foregroundStyle(.secondary)
                                            .lineSpacing(3)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
            .bottomFade()
        }
    }

    private func time(for item: StudyItem) -> TimeInterval? {
        segments.indices.contains(item.sourceIndex) ? segments[item.sourceIndex].start : nil
    }
}

private struct Flashcard: View {
    let item: StudyItem
    let time: TimeInterval?
    let openSource: (TimeInterval) -> Void
    @State private var revealed = false

    var body: some View {
        Button {
            withAnimation(.snappy) { revealed.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.kind == .flashcard ? "Flashcard" : "Question")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.leading)
                if revealed {
                    Divider()
                    Text(item.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer(minLength: 0)
                HStack {
                    Text(revealed ? "Hide answer" : "Show answer")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let time, revealed {
                        SourceButton(time: time) { openSource(time) }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Side panel

private struct SidePanelView: View {
    @Bindable var library: LectureLibrary
    let lecture: Lecture
    @Bindable var playback: AudioPlayback
    @Binding var panel: SidePanel?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: Binding(
                get: { panel ?? .transcript },
                set: { panel = $0 }
            )) {
                ForEach(SidePanel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .padding(.top, 10)
            .padding(.bottom, 14)

            switch panel ?? .transcript {
            case .transcript:
                TranscriptPanel(library: library, lecture: lecture, playback: playback)
            case .ask:
                ChatPanel(library: library, currentLecture: lecture) { source in
                    if source.lectureID == lecture.id {
                        playback.seek(to: source.start)
                        panel = .transcript
                    } else {
                        library.jump(to: source.lectureID, time: source.start)
                        panel = .transcript
                    }
                }
            }
        }
    }
}

private struct TranscriptPanel: View {
    @Bindable var library: LectureLibrary
    let lecture: Lecture
    @Bindable var playback: AudioPlayback
    @State private var filter = ""

    private var paragraphs: [String] {
        TranscriptParagraphs.make(from: lecture.transcript)
    }

    private var visibleIndices: [Int] {
        guard !filter.isEmpty else { return Array(lecture.transcriptSegments.indices) }
        return lecture.transcriptSegments.indices.filter { lecture.transcriptSegments[$0].text.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if lecture.transcriptionState == .complete && !lecture.transcriptSegments.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find in transcript", text: $filter)
                        .textFieldStyle(.plain)
                    if !filter.isEmpty {
                        Text("\(visibleIndices.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button {
                            filter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        switch lecture.transcriptionState {
                        case .processing:
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Transcribing on device…")
                            }
                            Text("The recording is saved. The transcript will appear here when it’s ready.")
                                .foregroundStyle(.secondary)
                        case .complete:
                            if lecture.transcriptSegments.isEmpty && paragraphs.isEmpty {
                                Text("No speech was detected in this recording.")
                                    .foregroundStyle(.secondary)
                            } else if !lecture.transcriptSegments.isEmpty {
                                ForEach(visibleIndices, id: \.self) { index in
                                    let segment = lecture.transcriptSegments[index]
                                    let isCurrent = playback.position >= segment.start && playback.position < segment.end
                                    Button {
                                        playback.seek(to: segment.start)
                                        if !playback.isPlaying { playback.toggle() }
                                    } label: {
                                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                                            Text(segment.start.formattedDuration)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .frame(width: 44, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 3) {
                                                if let speaker = segment.speaker,
                                                   index == 0 || lecture.transcriptSegments[index - 1].speaker != speaker || visibleIndices.first == index {
                                                    SpeakerLabel(speaker: speaker)
                                                }
                                                Text(segment.text)
                                                    .font(.system(size: 14))
                                                    .lineSpacing(4)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .background(isCurrent && playback.isPlaying ? Color.accentColor.opacity(0.14) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 10))
                                    .id(index)
                                }
                            } else {
                                ForEach(paragraphs.indices, id: \.self) { index in
                                    Text(paragraphs[index])
                                        .font(.system(size: 14))
                                        .lineSpacing(6)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.bottom, 10)
                                }
                                Button("Add timestamps") { library.retryTranscription(for: lecture.id) }
                                    .buttonStyle(.glass)
                            }
                        case .unavailable:
                            Text("The audio is saved, but a transcript isn’t available yet.")
                                .foregroundStyle(.secondary)
                            Button("Try Again") { library.retryTranscription(for: lecture.id) }
                                .buttonStyle(.glass)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: currentIndex) { _, index in
                    guard playback.isPlaying, filter.isEmpty, let index else { return }
                    withAnimation { proxy.scrollTo(index, anchor: .center) }
                }
                .onAppear {
                    if let currentIndex { proxy.scrollTo(currentIndex, anchor: .center) }
                }
            }
        }
    }

    private var currentIndex: Int? {
        lecture.transcriptSegments.firstIndex { playback.position >= $0.start && playback.position < $0.end }
    }
}

private enum TranscriptParagraphs {
    static func make(from transcript: String) -> [String] {
        let blocks = transcript.components(separatedBy: .newlines)
        return blocks.flatMap { block -> [String] in
            let source = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { return [] }

            let nsSource = source as NSString
            var sentences: [String] = []
            nsSource.enumerateSubstrings(in: NSRange(location: 0, length: nsSource.length), options: .bySentences) { sentence, _, _, _ in
                if let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                    sentences.append(sentence)
                }
            }
            guard !sentences.isEmpty else { return [source] }

            var paragraphs: [String] = []
            var current = ""
            for sentence in sentences {
                if !current.isEmpty && current.count + sentence.count > 340 {
                    paragraphs.append(current)
                    current = ""
                }
                current += current.isEmpty ? sentence : " " + sentence
            }
            if !current.isEmpty { paragraphs.append(current) }
            return paragraphs
        }
    }
}
