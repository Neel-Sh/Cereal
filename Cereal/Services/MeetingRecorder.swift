import AVFoundation
import Foundation

/// Records your microphone and the computer's audio as separate tracks so transcripts can tell "Me" from "Them".
/// After stopping, the tracks are mixed into one file for playback.
@MainActor
final class MeetingRecorder {
    private let microphone = MicrophoneRecorder()
    private let system = SystemAudioRecorder()

    var levels: [Float] {
        let mic = microphone.levels
        let computer = system.levels
        let count = max(mic.count, computer.count)
        return (0..<count).map { index in
            let micIndex = index - (count - mic.count)
            let computerIndex = index - (count - computer.count)
            return max(micIndex >= 0 ? mic[micIndex] : 0,
                       computerIndex >= 0 ? computer[computerIndex] : 0)
        }
    }

    func start(microphoneURL: URL, systemURL: URL, microphoneFeed: LiveAudioFeed?, systemFeed: LiveAudioFeed?) async throws {
        try await microphone.start(at: microphoneURL, feed: microphoneFeed)
        do {
            try system.start(at: systemURL, feed: systemFeed)
        } catch {
            _ = microphone.stop()
            throw error
        }
    }

    func pause() {
        system.isPaused = true
        microphone.pause()
    }

    func resume() throws {
        try microphone.resume()
        system.isPaused = false
    }

    /// Stops both tracks. Safe to call more than once.
    func stop() {
        if microphone.isActive { _ = microphone.stop() }
        if system.isActive { _ = system.stop() }
    }

    /// Mixes whichever tracks exist into a single M4A and returns its duration.
    static func mix(microphoneURL: URL, systemURL: URL, to finalURL: URL) async throws -> TimeInterval {
        let composition = AVMutableComposition()
        for url in [microphoneURL, systemURL] where FileManager.default.fileExists(atPath: url.path) {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let range = try await source.load(.timeRange)
            let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try track?.insertTimeRange(range, of: source, at: .zero)
        }
        guard !composition.tracks.isEmpty,
              let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw MeetingRecorderError.couldNotMix
        }
        try? FileManager.default.removeItem(at: finalURL)
        try await exporter.export(to: finalURL, as: .m4a)
        return try await AVURLAsset(url: finalURL).load(.duration).seconds
    }
}

private enum MeetingRecorderError: LocalizedError {
    case couldNotMix

    var errorDescription: String? {
        "The call audio was captured, but its tracks could not be combined into one recording."
    }
}
