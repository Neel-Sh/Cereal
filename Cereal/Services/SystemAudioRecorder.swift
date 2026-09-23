import AVFoundation
import CoreAudio
import Foundation

/// Records what the Mac is playing (everything except Cereal) through a Core Audio process tap.
/// Audio-only: no screen recording permission and no temporary video.
@MainActor
final class SystemAudioRecorder {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var sink: AudioTrackSink?
    private let queue = DispatchQueue(label: "Cereal.SystemAudioTap", qos: .userInitiated)

    var levels: [Float] { sink?.levels ?? [] }
    var isActive: Bool { procID != nil }

    var isPaused: Bool {
        get { sink?.isPaused ?? false }
        set { sink?.isPaused = newValue }
    }

    func start(at url: URL, feed: LiveAudioFeed?) throws {
        try LectureStorage().prepareAudioDirectory()
        do {
            try createTap()
            try createAggregateDevice()
            guard let format = tapFormat() else { throw SystemAudioError.couldNotStart }
            let sink = try AudioTrackSink(url: url, inputFormat: format, feed: feed)
            var procID: AudioDeviceIOProcID?
            var status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, Self.ioBlock(format: format, sink: sink))
            guard status == noErr, let procID else { throw SystemAudioError.couldNotStart }
            self.procID = procID
            self.sink = sink
            status = AudioDeviceStart(aggregateID, procID)
            guard status == noErr else { throw SystemAudioError.couldNotStart }
        } catch {
            _ = stop()
            throw error
        }
    }

    nonisolated private static func ioBlock(format: AVAudioFormat, sink: AudioTrackSink) -> AudioDeviceIOBlock {
        { _, inputData, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else { return }
            sink.process(buffer)
        }
    }

    func stop() -> TimeInterval {
        let duration = sink?.duration ?? 0
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        sink = nil
        return duration
    }

    private func createTap() throws {
        let excluded = CoreAudioProperties.processObject(for: ProcessInfo.processInfo.processIdentifier).map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "Cereal computer audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != kAudioObjectUnknown else {
            throw SystemAudioError.couldNotStart
        }
        self.tapID = tapID
    }

    private func createAggregateDevice() throws {
        guard let tapUID = CoreAudioProperties.string(kAudioTapPropertyUID, of: tapID) else {
            throw SystemAudioError.couldNotStart
        }
        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Cereal Capture",
            kAudioAggregateDeviceUIDKey: "com.neelsharma.Cereal.capture.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUID
            ]]
        ]
        if let outputID = CoreAudioProperties.value(kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                    of: AudioObjectID(kAudioObjectSystemObject),
                                                    default: AudioObjectID(kAudioObjectUnknown)),
           let outputUID = CoreAudioProperties.string(kAudioDevicePropertyDeviceUID, of: outputID) {
            description[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            description[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
        }
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID) == noErr,
              aggregateID != kAudioObjectUnknown else {
            throw SystemAudioError.couldNotStart
        }
        self.aggregateID = aggregateID
    }

    /// The tap's channel layout at the aggregate device's clock rate, which is what the IO callback delivers.
    private func tapFormat() -> AVAudioFormat? {
        guard var description = CoreAudioProperties.value(kAudioTapPropertyFormat, of: tapID,
                                                          default: AudioStreamBasicDescription()),
              description.mSampleRate > 0 else { return nil }
        if let deviceRate = CoreAudioProperties.value(kAudioDevicePropertyNominalSampleRate, of: aggregateID, default: Float64(0)),
           deviceRate > 0 {
            description.mSampleRate = deviceRate
        }
        return AVAudioFormat(streamDescription: &description)
    }
}

private enum SystemAudioError: LocalizedError {
    case couldNotStart

    var errorDescription: String? {
        "Computer audio could not be captured. Allow Cereal under System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only."
    }
}
