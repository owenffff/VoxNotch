//
//  DictationStateMachine.swift
//  VoxNotch
//
//  Owns the dictation state, session lifecycle, timer management, and
//  pipeline orchestration (record → transcribe → LLM → output → history).
//  The controller wires events here and translates callbacks into UI side effects.
//

import AppKit
import Foundation
import GRDB
import os.log

// MARK: - Delegate

/// Notified on every state transition so the controller can sync AppState / UI.
@MainActor protocol DictationStateMachineDelegate: AnyObject {
    func stateMachine(
        _ stateMachine: DictationStateMachine,
        didTransitionFrom oldState: DictationState,
        to newState: DictationState
    )
}

// MARK: - State Machine

@MainActor
final class DictationStateMachine {

    private let logger = Logger(subsystem: "com.voxnotch", category: "DictationStateMachine")

    // MARK: - State Properties

    /// Current dictation state.
    private(set) var state: DictationState = .idle

    /// Session ID — incremented on cancel so in-flight async tasks know to discard.
    private(set) var currentSessionID = UUID()

    /// Recording start time.
    var recordingStartTime: Date?

    /// Timestamp of last cancel — used for cooldown between rapid presses.
    var lastCancelTime: Date?

    /// Minimum recording duration to avoid accidental taps and phantom words.
    let minimumRecordingDuration: TimeInterval = 0.5

    /// Delegate receives every state transition.
    weak var delegate: DictationStateMachineDelegate?

    // MARK: - Dependencies

    private let audioManager: AudioRecording
    private let transcriptionEngine: TranscriptionEngine
    private let llmProcessor: LLMProcessing
    private let textOutputManager: TextOutputting

    // MARK: - Timers

    private var watchdogTimer: Timer?
    private var durationTimer: Timer?

    // MARK: - Callbacks

    /// Fired every second while recording, providing elapsed time.
    var onRecordingDurationTick: ((TimeInterval) -> Void)?

    /// Fired when the watchdog triggers (stuck recording).
    var onWatchdogFired: (() -> Void)?

    /// Fired after successful text output. Bool = wasClipboard (no focused text field).
    var onPipelineOutputSuccess: ((_ wasClipboard: Bool) -> Void)?

    /// Fired when the pipeline is cancelled (too short, etc.) so the controller can hide UI.
    var onPipelineCancelled: (() -> Void)?

    /// Fired when LLM fails but transcription succeeded (non-blocking warning).
    var onLLMWarning: ((_ message: String) -> Void)?

    /// Fired before .error transition when audio is preserved for retry.
    var onPipelineErrorWithAudio: ((_ audioURL: URL) -> Void)?

    // MARK: - Initialization

    init(
        audioManager: AudioRecording = AudioCaptureManager.shared,
        transcriptionEngine: TranscriptionEngine = TranscriptionService.shared,
        llmProcessor: LLMProcessing = LLMService.shared,
        textOutputManager: TextOutputting = TextOutputManager.shared
    ) {
        self.audioManager = audioManager
        self.transcriptionEngine = transcriptionEngine
        self.llmProcessor = llmProcessor
        self.textOutputManager = textOutputManager
    }

    // MARK: - State Transitions

    /// Transition to a new state. Manages timers and notifies the delegate.
    func transition(to newState: DictationState) {
        let oldState = state
        assert(
            Self.isValidTransition(from: oldState, to: newState),
            "Invalid state transition: \(oldState) → \(newState)"
        )
        state = newState

        // Duration timer: only runs during .recording
        if case .recording = newState {} else {
            stopDurationTimer()
        }

        // Watchdog timer: start on recording, stop on anything else
        stopWatchdog()
        if case .recording = newState {
            startWatchdog()
        }

        delegate?.stateMachine(self, didTransitionFrom: oldState, to: newState)
    }

    /// Valid transitions per the dictation flow graph.
    ///
    ///     idle → idle | recording | modelSelecting | toneSelecting | warmingUp
    ///     recording → warmingUp | transcribing | idle | error
    ///     warmingUp → transcribing | idle | error
    ///     transcribing → processingLLM | outputting | idle | error
    ///     processingLLM → outputting | idle
    ///     outputting → idle | error
    ///     modelSelecting → idle | toneSelecting
    ///     toneSelecting → idle | modelSelecting
    ///     error → idle | warmingUp
    ///
    private static func isValidTransition(from oldState: DictationState, to newState: DictationState) -> Bool {
        switch oldState {
        case .idle:
            switch newState {
            case .idle, .recording, .modelSelecting, .toneSelecting, .warmingUp:
                return true
            default:
                return false
            }
        case .recording:
            switch newState {
            case .warmingUp, .transcribing, .idle, .error:
                return true
            default:
                return false
            }
        case .warmingUp:
            switch newState {
            case .transcribing, .idle, .error:
                return true
            default:
                return false
            }
        case .transcribing:
            switch newState {
            case .processingLLM, .outputting, .idle, .error:
                return true
            default:
                return false
            }
        case .processingLLM:
            switch newState {
            case .outputting, .idle:
                return true
            default:
                return false
            }
        case .outputting:
            switch newState {
            case .idle, .error:
                return true
            default:
                return false
            }
        case .modelSelecting:
            switch newState {
            case .idle, .toneSelecting:
                return true
            default:
                return false
            }
        case .toneSelecting:
            switch newState {
            case .idle, .modelSelecting:
                return true
            default:
                return false
            }
        case .error:
            switch newState {
            case .idle, .warmingUp:
                return true
            default:
                return false
            }
        }
    }

