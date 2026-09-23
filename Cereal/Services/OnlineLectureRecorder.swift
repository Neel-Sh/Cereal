import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class OnlineLectureRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, SCStreamOutput {
    nonisolated private let liveFeedBox = LiveFeedBox()
    private let sampleQueue = DispatchQueue(label: "Cereal.OnlineLiveAudio")
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var temporaryURL: URL?
    private var finalURL: URL?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private var captureStopped = false
    private var finishError: Error?

    func start(at url: URL, temporaryURL: URL, feed: LiveAudioFeed?) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw OnlineRecorderError.microphoneDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw OnlineRecorderError.noDisplay
        }

        try LectureStorage().prepareAudioDirectory()
        try? FileManager.default.removeItem(at: temporaryURL)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 320
        configuration.height = 180
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = temporaryURL
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.mixesAudioWithMicrophone = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        try stream.addRecordingOutput(output)
        if let feed {
            liveFeedBox.feed = feed
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }
        self.stream = stream
        recordingOutput = output
        self.temporaryURL = temporaryURL
        finalURL = url
        finished = false
        captureStopped = false
        finishError = nil
        do {
            try await stream.startCapture()
        } catch {
            self.stream = nil
            recordingOutput = nil
            throw error
        }
    }

    func stop() async throws -> TimeInterval {
        guard let stream, let temporaryURL, let finalURL else {
            throw OnlineRecorderError.notRecording
        }
        liveFeedBox.feed = nil
        if !captureStopped {
            try await stream.stopCapture()
            captureStopped = true
        }
        if !finished {
            try await withCheckedThrowingContinuation { continuation in
                finishContinuation = continuation
            }
        } else if let finishError {
            throw finishError
        }

        try await Self.extractAudio(from: temporaryURL, to: finalURL)
        let asset = AVURLAsset(url: finalURL)
        let duration = try await asset.load(.duration).seconds
        try? FileManager.default.removeItem(at: temporaryURL)
        self.stream = nil
        recordingOutput = nil
        self.temporaryURL = nil
        self.finalURL = nil
        return duration
    }

    static func extractAudio(from temporaryURL: URL, to finalURL: URL) async throws {
        let asset = AVURLAsset(url: temporaryURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw OnlineRecorderError.couldNotExport
        }
        try? FileManager.default.removeItem(at: finalURL)
        try await exporter.export(to: finalURL, as: .m4a)
        try? FileManager.default.removeItem(at: temporaryURL)
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let feed = liveFeedBox.feed,
              let description = sampleBuffer.formatDescription,
              let format = AVAudioFormat(formatDescription: description) else { return }
        try? sampleBuffer.withAudioBufferList { list, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer) else { return }
            feed.append(buffer)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            finished = true
            finishContinuation?.resume()
            finishContinuation = nil
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in
            finishError = error
            finished = true
            finishContinuation?.resume(throwing: error)
            finishContinuation = nil
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            finishError = error
            finished = true
            finishContinuation?.resume(throwing: error)
            finishContinuation = nil
        }
    }
}

nonisolated private final class LiveFeedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFeed: LiveAudioFeed?

    var feed: LiveAudioFeed? {
        get { lock.lock(); defer { lock.unlock() }; return storedFeed }
        set { lock.lock(); storedFeed = newValue; lock.unlock() }
    }
}

private enum OnlineRecorderError: LocalizedError {
    case microphoneDenied, noDisplay, notRecording, couldNotExport

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Allow microphone access in System Settings to capture your voice."
        case .noDisplay: "No display was available for computer audio capture."
        case .notRecording: "The online lecture recording was not active."
        case .couldNotExport: "Computer audio was captured, but the audio file could not be finalized."
        }
    }
}
