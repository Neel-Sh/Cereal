import SwiftUI

struct MenuBarContent: View {
    let library: LectureLibrary
    let calls: CallCoordinator
    @ObservedObject var updates: UpdateManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if library.isRecording {
            Text(library.isPaused ? "Paused · \(library.elapsed.formattedDuration)" : "Recording · \(library.elapsed.formattedDuration)")
            if library.canPause {
                Button(library.isPaused ? "Resume" : "Pause") { library.togglePause() }
            }
            Button("Stop & Save") { library.stopRecording() }
                .disabled(library.isStopping)
        } else {
            Button("Record Microphone", systemImage: "mic") { record(.microphone) }
                .disabled(library.isBusy)
            Button("Record Computer Audio", systemImage: "desktopcomputer") { record(.online) }
                .disabled(library.isBusy)
        }
        if let call = calls.currentCall {
            Text("\(call.name) is using the microphone")
        }
        Divider()
        Button("Open Cereal") { showWindow() }
        if let version = updates.availableVersion {
            Button("Update Cereal to \(version)", systemImage: "arrow.down.circle") {
                updates.installAvailableUpdate()
            }
            .disabled(library.isRecording || library.isStarting || library.isStopping)
        } else {
            Button("Check for Updates…") { updates.checkForUpdates() }
                .disabled(library.isRecording || library.isStarting || library.isStopping)
        }
        @Bindable var settings = calls.settings
        Toggle("Detect Calls", isOn: $settings.detectsCalls)
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Cereal") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func record(_ mode: CaptureMode) {
        showWindow()
        library.captureMode = mode
        library.showRecorder = true
        Task { await library.startRecording() }
    }

    private func showWindow() {
        calls.openMainWindow = { openWindow(id: "main") }
        calls.showMainWindow()
    }
}

struct MenuBarLabel: View {
    let library: LectureLibrary
    let calls: CallCoordinator
    @ObservedObject var updates: UpdateManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if library.isRecording {
                HStack(spacing: 4) {
                    Image(systemName: library.isPaused ? "pause.circle.fill" : "record.circle.fill")
                    Text(library.elapsed.formattedDuration)
                        .monospacedDigit()
                }
            } else {
                Image(systemName: updates.availableVersion == nil ? "waveform" : "arrow.down.circle")
            }
        }
        .task { calls.openMainWindow = { openWindow(id: "main") } }
    }
}

struct CerealSettingsView: View {
    let calls: CallCoordinator
    let updates: UpdateManager
    @State private var launchError: String?

    private var settings: CallSettings { calls.settings }

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.automaticallyChecksForUpdates = $0 }
                ))
                Button("Check for Updates…") { updates.checkForUpdates() }
            }

            Section {
                Toggle("Open Cereal at login", isOn: Binding(
                    get: { settings.launchesAtLogin },
                    set: { enabled in
                        do {
                            try settings.setLaunchesAtLogin(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                    }))
                if settings.launchAtLoginNeedsApproval {
                    Text("Allow Cereal in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Cereal keeps running in the menu bar after you close its window, so it can notice calls.")
            }

            Section("Calls") {
                @Bindable var settings = settings
                Toggle("Offer to record when a call starts", isOn: $settings.detectsCalls)
                Toggle("Stop and save automatically when the call ends", isOn: $settings.stopsAutomatically)
                    .disabled(!settings.detectsCalls)
            }

            Section {
                if settings.ignoredApps.isEmpty {
                    Text("No ignored apps")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.ignoredApps.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }, id: \.key) { bundleID, name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { settings.unignore(bundleID) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Ask again when \(name) uses the microphone")
                    }
                }
            } header: {
                Text("Never ask for")
            } footer: {
                Text("Choose “Don’t ask for…” on a call prompt to add an app here.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { settings.refreshLaunchAtLogin() }
    }
}
