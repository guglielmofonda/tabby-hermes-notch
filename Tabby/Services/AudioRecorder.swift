import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import Combine
import OSLog

/// Captures mic input and accumulates 16 kHz mono Float32 PCM, publishing RMS level for a waveform.
final class AudioRecorder: ObservableObject, @unchecked Sendable {
    static let targetSampleRate: Double = 16_000

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var level: Float = 0            // 0...1 RMS level, main-thread published
    @Published private(set) var durationSeconds: Double = 0
    static let levelHistoryBars = 28
    /// Rolling history of RMS levels (most recent last). Fixed length = `levelHistoryBars`.
    @Published private(set) var levelHistory: [Float] = Array(repeating: 0, count: 28)

    /// Read after `stop()` returns on the main thread.
    private var samples: [Float] = []

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var startTime: Date?
    private let logger = Logger(subsystem: "com.guglielmofonda.Tabby", category: "Audio")

    enum AudioError: Error {
        case microphonePermissionDenied
        case engineStartFailed(String)
    }

    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    @MainActor
    func start() async throws {
        guard !isRecording else { return }
        guard await requestMicrophonePermission() else {
            throw AudioError.microphonePermissionDenied
        }

        samples.removeAll(keepingCapacity: true)
        level = 0
        durationSeconds = 0
        levelHistory = Array(repeating: 0, count: Self.levelHistoryBars)
        startTime = Date()

        let input = engine.inputNode

        // Choose the input device: user-selected → built-in MacBook → system default.
        let resolvedDeviceID = resolveInputDeviceID()
        if let deviceID = resolvedDeviceID {
            assignInputDevice(to: input, deviceID: deviceID)
            let name = AudioDeviceRegistry.name(for: deviceID) ?? "device \(deviceID)"
            logger.info("Using input device: \(name, privacy: .public) (id=\(deviceID))")
        } else {
            logger.warning("No input device resolved — relying on engine default")
        }

        let hwFormat = input.inputFormat(forBus: 0)
        logger.info("Input HW format: \(hwFormat.sampleRate, format: .fixed(precision: 0))Hz, channels=\(hwFormat.channelCount)")

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.engineStartFailed("Could not create target AVAudioFormat")
        }
        outputFormat = target
        converter = AVAudioConverter(from: hwFormat, to: target)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer: buffer)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioError.engineStartFailed(error.localizedDescription)
        }

        isRecording = true
        logger.info("Recording started. hwSR=\(hwFormat.sampleRate) → \(Self.targetSampleRate)")
    }

    @MainActor
    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return samples }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        outputFormat = nil
        isRecording = false
        level = 0
        let out = samples
        samples.removeAll(keepingCapacity: true)
        logger.info("Recording stopped. samples=\(out.count), tapFires=\(self.tapFireCount), seconds=\(self.durationSeconds, format: .fixed(precision: 2))")
        tapFireCount = 0
        return out
    }

    private var tapFireCount: Int = 0

    // MARK: - Input device wiring

    private func resolveInputDeviceID() -> AudioDeviceID? {
        if let stored = SettingsStore.selectedInputDeviceID,
           AudioDeviceRegistry.listInputDevices().contains(where: { $0.id == stored }) {
            return stored
        }
        if let builtIn = AudioDeviceRegistry.builtInInput()?.id {
            return builtIn
        }
        return AudioDeviceRegistry.systemDefaultInputID()
    }

    private func assignInputDevice(to input: AVAudioInputNode, deviceID: AudioDeviceID) {
        guard let au = input.audioUnit else { return }
        var id = deviceID
        let status = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            logger.error("AudioUnitSetProperty(CurrentDevice) failed: status=\(status)")
        }
    }

    // MARK: - Tap handler (audio I/O thread)

    private func handleTap(buffer: AVAudioPCMBuffer) {
        guard let converter, let outFormat = outputFormat else {
            logger.debug("handleTap bailing: converter or outFormat nil")
            return
        }
        tapFireCount += 1
        if tapFireCount == 1 {
            logger.info("First tap fired. inBuf frames=\(buffer.frameLength), inSR=\(buffer.format.sampleRate), inCh=\(buffer.format.channelCount), outSR=\(outFormat.sampleRate)")
        }

        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else { return }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                // Use .noDataNow so the converter stays live for the next tap; .endOfStream would
                // drain the converter permanently and subsequent taps would produce 0 frames.
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error {
            logger.error("AVAudioConverter error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return
        }
        guard let ch = outBuffer.floatChannelData?.pointee else {
            logger.error("outBuffer has no floatChannelData")
            return
        }
        let frames = Int(outBuffer.frameLength)
        if frames == 0 && tapFireCount <= 3 {
            logger.warning("Converter produced 0 frames for inBuf frames=\(buffer.frameLength)")
        }
        // Log peak amplitude at first few taps so we can tell if the device is producing silence.
        if tapFireCount <= 3 && frames > 0 {
            var peak: Float = 0
            for i in 0..<frames { peak = max(peak, abs(ch[i])) }
            logger.info("Tap #\(self.tapFireCount): frames=\(frames), peakAmp=\(peak)")
        }
        var rmsSum: Float = 0
        samples.reserveCapacity(samples.count + frames)
        for i in 0..<frames {
            let s = ch[i]
            samples.append(s)
            rmsSum += s * s
        }
        let rms = frames > 0 ? sqrtf(rmsSum / Float(frames)) : 0
        // Boost + compress so quiet speech still registers while loud speech caps at 1.
        let levelTarget = min(1, powf(rms * 8, 0.75))
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let smoothed = max(levelTarget, self.level * 0.72)
            self.level = smoothed
            self.durationSeconds = duration
            // Rolling history: shift left, append latest.
            var h = self.levelHistory
            if !h.isEmpty {
                h.removeFirst()
                h.append(smoothed)
                self.levelHistory = h
            }
        }
    }
}
