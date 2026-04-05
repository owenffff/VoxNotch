//
//  AudioCaptureManager.swift
//  VoxNotch
//
//  Audio capture from microphone using AVAudioEngine
//

import Foundation
import AVFoundation
import CoreAudio
import Accelerate

/// Manages audio capture from the system microphone
final class AudioCaptureManager {

    // MARK: - Types

    enum AudioCaptureError: LocalizedError {
        case noInputAvailable
        case engineStartFailed(Error)
        case permissionDenied
        case noAudioRecorded
        case fileWriteFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noInputAvailable:
                return "No microphone found"
            case .engineStartFailed:
                return "Microphone failed to start"
            case .permissionDenied:
                return "Microphone access denied"
            case .noAudioRecorded:
                return "No audio was recorded"
            case .fileWriteFailed:
                return "Could not save recording"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .noInputAvailable:
                return "Connect a microphone and try again"
            case .engineStartFailed:
                return "Try again — restart the app if it persists"
            case .permissionDenied:
                return "Grant access in System Settings → Privacy"
            case .noAudioRecorded:
                return "Try speaking louder or longer"
            case .fileWriteFailed:
                return "Try again — check disk space if it persists"
            }
        }
    }

    /// Audio capture result
    struct CaptureResult {
        let fileURL: URL
        let duration: TimeInterval
        let sampleRate: Double
    }

    // MARK: - Properties

    static let shared = AudioCaptureManager()

    /// The audio engine for capture
    private let audioEngine = AVAudioEngine()

    /// Lock protecting state shared between the audio-tap thread and the main thread.
    private let audioLock = NSLock()

    /// Buffer to accumulate recorded audio
    private var recordedBuffers: [AVAudioPCMBuffer] = []

    /// Whether we're currently recording
    private(set) var isRecording: Bool = false

    /// Recording start time
    private var recordingStartTime: Date?

    /// Sample rate for recording (16kHz is minimum for good transcription)
    private let targetSampleRate: Double = 16000

    /// Whether to accumulate buffers for file saving
    var accumulateBuffers: Bool = true

    /// Resampling converter for producing 16kHz mono from native input
    private var resamplingConverter: AVAudioConverter?

    /// Output format for resampled audio (16kHz mono Float32)
    private let resampledFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// Whether microphone permission has been granted
    var hasMicrophonePermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Device Selection

    /// User-selected audio device ID. `nil` means system default.
    private(set) var selectedDeviceID: AudioDeviceID?

    /// Listener block reference for device change notifications
    private var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?

    /// Whether any input device is available
    var hasInputDevice: Bool {
        !availableInputDevices().isEmpty
    }

    /// Notification posted when the set of available input devices changes
    static let inputDevicesChangedNotification = Notification.Name("AudioCaptureManagerInputDevicesChanged")

    /// Returns a list of available audio input devices
    func availableInputDevices() -> [(id: AudioDeviceID, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard status == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            return []
        }

        /// Filter to devices that have input streams
        var result: [(id: AudioDeviceID, name: String)] = []

        for deviceID in deviceIDs {
            /// Check if device has input streams
            var inputStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(
                deviceID,
                &inputStreamAddress,
                0, nil,
                &streamSize
            )

            guard streamStatus == noErr,
                  streamSize > 0
            else {
                continue
            }

            /// Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)

            let nameStatus = AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0, nil,
                &nameSize,
                &name
            )

            if nameStatus == noErr {
                result.append((id: deviceID, name: name as String))
            }
        }

        return result
    }

    /// Select an input device. Pass `nil` to revert to system default.
    func selectInputDevice(_ deviceID: AudioDeviceID?) {
        selectedDeviceID = deviceID

        /// Persist selection
        SettingsManager.shared.selectedMicrophoneDeviceID = deviceID.map { UInt32($0) } ?? 0

        /// Apply to audio engine if currently recording
        applySelectedDevice()
    }

    /// Apply the selected device to the audio engine's input node
    private func applySelectedDevice() {
        let inputNode = audioEngine.inputNode

        guard let audioUnit = inputNode.audioUnit else {
            return
        }

        if let deviceID = selectedDeviceID {
            var mutableDeviceID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )

            if status != noErr {
                print("AudioCaptureManager: Failed to set input device (\(deviceID)): \(status)")
            }
        } else {
            /// Revert to system default
            var defaultDeviceID = defaultInputDeviceID()
            if defaultDeviceID != 0 {
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &defaultDeviceID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
            }
        }
    }

    /// Get the currently active device ID on the audio unit
    private func getCurrentDeviceID() -> AudioDeviceID {
        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else { return 0 }
        
        var currentDeviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &currentDeviceID,
            &size
        )
        
        return status == noErr ? currentDeviceID : 0
    }

    /// Get the system default input device ID
    private func defaultInputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : 0
    }

    /// Start listening for device connect/disconnect events
    func startDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }

                let hasDevice = self.hasInputDevice
                AppState.shared.noMicrophoneDetected = !hasDevice

                /// If the selected device was disconnected, revert to system default
                if let selected = self.selectedDeviceID {
                    let available = self.availableInputDevices()
                    if !available.contains(where: { $0.id == selected }) {
                        self.selectedDeviceID = nil
                        SettingsManager.shared.selectedMicrophoneDeviceID = 0
                    }
                }

                NotificationCenter.default.post(
                    name: Self.inputDevicesChangedNotification,
                    object: nil
                )
            }
        }

        deviceChangeListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    /// Stop listening for device changes
    func stopDeviceChangeListener() {
        guard let block = deviceChangeListenerBlock else {
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )

        deviceChangeListenerBlock = nil
    }

    /// Restore the persisted device selection on launch
    func restoreDeviceSelection() {
        let persistedID = SettingsManager.shared.selectedMicrophoneDeviceID

        if persistedID != 0 {
            let available = availableInputDevices()
            if available.contains(where: { $0.id == persistedID }) {
                selectedDeviceID = AudioDeviceID(persistedID)
            }
        }

        /// Update no-mic state
        AppState.shared.noMicrophoneDetected = !hasInputDevice
    }

    // MARK: - FFT

    private var fftSetup: FFTSetup?
    private let fftLog2N: vDSP_Length = 10  // log2(1024)
    private var previousBands = [Float](repeating: 0, count: 6)

    // MARK: - Silence Detection

    /// Time when silence started (nil if currently speaking)
    private var silenceStartTime: Date?

    /// Callback when silence is detected for a brief warning period
    var onSilenceWarning: (() -> Void)?

    /// Callback when silence duration threshold is exceeded (auto-stop)
    var onSilenceThresholdReached: (() -> Void)?

    /// Whether we've already triggered the warning for current silence period
    private var silenceWarningTriggered = false

    /// Warning is triggered at 75% of the configured silence duration
    private var silenceWarningRatio: Double { 0.75 }

    // MARK: - Real-time Audio Streaming

    /// Callback for real-time audio samples (for streaming transcription)
    /// Provides Float32 samples at the input sample rate
    var onAudioSamples: (([Float]) -> Void)?

    /// Callback for resampled 16kHz audio samples (ready for FluidAudio)
    var onResampledAudioSamples: (([Float]) -> Void)?

    // MARK: - Initialization

    private init() {}

    /// Tracks whether the tap is currently installed on the input node
    private var isTapInstalled = false

    /// Throttle audio level updates to 60fps max
    private var lastAudioLevelUpdate = Date.distantPast

    // MARK: - Permission

    /// Request microphone permission
    /// - Parameter completion: Callback with granted status
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Recording

    /// Start recording audio from the microphone
    /// - Throws: AudioCaptureError if recording cannot start
    private func installTapIfNeeded() {
        guard !isTapInstalled else { return }
        let inputNode = audioEngine.inputNode

        // Install tap with nil format — lets AVAudioEngine use the hardware's
        // native format, avoiding stale-format mismatches after engine restarts.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }

            // Lazily create resampling converter from the actual hardware format
            self.audioLock.withLock {
                if self.resamplingConverter == nil {
                    self.resamplingConverter = AVAudioConverter(from: buffer.format, to: self.resampledFormat)
                }
            }

            // Resample mic audio to 16kHz mono
            var micSamples16kHz: [Float] = []
            if let converter = self.audioLock.withLock({ self.resamplingConverter }) {
                let ratio = self.targetSampleRate / buffer.format.sampleRate
                let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

                if let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.resampledFormat, frameCapacity: outputFrameCapacity) {
                    var error: NSError?
                    var consumed = false
                    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                        if consumed {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        consumed = true
                        outStatus.pointee = .haveData
                        return buffer
                    }

                    if error == nil, outputBuffer.frameLength > 0, let channelData = outputBuffer.floatChannelData {
                        micSamples16kHz = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
                    }
                }
            }

            guard !micSamples16kHz.isEmpty else { return }

            // Create a buffer with the resampled samples for downstream processing
            guard let resampledBuffer = AVAudioPCMBuffer(pcmFormat: self.resampledFormat, frameCapacity: AVAudioFrameCount(micSamples16kHz.count)) else { return }
            resampledBuffer.frameLength = AVAudioFrameCount(micSamples16kHz.count)
            if let channelData = resampledBuffer.floatChannelData {
                channelData[0].update(from: micSamples16kHz, count: micSamples16kHz.count)
            }

            // Accumulate buffers for file saving
            if self.accumulateBuffers {
                self.audioLock.withLock {
                    self.recordedBuffers.append(resampledBuffer)
                }
            }

            // Update audio level for visualization
            self.updateAudioLevel(buffer: resampledBuffer)

            // Stream raw samples for real-time processing
            self.onAudioSamples?(micSamples16kHz)

            // Produce 16kHz mono resampled samples for ASR
            self.onResampledAudioSamples?(micSamples16kHz)
        }
        isTapInstalled = true
    }

    func startRecording() throws {
        guard hasMicrophonePermission else {
            throw AudioCaptureError.permissionDenied
        }

        if isRecording {
            print("AudioCaptureManager: Already recording, restarting tap...")
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        // Clear previous buffers and reset audio-thread shared state
        audioLock.withLock {
            recordedBuffers.removeAll()
            previousBands = [Float](repeating: 0, count: 6)
            silenceStartTime = nil
            silenceWarningTriggered = false
            lastAudioLevelUpdate = .distantPast
        }

        let targetDeviceID = selectedDeviceID ?? defaultInputDeviceID()
        let currentDeviceID = getCurrentDeviceID()
        let deviceChanged = (targetDeviceID != 0 && currentDeviceID != targetDeviceID)

        if deviceChanged {
            print("AudioCaptureManager: Device changed from \(currentDeviceID) to \(targetDeviceID), resetting engine")
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
            audioEngine.reset()
            audioLock.withLock { resamplingConverter = nil }
            applySelectedDevice()
        }

        installTapIfNeeded()

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            recordingStartTime = Date()
            print("AudioCaptureManager: Started recording")
        } catch {
            print("AudioCaptureManager: Failed to start engine: \(error.localizedDescription), attempting reset...")
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
            audioEngine.reset()
            audioLock.withLock { resamplingConverter = nil }
            applySelectedDevice()
            installTapIfNeeded()
            
            do {
                audioEngine.prepare()
                try audioEngine.start()
                isRecording = true
                recordingStartTime = Date()
                print("AudioCaptureManager: Started recording after reset")
            } catch let fallbackError {
                audioEngine.inputNode.removeTap(onBus: 0)
                isTapInstalled = false
                throw AudioCaptureError.engineStartFailed(fallbackError)
            }
        }
    }

    /// Stop recording and save to file
    /// - Returns: CaptureResult with file URL and metadata
    /// - Throws: AudioCaptureError if recording cannot be saved
    func stopRecording() throws -> CaptureResult {
        guard isRecording else {
            throw AudioCaptureError.noAudioRecorded
        }

        // Stop the engine and remove tap
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
        isRecording = false
        audioLock.withLock { resamplingConverter = nil }
        accumulateBuffers = true

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        print("AudioCaptureManager: Stopped recording, duration: \(duration)s")

        // Snapshot and clear buffers under lock, then process outside lock
        let bufferSnapshot = audioLock.withLock {
            let snapshot = recordedBuffers
            recordedBuffers.removeAll()
            return snapshot
        }

        guard !bufferSnapshot.isEmpty else {
            throw AudioCaptureError.noAudioRecorded
        }

        // Combine all buffers and save to file
        let fileURL = try saveBuffersToFile(from: bufferSnapshot)

        // Reset audio level
        DispatchQueue.main.async {
            AppState.shared.audioLevel = 0
            AppState.shared.audioFrequencyBands = [Float](repeating: 0, count: 6)
        }
        audioLock.withLock {
            previousBands = [Float](repeating: 0, count: 6)
        }

        return CaptureResult(
            fileURL: fileURL,
            duration: duration,
            sampleRate: targetSampleRate
        )
    }

    /// Pre-warm the AVAudioEngine to eliminate first-use startup latency.
    /// Must be called from the main thread. Safe to call when not recording.
    func warmUp() {
        guard hasMicrophonePermission, !isRecording else { return }
        // Just initialize the input node and apply the device to save time on first start.
        // We avoid calling prepare() and stop() here because starting and immediately
        // stopping the CoreAudio HAL can leave it in a corrupted state where the next
        // start() succeeds but the tap callback never fires.
        _ = audioEngine.inputNode
        applySelectedDevice()
        print("AudioCaptureManager: Engine pre-warmed successfully")
    }

    /// Cancel recording without saving
    func cancelRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        isRecording = false
        audioLock.withLock {
            recordedBuffers.removeAll()
            previousBands = [Float](repeating: 0, count: 6)
        }
        audioLock.withLock { resamplingConverter = nil }
        accumulateBuffers = true

        DispatchQueue.main.async {
            AppState.shared.audioLevel = 0
            AppState.shared.audioFrequencyBands = [Float](repeating: 0, count: 6)
        }

        print("AudioCaptureManager: Recording cancelled")
    }

    // MARK: - Private Methods

    private func saveBuffersToFile(from buffers: [AVAudioPCMBuffer]) throws -> URL {
        guard let firstBuffer = buffers.first else {
            throw AudioCaptureError.noAudioRecorded
        }

        let inputFormat = firstBuffer.format

        // Create output format at target sample rate
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        // Calculate total frame count
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }

        // Create a combined buffer
        guard let combinedBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else {
            throw AudioCaptureError.noAudioRecorded
        }

        // Copy all buffers into combined buffer
        var offset: AVAudioFrameCount = 0
        for buffer in buffers {
            let frameCount = buffer.frameLength
            guard let srcData = buffer.floatChannelData,
                  let dstData = combinedBuffer.floatChannelData else { continue }

            for channel in 0..<Int(inputFormat.channelCount) {
                let src = srcData[channel]
                let dst = dstData[channel].advanced(by: Int(offset))
                dst.update(from: src, count: Int(frameCount))
            }
            offset += frameCount
        }
        combinedBuffer.frameLength = offset

        // Convert to output format if needed
        let finalBuffer: AVAudioPCMBuffer
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw AudioCaptureError.noAudioRecorded
            }

            let ratio = targetSampleRate / inputFormat.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(combinedBuffer.frameLength) * ratio)

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCapacity
            ) else {
                throw AudioCaptureError.noAudioRecorded
            }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return combinedBuffer
            }

            if let error = error {
                throw AudioCaptureError.fileWriteFailed(error)
            }

            finalBuffer = convertedBuffer
        } else {
            finalBuffer = combinedBuffer
        }

        // Generate temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voxnotch_recording_\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // Write to WAV file
        do {
            let audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: targetSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
            )
            try audioFile.write(from: finalBuffer)
            print("AudioCaptureManager: Saved audio to \(fileURL.path)")
            return fileURL
        } catch {
            throw AudioCaptureError.fileWriteFailed(error)
        }
    }

    private func computeFrequencyBands(from samples: [Float], sampleRate: Double) -> [Float] {
        let fftSize = 1024

        if fftSetup == nil {
            fftSetup = vDSP_create_fftsetup(fftLog2N, FFTRadix(kFFTRadix2))
        }
        guard let setup = fftSetup else { return [Float](repeating: 0, count: 6) }

        // Zero-pad or truncate to fftSize
        var input = [Float](repeating: 0, count: fftSize)
        let copyCount = min(samples.count, fftSize)
        input[0..<copyCount] = samples[0..<copyCount]

        // Apply Hann window to reduce spectral leakage
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(fftSize))

        // Pack real array into split complex and run FFT
        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)

                // Interleaved → split complex
                input.withUnsafeBytes { rawPtr in
                    rawPtr.withMemoryRebound(to: DSPComplex.self) { complexPtr in
                        vDSP_ctoz(complexPtr.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }

                // Forward real FFT
                vDSP_fft_zrip(setup, &split, 1, fftLog2N, FFTDirection(FFT_FORWARD))

                // Compute magnitudes (N/2 bins = 0 Hz to Nyquist)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Normalize by FFT size
        var scale = Float(1.0) / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))

        // 6 speech-tuned frequency band boundaries (Hz)
        // Adjusted for 16kHz sample rate (max 8kHz) and speech characteristics
        let boundaries: [Double] = [100, 300, 600, 1000, 2000, 3500, 6000]
        let binWidth = sampleRate / Double(fftSize)

        // Per-band sensitivity boost (higher freqs need more gain in speech)
        let sensitivities: [Float] = [1.5, 2.0, 2.5, 3.5, 8.0, 15.0]
        // dB floor: -45 dB maps to 0, 0 dB maps to 1 (middle ground for sensitivity)
        let dbFloor: Float = -45.0

        let lockedPreviousBands = audioLock.withLock { previousBands }
        var bands = [Float](repeating: 0, count: 6)
        magnitudes.withUnsafeBufferPointer { magBuf in
            for i in 0..<6 {
                let lowBin = max(1, Int(boundaries[i] / binWidth))
                let highBin = min(fftSize / 2 - 1, Int(boundaries[i + 1] / binWidth))
                guard lowBin < highBin else { continue }

                var rms: Float = 0
                vDSP_rmsqv(magBuf.baseAddress!.advanced(by: lowBin), 1, &rms, vDSP_Length(highBin - lowBin))

                let db = 20.0 * log10(max(rms, 1e-10))
                let normalized = max(0, min(1, (db - dbFloor) / (-dbFloor))) * sensitivities[i]
                let target = min(1, normalized)

                // Asymmetric smoothing (fast attack, slow decay)
                let previous = lockedPreviousBands[i]
                if target > previous {
                    // Fast attack (snappy)
                    bands[i] = previous + (target - previous) * 0.95
                } else {
                    // Smooth decay (fluid but returns to 0)
                    bands[i] = previous + (target - previous) * 0.25
                }
            }
        }

        audioLock.withLock {
            previousBands = bands
        }

        return bands
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { channelDataValue[$0] }

        // Calculate RMS
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))

        // Convert to 0-1 range with some scaling for visualization
        let normalizedLevel = min(rms * 3, 1.0)

        let sampleRate = buffer.format.sampleRate
        let bands = computeFrequencyBands(from: channelDataValueArray, sampleRate: sampleRate)

        let now = Date()
        let shouldUpdateLevel = audioLock.withLock {
            if now.timeIntervalSince(lastAudioLevelUpdate) >= 1.0 / 60.0 {
                lastAudioLevelUpdate = now
                return true
            }
            return false
        }
        if shouldUpdateLevel {
            DispatchQueue.main.async {
                AppState.shared.audioLevel = normalizedLevel
                AppState.shared.audioFrequencyBands = bands
            }
        }

        // Silence detection
        let settings = SettingsManager.shared

        guard settings.enableAutoStopOnSilence else {
            // Reset silence tracking when disabled
            audioLock.withLock {
                silenceStartTime = nil
                silenceWarningTriggered = false
            }
            return
        }

        // Convert RMS to dB: 20 * log10(rms)
        // Avoid log of zero by using a minimum value
        let rmsDB: Double
        if rms > 0 {
            rmsDB = 20.0 * log10(Double(rms))
        } else {
            rmsDB = -100.0 // Very quiet
        }

        let isSilent = rmsDB < settings.silenceThresholdDB

        audioLock.withLock {
            if isSilent {
                // Start or continue silence tracking
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                    silenceWarningTriggered = false
                }

                if let startTime = silenceStartTime {
                    let silenceDuration = Date().timeIntervalSince(startTime)
                    let thresholdDuration = settings.silenceDurationSeconds

                    // Check for warning (75% of threshold)
                    if !silenceWarningTriggered && silenceDuration >= thresholdDuration * silenceWarningRatio {
                        silenceWarningTriggered = true
                        DispatchQueue.main.async { [weak self] in
                            self?.onSilenceWarning?()
                        }
                    }

                    // Check for auto-stop threshold
                    if silenceDuration >= thresholdDuration {
                        DispatchQueue.main.async { [weak self] in
                            self?.onSilenceThresholdReached?()
                        }
                        // Reset to prevent repeated triggers
                        silenceStartTime = nil
                        silenceWarningTriggered = false
                    }
                }
            } else {
                // Speech detected, reset silence tracking
                silenceStartTime = nil
                silenceWarningTriggered = false
            }
        }
    }

    // MARK: - Resampling
    // (Resampling is now handled inline in installTapIfNeeded to support mixing)

    // MARK: - Sample Extraction

    /// Extract Float32 samples from an audio buffer
    /// - Parameter buffer: The audio buffer
    /// - Returns: Array of Float32 samples (first channel only)
    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(buffer.frameLength)
        ))
    }

    // MARK: - Cleanup

    /// Clean up a recorded audio file
    /// - Parameter url: The file URL to delete
    func cleanupFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        print("AudioCaptureManager: Cleaned up file at \(url.path)")
    }
}