    /// Invalidate the current session (cancel in-flight work).
    @discardableResult
    func invalidateSession() -> UUID {
        let newID = UUID()
        currentSessionID = newID
        return newID
    }

    /// Check whether a captured session ID still matches the current session.
    func isSessionValid(_ sessionID: UUID) -> Bool {
        return sessionID == currentSessionID
    }

    // MARK: - Pipeline: Begin Recording

    /// Begin audio capture. Called by controller after pre-flight checks pass.
    func beginRecording() throws {
        transition(to: .recording)
        recordingStartTime = Date()
        startDurationTimer()

        audioManager.accumulateBuffers = true
        try audioManager.startRecording()
        transcriptionEngine.preloadModel()
    }

    // MARK: - Pipeline: Stop Recording & Transcribe

    /// Stop recording and run the full pipeline: transcribe → LLM → output → history.
    func stopRecordingAndTranscribe(savedFrontmostApp: NSRunningApplication?) {
        guard case .recording = state else { return }

        // Check minimum duration
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        if duration < minimumRecordingDuration {
            cancelPipeline()
            onPipelineCancelled?()
            return
        }

        // Stop audio capture
        let captureResult: AudioCaptureManager.CaptureResult
        do {
            captureResult = try audioManager.stopRecording()
        } catch {
            audioManager.cancelRecording()
            transition(to: .error(error))
            return
        }

        let capturedSessionID = currentSessionID

        Task {
            var shouldCleanupAudio = true
            defer {
                if shouldCleanupAudio {
                    audioManager.cleanupFile(at: captureResult.fileURL)
                }
            }

            do {
                // Check model ready → warmingUp or transcribing
                let isReady = await transcriptionEngine.isReady
                await MainActor.run {
                    transition(to: isReady ? .transcribing : .warmingUp)
                }

                try await transcriptionEngine.ensureModelReady()
                guard isSessionValid(capturedSessionID) else { return }

                if !isReady {
                    await MainActor.run { transition(to: .transcribing) }
                }

                // Transcribe
                let result = try await transcriptionEngine.transcribe(audioURL: captureResult.fileURL, language: nil)
                guard isSessionValid(capturedSessionID) else { return }

                // Post-process text
                let text: String = {
                    let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let filtered = SettingsManager.shared.removeFillerWords ? FillerWordFilter.clean(raw) : raw
                    return SettingsManager.shared.applyITN ? NemoTextProcessing.normalizeSentence(filtered) : filtered
                }()

                // Empty rejection
                if text.isEmpty {
                    await MainActor.run { transition(to: .idle) }
                    return
                }

                // Low-confidence rejection
                if let confidence = result.confidence, confidence < 0.45 {
                    await MainActor.run { transition(to: .idle) }
                    return
                }

                // LLM processing
                await MainActor.run { transition(to: .processingLLM) }
                guard isSessionValid(capturedSessionID) else { return }

                let finalText: String
                if llmProcessor.isEnabled {
                    let llmResult = await llmProcessor.processWithResult(text: text)
                    finalText = llmResult.text
                    if case .fallback(_, let error) = llmResult {
                        await MainActor.run { onLLMWarning?(error.localizedDescription) }
                    }
                } else {
                    finalText = text
                }

                // History save (non-blocking)
                saveToHistory(
                    rawText: text,
                    finalText: finalText,
                    captureResult: captureResult,
                    transcriptionResult: result,
                    savedFrontmostApp: savedFrontmostApp
                )

                // Output text
                await outputText(finalText, savedFrontmostApp: savedFrontmostApp)

            } catch {
                guard isSessionValid(capturedSessionID) else { return }
                shouldCleanupAudio = false
                await MainActor.run {
                    onPipelineErrorWithAudio?(captureResult.fileURL)
                    transition(to: .error(error))
                }
            }
        }
    }

    // MARK: - Pipeline: Retry Transcription

