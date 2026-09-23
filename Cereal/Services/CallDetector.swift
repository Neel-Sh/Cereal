import AppKit
import CoreAudio
import Foundation

/// An app that currently has the microphone open.
struct MicrophoneUser: Hashable {
    let bundleID: String
    let name: String
}

/// Asks Core Audio which processes are capturing input and maps each one to the app the user sees,
/// so a browser or Zoom helper process reports as "Google Chrome" or "zoom.us".
enum CallDetector {
    static func microphoneUsers() -> [MicrophoneUser] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let regularApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var users: [MicrophoneUser] = []
        for process in CoreAudioProperties.objectList(kAudioHardwarePropertyProcessObjectList) {
            guard CoreAudioProperties.value(kAudioProcessPropertyIsRunningInput, of: process, default: UInt32(0)) == 1,
                  let pid = CoreAudioProperties.value(kAudioProcessPropertyPID, of: process, default: pid_t(0)),
                  pid != ownPID,
                  let app = owningApp(pid: pid,
                                      bundleID: CoreAudioProperties.string(kAudioProcessPropertyBundleID, of: process),
                                      among: regularApps),
                  app.processIdentifier != ownPID,
                  let bundleID = app.bundleIdentifier else { continue }
            let user = MicrophoneUser(bundleID: bundleID, name: app.localizedName ?? bundleID)
            if !users.contains(user) { users.append(user) }
        }
        return users
    }

    /// System processes that capture audio on behalf of an app: FaceTime calls run in avconferenced,
    /// and Safari's web calls run in a shared WebKit process.
    private static let daemonOwners = [
        "com.apple.avconferenced": "com.apple.FaceTime",
        "com.apple.WebKit": "com.apple.Safari"
    ]

    private static func owningApp(pid: pid_t, bundleID: String?, among apps: [NSRunningApplication]) -> NSRunningApplication? {
        let process = NSRunningApplication(processIdentifier: pid)
        if let process, process.activationPolicy == .regular { return process }
        if let path = (process?.bundleURL ?? process?.executableURL)?.standardizedFileURL.path,
           let app = apps.first(where: { app in
               guard let appPath = app.bundleURL?.standardizedFileURL.path else { return false }
               return path.hasPrefix(appPath + "/")
           }) {
            return app
        }
        guard let bundleID else { return nil }
        if let appID = daemonOwners.first(where: { bundleID.hasPrefix($0.key) })?.value {
            return apps.first { $0.bundleIdentifier == appID }
        }
        return apps.first { app in
            guard let appID = app.bundleIdentifier else { return false }
            return bundleID.hasPrefix(appID + ".")
        }
    }
}
