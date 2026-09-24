import SwiftUI

@main
struct CerealApp: App {
    @State private var library: LectureLibrary
    @State private var calls: CallCoordinator
    @StateObject private var updates = UpdateManager()

    init() {
        let library = LectureLibrary()
        _library = State(initialValue: library)
        _calls = State(initialValue: CallCoordinator(library: library))
    }

    var body: some Scene {
        Window("Cereal", id: "main") {
            ContentView(library: library, updates: updates)
                .frame(minWidth: 800, minHeight: 560)
                #if DEBUG
                .onAppear {
                    DebugSnapshot.scheduleIfNeeded()
                    DebugSnapshot.showCallPromptIfNeeded(calls)
                }
                #endif
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    library.showRecorder = true
                }
                .keyboardShortcut("n")
                .disabled(library.isRecording || library.isStarting || library.canRetrySaving || library.isRecovering)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(library.isRecording || library.isStarting || library.isStopping)
            }
        }

        MenuBarExtra {
            MenuBarContent(library: library, calls: calls, updates: updates)
        } label: {
            MenuBarLabel(library: library, calls: calls, updates: updates)
        }

        Settings {
            CerealSettingsView(calls: calls, updates: updates)
        }
    }
}