    /// Retry transcription using a previously saved audio file. Skips LLM.
    func retryTranscription(audioURL: URL, savedFrontmostApp: NSRunningApplication?) {
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }

        let capturedSessionID = currentSessionID

        Task {
            do {
                await MainActor.run { transition(to: .warmingUp) }
                try await transcriptionEngine.ensureModelReady()
                guard isSessionValid(capturedSessionID) else { return }

                await MainActor.run { transition(to: .transcribing) }
                let result = try await transcriptionEngine.transcribe(audioURL: audioURL, language: nil)
                guard isSessionValid(capturedSessionID) else { return }

                let text = result.text
                guard !text.isEmpty else {
                    await MainActor.run { transition(to: .error(TranscriptionError.noSpeechDetected)) }
                    return
                }

                audioManager.cleanupFile(at: audioURL)
                await outputText(text, savedFrontmostApp: savedFrontmostApp)

            } catch {
                guard isSessionValid(capturedSessionID) else { return }
                await MainActor.run { transition(to: .error(error)) }
            }
        }
    }

    // MARK: - Pipeline: Output Text

    private func outputText(_ text: String, savedFrontmostApp: NSRunningApplication?) async {
        let hasFocusedInput = textOutputManager.hasFocusedTextInput(for: savedFrontmostApp)

        await MainActor.run { transition(to: .outputting) }

        if hasFocusedInput {
            do {
                try await textOutputManager.output(text)
                textOutputManager.copyToClipboardOnly(text)
                await MainActor.run {
                    onPipelineOutputSuccess?(false)
                    transition(to: .idle)
                }
            } catch {
                await MainActor.run { transition(to: .error(error)) }
            }
        } else {
            textOutputManager.copyToClipboardOnly(text)
            await MainActor.run {
                onPipelineOutputSuccess?(true)
                transition(to: .idle)
            }
        }
    }

    // MARK: - Pipeline: History Save

    private func saveToHistory(
        rawText: String,
        finalText: String,
        captureResult: AudioCaptureManager.CaptureResult,
        transcriptionResult: TranscriptionResult,
        savedFrontmostApp: NSRunningApplication?
    ) {
        guard SettingsManager.shared.historyEnabled else { return }

        var audioPath: String? = nil
        if SettingsManager.shared.saveAudioRecordings {
            let audioDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("VoxNotch/audio", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
                let dest = audioDir.appendingPathComponent("\(UUID().uuidString).wav")
                try FileManager.default.copyItem(at: captureResult.fileURL, to: dest)
                audioPath = dest.path
            } catch {
                logger.error("Failed to save audio recording: \(error.localizedDescription)")
            }
        }

        let toneID = SettingsManager.shared.activeToneID
        let toneName = ToneRegistry.shared.tone(forID: toneID)?.displayName ?? toneID
        let hasFocusedInput = textOutputManager.hasFocusedTextInput(for: savedFrontmostApp)
        let metadataDict: [String: String] = [
            "tone": toneName,
            "outputMethod": hasFocusedInput ? "paste" : "clipboard",
        ]
        let metadataJSON: String?
        do {
            let data = try JSONEncoder().encode(metadataDict)
            metadataJSON = String(data: data, encoding: .utf8)
        } catch {
            logger.error("Failed to encode history metadata: \(error.localizedDescription)")
            metadataJSON = nil
        }

        let processedText = (finalText != rawText) ? finalText : nil
        var record = TranscriptionRecord(
            rawText: rawText,
            processedText: processedText,
            model: SettingsManager.shared.speechModel,
            duration: captureResult.duration,
            confidence: transcriptionResult.confidence.map(Double.init),
            audioPath: audioPath,
            metadata: metadataJSON
        )
        Task {
            do {
                _ = try await DatabaseManager.shared.write { db in
                    try record.insert(db)
                }
            } catch {
                logger.error("Failed to save history: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Session Management

    /// Cancel audio without hiding the notch. Used for model/tone selection during recording.
    func stopRecordingQuietly() {
        invalidateSession()
        audioManager.cancelRecording()
        stopDurationTimer()
        transition(to: .idle)
    }

    /// Cancel any active pipeline. Invalidates session, stops audio, transitions to idle.
    func cancelPipeline() {
        lastCancelTime = Date()
        invalidateSession()
        audioManager.cancelRecording()
        transition(to: .idle)
    }

    /// Passthrough to reconfigure the transcription engine (e.g., after model switch).
    func reconfigureTranscription() {
        transcriptionEngine.reconfigure()
    }

    // MARK: - Duration Timer

    /// Start the duration timer.
    func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.recordingStartTime else { return }
                self.onRecordingDurationTick?(Date().timeIntervalSince(start))
            }
        }
    }

    /// Stop the duration timer.
    func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 180.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onWatchdogFired?()
            }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }
}
