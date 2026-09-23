import SwiftUI

@main
struct CerealApp: App {
    @State private var library = LectureLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView(library: library)
                .frame(minWidth: 800, minHeight: 560)
                #if DEBUG
                .onAppear { DebugSnapshot.scheduleIfNeeded() }
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
    }
}
