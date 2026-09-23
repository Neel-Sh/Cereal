import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class AudioPlayback {
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?

    func load(_ url: URL) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            errorMessage = nil
        } catch {
            errorMessage = "Could not open this recording: \(error.localizedDescription)"
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
            timer = nil
        } else {
            if position >= duration { seek(to: 0) }
            isPlaying = player.play()
            guard isPlaying else { return }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), duration)
        position = player.currentTime
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        isPlaying = false
        position = 0
        duration = 0
    }

    func dismissError() { errorMessage = nil }

    private func refresh() {
        guard let player else { return }
        position = player.currentTime
        if !player.isPlaying {
            isPlaying = false
            timer?.invalidate()
            timer = nil
        }
    }
}
