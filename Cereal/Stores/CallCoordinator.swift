import AppKit
import Foundation
import Observation

/// Watches for apps opening the microphone and offers to record the call, then offers to stop when it ends.
@MainActor @Observable
final class CallCoordinator {
    let settings: CallSettings
    private(set) var currentCall: MicrophoneUser?
    /// Opens the main window; provided by a SwiftUI view that has the `openWindow` action.
    var openMainWindow: (() -> Void)?

    private let library: LectureLibrary
    private let panel = CallPromptPanel()
    private var pollTask: Task<Void, Never>?
    private var callStartedAt: Date?
    private var callLastSeen: Date?
    private var hasPrompted = false
    private var recordingCall: MicrophoneUser?

    /// How long an app must hold the microphone before it counts as a call.
    private let confirmDelay: TimeInterval = 3
    /// How long the microphone must stay released before the call counts as over.
    private let endGrace: TimeInterval = 10

    init(library: LectureLibrary, settings: CallSettings? = nil) {
        self.library = library
        self.settings = settings ?? CallSettings()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                self?.poll()
            }
        }
    }

    private func poll() {
        guard settings.detectsCalls else {
            if currentCall != nil { endCall(notify: false) }
            return
        }
        let now = Date()
        let users = CallDetector.microphoneUsers().filter { !settings.isIgnored($0.bundleID) }

        if let call = currentCall {
            if users.contains(call) {
                callLastSeen = now
            } else if now.timeIntervalSince(callLastSeen ?? now) >= endGrace {
                endCall(notify: true)
            }
        }
        if currentCall == nil, let user = users.first {
            currentCall = user
            callStartedAt = now
            callLastSeen = now
            hasPrompted = false
        }
        if let call = currentCall, recordingCall == nil, library.isRecording, library.activeCaptureMode == .online {
            recordingCall = call
        }
        guard let call = currentCall, !hasPrompted,
              now.timeIntervalSince(callStartedAt ?? now) >= confirmDelay else { return }
        hasPrompted = true
        if library.isRecording {
            if library.activeCaptureMode == .online { recordingCall = call }
            return
        }
        guard !library.isBusy else { return }
        library.calendar.refresh()
        showStartPrompt(for: call, eventTitle: library.calendar.currentEvent?.title)
    }

    private func endCall(notify: Bool) {
        let ended = currentCall
        currentCall = nil
        callStartedAt = nil
        callLastSeen = nil
        if panel.kind == .start { panel.dismiss() }
        guard notify, let ended, recordingCall == ended else { return }
        recordingCall = nil
        guard library.isRecording, !library.isStopping else { return }
        if settings.stopsAutomatically {
            library.stopRecording()
        } else {
            showEndPrompt(for: ended)
        }
    }

    func showStartPrompt(for call: MicrophoneUser, eventTitle: String?) {
        panel.show(CallPromptView(
            kind: .start,
            app: call,
            eventTitle: eventTitle,
            primary: { [weak self] in self?.recordCall(call) },
            secondary: { [weak self] in self?.panel.dismiss() },
            ignore: { [weak self] in
                self?.settings.ignore(call)
                self?.panel.dismiss()
            }
        ), kind: .start, dismissAfter: 30)
    }

    func showEndPrompt(for call: MicrophoneUser) {
        panel.show(CallPromptView(
            kind: .end,
            app: call,
            eventTitle: nil,
            primary: { [weak self] in
                self?.panel.dismiss()
                self?.library.stopRecording()
            },
            secondary: { [weak self] in self?.panel.dismiss() },
            ignore: nil
        ), kind: .end, dismissAfter: 120)
    }

    private func recordCall(_ call: MicrophoneUser) {
        panel.dismiss()
        recordingCall = call
        showMainWindow()
        Task { await library.startCallRecording(appName: call.name) }
    }

    func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        NSApp.activate()
    }
}
