#if DEBUG
import AppKit
import AVFoundation
import SwiftUI

/// Development-only launch hooks for capturing UI states without clicking through the app.
/// CEREAL_STORAGE_ROOT points storage at a scratch folder, CEREAL_SCENE picks the starting screen,
/// and CEREAL_SNAPSHOT writes a PNG of the main window a few seconds after launch, then quits.
enum DebugSnapshot {
    static let environment = ProcessInfo.processInfo.environment
    static var storageRoot: URL? { environment["CEREAL_STORAGE_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) } }
    static var scene: String { environment["CEREAL_SCENE"] ?? "" }

    static func scheduleIfNeeded() {
        guard let path = environment["CEREAL_SNAPSHOT"] else { return }
        let delay = environment["CEREAL_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 3.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let wantsPanel = scene.contains("callprompt") || scene.contains("callend")
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && $0.contentView != nil && (wantsPanel ? $0 is NSPanel : $0.canBecomeMain)
            }) else { exit(1) }
            capture(window, to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    /// Shows the call prompt with a sample app so it can be captured without a real call.
    static func showCallPromptIfNeeded(_ calls: CallCoordinator) {
        let app = MicrophoneUser(bundleID: "com.apple.FaceTime", name: "FaceTime")
        if scene.contains("callprompt") {
            calls.showStartPrompt(for: app, eventTitle: scene.contains("event") ? "Weekly design sync" : nil)
        } else if scene.contains("callend") {
            calls.showEndPrompt(for: app)
        }
        if scene.contains("settings") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }    }

    /// Streams CEREAL_LIVE_FILE through the live transcription pipeline at roughly real-time pace.
    static func feedLiveFile(into transcriber: LiveTranscriber) async {
        guard let path = environment["CEREAL_LIVE_FILE"],
              let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return }
        let feed = LiveAudioFeed()
        await transcriber.start(feed: feed)
        let format = file.processingFormat
        await Task.detached {
            while let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096),
                  (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 {
                feed.append(buffer)
                try? await Task.sleep(for: .seconds(Double(buffer.frameLength) / format.sampleRate))
            }
        }.value
    }

    private static func capture(_ window: NSWindow, to url: URL) {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGWindowListCreateImage") {
            let create = unsafeBitCast(symbol, to: CreateImage.self)
            // Include only this window, at best resolution, without its shadow.
            if let image = create(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue(),
               image.width > 1,
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                return
            }
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
