import SwiftUI

enum SidePanel: String, CaseIterable, Identifiable {
    case transcript, ask
    var id: Self { self }
    var title: String {
        switch self {
        case .transcript: "Transcript"
        case .ask: "Ask"
        }
    }
}

struct ContentView: View {
    @Bindable var library: LectureLibrary
    @ObservedObject var updates: UpdateManager
    @State private var showingLibrary = false
    @State private var sidePanel: SidePanel?
    @State private var showingChat = false

    private var showingDetail: Bool {
        !showingLibrary && !(library.isRecording || library.showRecorder) && library.selectedLecture != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if showingLibrary {
                    LectureListView(library: library) { id in
                        library.selectedID = id
                        library.showRecorder = false
                        showingLibrary = false
                        sidePanel = nil
                    }
                } else if library.isRecording || library.showRecorder {
                    RecorderView(library: library)
                } else if let lecture = library.selectedLecture {
                    LectureDetailView(library: library, lecture: lecture, sidePanel: $sidePanel)
                        .id(lecture.id)
                } else {
                    RecorderView(library: library)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        sidePanel = nil
                        showingLibrary.toggle()
                    } label: {
                        Label(showingLibrary ? "Back to Note" : "All Notes", systemImage: showingLibrary ? "chevron.left" : "house")
                    }
                    .help(showingLibrary ? "Back to note" : "All notes")
                    .disabled(library.isRecording || library.canRetrySaving || (showingLibrary && library.selectedLecture == nil && !library.showRecorder))
                }
                ToolbarItem(placement: .navigation) {
                    Button {
                        library.showRecorder = true
                        showingLibrary = false
                    } label: {
                        Label("New Note", systemImage: "plus")
                    }
                    .help("New note (⌘N)")
                    .disabled(library.isRecording || library.isStarting || library.canRetrySaving || library.isRecovering || (library.showRecorder && !showingLibrary))
                }
                if !showingDetail {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingChat = true
                        } label: {
                            Label("Ask", systemImage: "sparkle.magnifyingglass")
                        }
                        .help("Ask across all your notes")
                        .disabled(library.isRecording || library.lectures.isEmpty)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let version = updates.availableVersion,
               !library.isRecording && !library.isStarting && !library.isStopping &&
               !library.isRecovering && !library.canRetrySaving {
                HStack {
                    Button {
                        updates.installAvailableUpdate()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.tint)
                            Text("Update available")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel("Update available. Install Cereal \(version)")
                    .help("Install Cereal \(version)")
                    Spacer(minLength: 0)
                }
                .padding(.leading, 20)
                .padding(.trailing, 20)
                .padding(.top, 6)
                .padding(.bottom, 14)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #if DEBUG
        .onAppear {
            let scene = DebugSnapshot.scene
            if scene.contains("library") { showingLibrary = true }
            if scene.contains("recorder") || scene.contains("rec-") { library.showRecorder = true }
            if scene.contains("transcript") { sidePanel = .transcript }
            if scene.contains("ask") { sidePanel = .ask }
            if scene.contains("chat") { showingChat = true }
        }
        #endif
        .sheet(isPresented: $showingChat) {
            GlobalChatSheet(library: library) { source in
                library.jump(to: source.lectureID, time: source.start)
                showingLibrary = false
                sidePanel = .transcript
            }
        }
        .onChange(of: library.showRecorder) { _, showing in
            if showing {
                showingLibrary = false
                sidePanel = nil
            }
        }
        .alert("Cereal", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("OK") { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }
}
