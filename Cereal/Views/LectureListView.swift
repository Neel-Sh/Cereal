import SwiftUI

struct LectureListView: View {
    @Bindable var library: LectureLibrary
    let select: (UUID) -> Void
    @State private var searchText = ""
    @State private var pendingDeletion: UUID?
    @State private var selectedCourse: String?

    private var courses: [String] {
        Array(Set(library.lectures.map(\.course).filter { !$0.isEmpty })).sorted()
    }

    private var matchingLectures: [Lecture] {
        library.lectures.filter {
            (selectedCourse == nil || $0.course == selectedCourse) &&
            (searchText.isEmpty ||
             $0.title.localizedCaseInsensitiveContains(searchText) ||
             $0.notes.localizedCaseInsensitiveContains(searchText) ||
             $0.summary.localizedCaseInsensitiveContains(searchText) ||
             $0.enhancedNotes.localizedCaseInsensitiveContains(searchText) ||
             $0.course.localizedCaseInsensitiveContains(searchText) ||
             $0.topic.localizedCaseInsensitiveContains(searchText) ||
             $0.transcript.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var groups: [(title: String, lectures: [Lecture])] {
        let calendar = Calendar.current
        let now = Date()
        var pinned: [Lecture] = []
        var buckets: [(title: String, lectures: [Lecture])] = []
        func append(_ lecture: Lecture, to title: String) {
            if let index = buckets.firstIndex(where: { $0.title == title }) {
                buckets[index].lectures.append(lecture)
            } else {
                buckets.append((title, [lecture]))
            }
        }
        for lecture in matchingLectures.sorted(by: { $0.recordedAt > $1.recordedAt }) {
            if lecture.isPinned {
                pinned.append(lecture)
            } else if calendar.isDateInToday(lecture.recordedAt) {
                append(lecture, to: "Today")
            } else if calendar.isDateInYesterday(lecture.recordedAt) {
                append(lecture, to: "Yesterday")
            } else if let days = calendar.dateComponents([.day], from: lecture.recordedAt, to: now).day, days < 7 {
                append(lecture, to: "Previous 7 days")
            } else {
                append(lecture, to: lecture.recordedAt.formatted(.dateTime.month(.wide).year()))
            }
        }
        return (pinned.isEmpty ? [] : [("Pinned", pinned)]) + buckets
    }

    var body: some View {
        PageColumn(maxWidth: 680) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    PageTitle(text: "All notes")
                    Text("\(library.lectures.count) \(library.lectures.count == 1 ? "note" : "notes") · saved on this Mac")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search notes and transcripts", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .accessibilityLabel("Search notes")
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 40)
                .glassEffect(.regular.interactive(), in: .capsule)

                if !courses.isEmpty {
                    GlassEffectContainer(spacing: 6) {
                        FlowLayout(spacing: 6) {
                            CourseFilterChip(title: "All", symbol: "tray.full", isSelected: selectedCourse == nil) {
                                selectedCourse = nil
                            }
                            ForEach(courses, id: \.self) { course in
                                CourseFilterChip(title: course, symbol: "folder", isSelected: selectedCourse == course) {
                                    selectedCourse = selectedCourse == course ? nil : course
                                }
                            }
                        }
                    }
                }

                if matchingLectures.isEmpty {
                    ContentUnavailableView(
                        library.lectures.isEmpty ? "No notes yet" : "No matches",
                        systemImage: library.lectures.isEmpty ? "waveform" : "magnifyingglass",
                        description: Text(library.lectures.isEmpty ? "Start a recording with ⌘N." : "Try a different search or course.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(groups, id: \.title) { group in
                                VStack(alignment: .leading, spacing: 2) {
                                    SectionHeading(text: group.title)
                                        .padding(.horizontal, 12)
                                        .padding(.bottom, 4)
                                    ForEach(group.lectures) { lecture in
                                        LectureRow(lecture: lecture) { select(lecture.id) }
                                            .contextMenu {
                                                Button(lecture.isPinned ? "Unpin" : "Pin to Top",
                                                       systemImage: lecture.isPinned ? "pin.slash" : "pin") {
                                                    library.togglePin(lecture.id)
                                                }
                                                Button("Copy Notes", systemImage: "doc.on.doc") {
                                                    LectureExport.copyToPasteboard(LectureExport.notesText(lecture))
                                                }
                                                Divider()
                                                Button("Delete Note…", systemImage: "trash", role: .destructive) {
                                                    pendingDeletion = lecture.id
                                                }
                                            }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.never)
                    .bottomFade(32)
                }
            }
        }
        .confirmationDialog("Delete this note and its recording?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Delete Note", role: .destructive) {
                if let id = pendingDeletion { library.delete(id) }
                pendingDeletion = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
}

private struct CourseFilterChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(ChipLabelStyle())
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular.interactive(), in: .capsule)
    }
}

private struct LectureRow: View {
    let lecture: Lecture
    let open: () -> Void
    @State private var isHovering = false

    private var subtitle: String {
        [lecture.course, lecture.topic].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: lecture.template.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .glassEffect(in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(lecture.displayTitle)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        if lecture.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(subtitle.isEmpty ? (lecture.summary.isEmpty ? lecture.template.title : lecture.summary) : subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if lecture.transcriptionState == .processing {
                    ProgressView().controlSize(.mini)
                }
                if lecture.actionItems.contains(where: { !$0.isDone }) {
                    Label("\(lecture.actionItems.filter { !$0.isDone }.count)", systemImage: "checklist")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("Open to-dos")
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Calendar.current.isDateInToday(lecture.recordedAt)
                         ? lecture.recordedAt.formatted(date: .omitted, time: .shortened)
                         : lecture.recordedAt.formatted(.dateTime.month(.abbreviated).day()))
                    Text(lecture.duration.formattedDuration)
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
