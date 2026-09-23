import SwiftUI

@main
struct CerealApp: App {
    @State private var library: LectureLibrary
    @State private var calls: CallCoordinator

    init() {
        let library = LectureLibrary()
        _library = State(initialValue: library)
        _calls = State(initialValue: CallCoordinator(library: library))
    }

    var body: some Scene {
        Window("Cereal", id: "main") {
            ContentView(library: library)
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
        }

        MenuBarExtra {
            MenuBarContent(library: library, calls: calls)
        } label: {
            MenuBarLabel(library: library, calls: calls)
        }

        Settings {
            CerealSettingsView(calls: calls)
        }
    }
}
