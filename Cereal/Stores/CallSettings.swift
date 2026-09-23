import Foundation
import Observation
import ServiceManagement

/// User preferences for call detection, persisted in UserDefaults.
@MainActor @Observable
final class CallSettings {
    private let defaults: UserDefaults

    var detectsCalls: Bool {
        didSet { defaults.set(detectsCalls, forKey: Keys.detectsCalls) }
    }

    var stopsAutomatically: Bool {
        didSet { defaults.set(stopsAutomatically, forKey: Keys.stopsAutomatically) }
    }

    /// Apps that never trigger a prompt, keyed by bundle identifier with a display name.
    private(set) var ignoredApps: [String: String] {
        didSet { defaults.set(ignoredApps, forKey: Keys.ignoredApps) }
    }

    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    var launchAtLoginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        detectsCalls = defaults.object(forKey: Keys.detectsCalls) as? Bool ?? true
        stopsAutomatically = defaults.bool(forKey: Keys.stopsAutomatically)
        ignoredApps = defaults.dictionary(forKey: Keys.ignoredApps) as? [String: String] ?? Self.defaultIgnoredApps
    }

    func isIgnored(_ bundleID: String) -> Bool { ignoredApps[bundleID] != nil }

    func ignore(_ user: MicrophoneUser) { ignoredApps[user.bundleID] = user.name }

    func unignore(_ bundleID: String) { ignoredApps[bundleID] = nil }

    func setLaunchesAtLogin(_ enabled: Bool) throws {
        defer { launchesAtLogin = SMAppService.mainApp.status == .enabled }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func refreshLaunchAtLogin() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Apps that use the microphone for things other than calls.
    private static let defaultIgnoredApps = [
        "com.apple.VoiceMemos": "Voice Memos",
        "com.apple.QuickTimePlayerX": "QuickTime Player",
        "com.apple.PhotoBooth": "Photo Booth",
        "com.apple.garageband10": "GarageBand",
        "com.apple.logic10": "Logic Pro"
    ]

    private enum Keys {
        static let detectsCalls = "detectsCalls"
        static let stopsAutomatically = "stopsRecordingWhenCallEnds"
        static let ignoredApps = "ignoredCallApps"
    }
}
