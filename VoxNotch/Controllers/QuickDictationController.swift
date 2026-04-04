//
//  QuickDictationController.swift
//  VoxNotch
//
//  Orchestrates the Quick Dictation flow: hotkey -> record -> transcribe -> output
//

import AppKit
import Foundation

/// Controller for Quick Dictation mode (hold-to-record, release to transcribe)
final class QuickDictationController {

    // MARK: - Types

    /// Dictation state
    enum State {
        case idle
        case recording
        case warmingUp
        case transcribing
        case processingLLM
        case outputting
        case modelSelecting
        case toneSelecting
        case error(Error)
    }

    /// Callback for state changes
    typealias StateCallback = (State) -> Void

    // MARK: - Properties

    static let shared = QuickDictationController()

    /// Current dictation state
    private(set) var state: State = .idle

    /// Callback for state changes
    var onStateChange: StateCallback?

    /// Whether dictation is currently active
    var isActive: Bool {
        switch state {
        case .recording, .warmingUp, .transcribing, .processingLLM, .outputting:
            return true
        case .idle, .modelSelecting, .toneSelecting, .error:
            return false
        }
    }

    // Dependencies
    private let hotkeyManager: HotkeyManager
    private let audioManager: AudioCaptureManager
    private let textOutputManager: TextOutputManager
    private let appState: AppState

    /// Minimum recording duration to avoid accidental taps
    private let minimumRecordingDuration: TimeInterval = 0.2

    /// Recording start time for duration check
    private var recordingStartTime: Date?

    /// Session ID incremented on cancel so in-flight transcription tasks know to discard results
    private var currentSessionID = UUID()

    /// The frontmost application when the user pressed the hotkey.
    /// Captured before the notch panel appears so AX queries target the correct app.
    private var savedFrontmostApp: NSRunningApplication?

    /// Watchdog timer to prevent stuck recording state
    private var watchdogTimer: Timer?

    /// Timer that updates appState.recordingDuration every second while recording
    private var durationTimer: Timer?

    // MARK: - Initialization

    private init() {
        self.hotkeyManager = HotkeyManager.shared
        self.audioManager = AudioCaptureManager.shared
        self.textOutputManager = TextOutputManager.shared
        self.appState = AppState.shared

        setupHotkeyHandler()
        setupModelSwitchHandler()
        setupToneSwitchHandler()
        setupSilenceDetection()
        setupEscapeHandler()
    }

    // MARK: - Setup

    private func setupHotkeyHandler() {
        hotkeyManager.onHotkeyEvent = { [weak self] event in
            print("QuickDictationController: Received hotkey event: \(event)")
            switch event {
            case .keyDown:
                print("QuickDictationController: Starting recording...")
                self?.startRecording()
            case .keyUp:
                if case .modelSelecting = self?.state {
                    print("QuickDictationController: Confirming model selection...")
                    self?.confirmModelSelection()
                } else if case .toneSelecting = self?.state {
                    print("QuickDictationController: Confirming tone selection...")
                    self?.confirmToneSelection()
                } else {
                    print("QuickDictationController: Stopping recording...")
                    self?.stopRecordingAndTranscribe()
                }
            }
        }
    }

    private func setupModelSwitchHandler() {
        hotkeyManager.onModelSwitchKey = { [weak self] direction in
            self?.handleModelSwitchRequest(direction: direction)
        }
    }

    private func setupToneSwitchHandler() {
        hotkeyManager.onToneSwitchKey = { [weak self] direction in
            self?.handleToneSwitchRequest(direction: direction)
        }
    }

    private func setupEscapeHandler() {
        hotkeyManager.onEscapeKey = { [weak self] in
            guard let self else { return }
            guard self.isActive else { return }
            self.cancelCurrentSession()
        }
    }

    private func setupSilenceDetection() {
        /// Warning callback - show visual feedback that auto-stop is coming
        audioManager.onSilenceWarning = { [weak self] in
            guard let self = self,
                  case .recording = self.state
            else {
                return
            }

            self.appState.silenceWarningActive = true
        }

        /// Threshold reached callback - auto-stop recording
        audioManager.onSilenceThresholdReached = { [weak self] in
            guard let self = self,
                  case .recording = self.state
            else {
                return
            }

            self.appState.silenceWarningActive = false
            self.stopRecordingAndTranscribe()
        }
    }

    /// Timer for retrying hotkey listener after permission is granted
    private var permissionCheckTimer: Timer?

    /// Start the Quick Dictation controller
    func start() {
        // Request permissions if needed
        if !hotkeyManager.hasAccessibilityPermission {
            hotkeyManager.requestAccessibilityPermission()
        }

        if !audioManager.hasMicrophonePermission {
            audioManager.requestMicrophonePermission { _ in }
        }

        // Try to start listening for hotkeys
        if hotkeyManager.startListening() {
            print("QuickDictationController: Hotkey listener started successfully")
        } else {
            // Permission not yet granted - poll until it is
            print("QuickDictationController: Waiting for accessibility permission...")
            startPermissionCheck()
        }
    }

    /// Poll for accessibility permission and start listener when granted
    private func startPermissionCheck() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            if self.hotkeyManager.hasAccessibilityPermission {
                timer.invalidate()
                self.permissionCheckTimer = nil

                if self.hotkeyManager.startListening() {
                    print("QuickDictationController: Hotkey listener started after permission granted")
                }
            }
        }
    }

    /// Stop the Quick Dictation controller
    func stop() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        hotkeyManager.stopListening()
        if audioManager.isRecording {
            audioManager.cancelRecording()
        }
        updateState(.idle)
    }

    // MARK: - Click-to-Dictate

    /// Toggle dictation on/off via click (alternative to hold-to-record hotkey)
    func toggleDictation() {
        switch state {
        case .idle, .error, .modelSelecting, .toneSelecting:
            startRecording()

        case .recording:
            stopRecordingAndTranscribe()

        case .warmingUp, .transcribing, .processingLLM, .outputting:
            break
        }
    }

    // MARK: - Recording Flow

    private func startRecording() {
        print("QuickDictationController: startRecording called, state: \(state)")

        // Clear any previous errors when starting a new recording
        appState.clearError()

        // If we are already recording, ignore
        if case .recording = state {
            return
        }

        // If we are transcribing, outputting, or in error, cancel the current session to start a new one
        if case .warmingUp = state {
            cancelCurrentSession()
        } else if case .transcribing = state {
            cancelCurrentSession()
        } else if case .processingLLM = state {
            cancelCurrentSession()
        } else if case .outputting = state {
            cancelCurrentSession()
        } else if case .error = state {
            cancelCurrentSession()
        }

        // Ensure we are back to idle before starting
        state = .idle

        // If the selected model is not downloaded, notify user and don't record
        let speechModelID = SettingsManager.shared.speechModel
        let (builtinModel, customModel) = SpeechModel.resolve(speechModelID)
        let isModelDownloaded: Bool
        let modelDisplayName: String
        if let builtin = builtinModel {
            isModelDownloaded = builtin.isDownloaded
            modelDisplayName = builtin.displayName
        } else if let custom = customModel {
            isModelDownloaded = custom.isDownloaded
            modelDisplayName = custom.displayName
        } else {
            isModelDownloaded = false
            modelDisplayName = "Unknown"
        }
        if !isModelDownloaded {
            print("QuickDictationController: Model not downloaded, directing to Settings")
            appState.modelsNeeded = true
            appState.modelsNeededMessage = "Model not downloaded: \(modelDisplayName)"
            NotchManager.shared.showModelsNeeded(appState.modelsNeededMessage)
            return
        }

        // Request mic permission if needed
        guard audioManager.hasMicrophonePermission else {
            print("QuickDictationController: No mic permission, requesting...")
            audioManager.requestMicrophonePermission { [weak self] granted in
                print("QuickDictationController: Mic permission result: \(granted)")
                if granted {
                    self?.startRecording()
                }
            }
            return
        }

        print("QuickDictationController: Starting audio capture...")

        // Capture the frontmost app BEFORE showing the notch panel,
        // so AX queries later target the correct application.
        savedFrontmostApp = NSWorkspace.shared.frontmostApplication

        // Set recording state synchronously so keyUp can always see it
        updateState(.recording)
        recordingStartTime = Date()
        appState.recordingDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.appState.recordingDuration = Date().timeIntervalSince(start)
        }

        // Accumulate buffers for batch transcription (save to WAV file on stop)
        audioManager.accumulateBuffers = true

        do {
            try audioManager.startRecording()
            print("QuickDictationController: Audio capture started")

            // Preload the model in the background to reduce cold start time
            TranscriptionService.shared.preloadModel()
        } catch {
            print("QuickDictationController: Failed to start audio capture: \(error)")
            updateState(.error(error))
            return
        }
    }

    private func stopRecordingAndTranscribe() {
        guard case .recording = state else {
            print("QuickDictationController: stopRecordingAndTranscribe ignored, state: \(state)")
            return
        }

        // Check minimum duration
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        print("QuickDictationController: Recording duration: \(String(format: "%.2f", duration))s")
        if duration < minimumRecordingDuration {
            print("QuickDictationController: Too short, cancelling")
            cancelCurrentSession()
            return
        }

        // Stop audio capture and save to WAV file
        let captureResult: AudioCaptureManager.CaptureResult
        do {
            captureResult = try audioManager.stopRecording()
            print("QuickDictationController: Audio saved to \(captureResult.fileURL.lastPathComponent), duration: \(String(format: "%.2f", captureResult.duration))s")
        } catch {
            print("QuickDictationController: Failed to stop recording: \(error)")
            audioManager.cancelRecording()
            updateState(.error(error))
            return
        }

        // Capture session ID to detect cancellation during async work
        let capturedSessionID = currentSessionID

        // Transcribe using batch ASR
        Task {
            defer { audioManager.cleanupFile(at: captureResult.fileURL) }

            do {
                // Check if model is ready, if not show warming up state
                let isReady = await TranscriptionService.shared.isReady
                if !isReady {
                    await MainActor.run {
                        updateState(.warmingUp)
                    }
                } else {
                    await MainActor.run {
                        updateState(.transcribing)
                    }
                }

                // Ensure batch model is loaded (will block if not ready)
                try await TranscriptionService.shared.ensureModelReady()

                guard capturedSessionID == self.currentSessionID else {
                    print("QuickDictationController: Session cancelled after ensureModelReady, discarding")
                    return
                }

                // Transition to transcribing state if we were warming up
                if !isReady {
                    await MainActor.run {
                        updateState(.transcribing)
                    }
                }

                // Transcribe the WAV file
                let result = try await TranscriptionService.shared.transcribe(audioURL: captureResult.fileURL)

                guard capturedSessionID == self.currentSessionID else {
                    print("QuickDictationController: Session cancelled after transcription, discarding")
                    return
                }

                let text: String = {
                  let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                  let filtered = SettingsManager.shared.removeFillerWords ? FillerWordFilter.clean(raw) : raw
                  return SettingsManager.shared.applyITN ? NemoTextProcessing.normalizeSentence(filtered) : filtered
                }()
                print("QuickDictationController: Transcribed text: '\(text)'")

                if text.isEmpty {
                    print("QuickDictationController: Empty transcription, returning to idle")
                    await MainActor.run {
                        updateState(.idle)
                    }
                    return
                }

                // Transition to LLM processing state
                await MainActor.run {
                    updateState(.processingLLM)
                }

                guard capturedSessionID == self.currentSessionID else {
                    print("QuickDictationController: Session cancelled before LLM, discarding")
                    return
                }

                let finalText: String
                if LLMService.shared.isEnabled {
                    let result = await LLMService.shared.processWithResult(text: text)
                    finalText = result.text

                    // Non-blocking: warn user if LLM failed but still output original text
                    if case .fallback(_, let error) = result {
                        await MainActor.run {
                            self.appState.setLLMWarning(error.localizedDescription, canRetry: false)
                        }
                    }
                } else {
                    finalText = text
                }

                // Output the text
                await outputText(finalText)

            } catch {
                guard capturedSessionID == self.currentSessionID else {
                    print("QuickDictationController: Session cancelled during error handling, discarding")
                    return
                }
                print("QuickDictationController: Transcription failed: \(error)")
                await MainActor.run {
                    updateState(.error(error))
                }
            }
        }
    }

    private func outputText(_ text: String) async {
        print("QuickDictationController: Outputting text: '\(text)'")

        // Detect focused text input BEFORE transitioning to .outputting,
        // because the notch feedback fires on that state transition.
        let hasFocusedInput = textOutputManager.hasFocusedTextInput(for: savedFrontmostApp)
        print("QuickDictationController: hasFocusedTextInput=\(hasFocusedInput)")

        await MainActor.run {
            appState.lastOutputWasClipboard = !hasFocusedInput
            updateState(.outputting)
        }

        if hasFocusedInput {
            do {
                try await textOutputManager.output(text)
                print("QuickDictationController: Text output succeeded")
                await MainActor.run {
                    NotchManager.shared.showSuccess()
                    updateState(.idle)
                }
            } catch {
                print("QuickDictationController: Text output failed: \(error)")
                await MainActor.run {
                    updateState(.error(error))
                }
            }
        } else {
            // No focused text input — copy to clipboard silently
            print("QuickDictationController: No focused text input, copying to clipboard")
            textOutputManager.copyToClipboardOnly(text)
            await MainActor.run {
                NotchManager.shared.showClipboard()
                updateState(.idle)
            }
        }
    }

    // MARK: - Session Management

    /// Stop recording and discard audio without hiding the notch.
    /// Used when transitioning from recording directly into model/tone selection
    /// so the expanded panel stays visible and content swaps seamlessly.
    private func stopRecordingQuietly() {
        currentSessionID = UUID()
        savedFrontmostApp = nil
        audioManager.cancelRecording()
        durationTimer?.invalidate()
        durationTimer = nil
        appState.recordingDuration = 0
        // Transition to idle without triggering NotchManager.hide()
        state = .idle
        appState.isRecording = false
        appState.silenceWarningActive = false
    }

    /// Force cancel any active recording or transcription.
    /// Increments currentSessionID to invalidate any in-flight transcription tasks.
    private func cancelCurrentSession() {
        print("QuickDictationController: Cancelling current session")
        currentSessionID = UUID()
        savedFrontmostApp = nil

        // Stop audio capture
        audioManager.cancelRecording()

        updateState(.idle)
        NotchManager.shared.hide()
    }

    // MARK: - Tone Selection

    private func handleToneSwitchRequest(direction: Int) {
        // Ignore if model selection is already active (one picker at a time)
        if case .modelSelecting = state { return }

        // If recording, stop recording quietly without hiding the notch
        // so the transition to tone selection is seamless.
        if case .recording = state {
            stopRecordingQuietly()
        }

        // Enter or advance tone selection
        if case .toneSelecting = state {
            cycleToneSelection(direction: direction)
        } else {
            enterToneSelectionMode(direction: direction)
        }
    }

    /// Returns the tones pinned to quick-switch slots, always prepending "Original"
    private func getPinnedTones() -> [ToneTemplate] {
        let ids = SettingsManager.shared.pinnedToneIDs.isEmpty
            ? ["cleanup", "punctuation", "filler-removal"]
            : SettingsManager.shared.pinnedToneIDs
        let pinned = ids.compactMap { ToneRegistry.shared.tone(forID: $0) }
        if let noneTone = ToneRegistry.shared.tone(forID: "none") {
            return [noneTone] + pinned
        }
        return pinned
    }

    private func enterToneSelectionMode(direction: Int) {
        let candidates = getPinnedTones()
        appState.toneSelectionCandidates = candidates
        appState.toneSelectionIndex = 0
        updateState(.toneSelecting)
    }

    private func cycleToneSelection(direction: Int) {
        let total = appState.toneSelectionCandidates.count + 1 // +1 for "More Tones..."
        let current = appState.toneSelectionIndex
        appState.toneSelectionIndex = ((current + direction) + total) % total
    }

    private func confirmToneSelection() {
        let index = appState.toneSelectionIndex
        let candidates = appState.toneSelectionCandidates

        if index >= candidates.count {
            // "More Tones..." — open Settings → dictationAI panel
            appState.navigateToSettingsPanel = SettingsPanel.dictationAI.rawValue
            SettingsWindowController.shared.showNavigatingToAIEnhancement()
        } else {
            // Apply the selected tone
            let selected = candidates[index]
            SettingsManager.shared.activeToneID = selected.id
            print("QuickDictationController: Tone switched to \(selected.displayName)")
        }

        updateState(.idle)
        NotchManager.shared.hide()
    }

    // MARK: - Model Selection

    private func handleModelSwitchRequest(direction: Int) {
        // Ignore if tone selection is already active (one picker at a time)
        if case .toneSelecting = state { return }

        // If recording, stop recording quietly without hiding the notch
        // so the transition to model selection is seamless.
        if case .recording = state {
            stopRecordingQuietly()
        }

        // Enter or advance model selection
        if case .modelSelecting = state {
            cycleModelSelection(direction: direction)
        } else {
            enterModelSelectionMode(direction: direction)
        }
    }

    /// Returns the models pinned to quick-switch slots (from Settings, defaulting to first 3 built-ins)
    private func getPinnedModels() -> [AnyModel] {
        let ids = SettingsManager.shared.pinnedModelIDs.isEmpty
            ? Array(SpeechModel.allCases.prefix(3)).map(\.rawValue)
            : SettingsManager.shared.pinnedModelIDs
        return ids.compactMap { id -> AnyModel? in
            if let builtin = SpeechModel(rawValue: id) { return .builtin(builtin) }
            if let custom = CustomModelRegistry.shared.model(withID: id) { return .custom(custom) }
            return nil
        }
    }

    private func enterModelSelectionMode(direction: Int) {
        let candidates = getPinnedModels()

        appState.modelSelectionCandidates = candidates
        appState.modelSelectionIndex = 0
        updateState(.modelSelecting)
    }

    private func cycleModelSelection(direction: Int) {
        let total = appState.modelSelectionCandidates.count + 1 // +1 for "More Models..."
        let current = appState.modelSelectionIndex
        appState.modelSelectionIndex = ((current + direction) + total) % total
    }

    private func confirmModelSelection() {
        let index = appState.modelSelectionIndex
        let candidates = appState.modelSelectionCandidates

        if index >= candidates.count {
            // "More Models..." — open Settings → dictationSpeechModel panel
            appState.navigateToSettingsPanel = SettingsPanel.dictationSpeechModel.rawValue
            SettingsWindowController.shared.showNavigatingToSpeechModel()
        } else {
            // Apply the selected model
            let selected = candidates[index]
            SettingsManager.shared.speechModel = selected.settingsID
            TranscriptionService.shared.reconfigure()
            print("QuickDictationController: Model switched to \(selected.displayName)")
        }

        updateState(.idle)
        NotchManager.shared.hide()
    }

    // MARK: - State Management

    private func updateState(_ newState: State) {
        state = newState

        // Stop duration timer when leaving recording
        if case .recording = newState {} else {
            durationTimer?.invalidate()
            durationTimer = nil
            appState.recordingDuration = 0
        }

        // Manage watchdog timer
        watchdogTimer?.invalidate()
        watchdogTimer = nil

        if case .recording = newState {
            // Start a 10-minute watchdog to prevent stuck expanded pill
            watchdogTimer = Timer.scheduledTimer(withTimeInterval: 600.0, repeats: false) { [weak self] _ in
                print("QuickDictationController: Watchdog triggered - force resetting stuck recording state")
                self?.cancelCurrentSession()
            }
        }

        // Update app state
        switch newState {
        case .idle:
            appState.isRecording = false
            appState.isWarmingUp = false
            appState.isTranscribing = false
            appState.isProcessingLLM = false
            appState.silenceWarningActive = false
            appState.isModelSelecting = false
            appState.isToneSelecting = false
            // Don't call hide() here — transient states handle their own auto-hide
            break

        case .recording:
            appState.isRecording = true
            appState.isWarmingUp = false
            appState.isTranscribing = false
            appState.silenceWarningActive = false
            appState.isModelSelecting = false
            appState.isToneSelecting = false
            NotchManager.shared.showRecording()

        case .warmingUp:
            appState.isRecording = false
            appState.isWarmingUp = true
            appState.isTranscribing = false
            appState.silenceWarningActive = false
            appState.isModelSelecting = false
            appState.isToneSelecting = false
            NotchManager.shared.showTranscribing()

        case .transcribing:
            appState.isRecording = false
            appState.isWarmingUp = false
            appState.isTranscribing = true
            appState.silenceWarningActive = false
            appState.isModelSelecting = false
            appState.isToneSelecting = false
            NotchManager.shared.showTranscribing()

        case .processingLLM:
            appState.isRecording = false
            appState.isWarmingUp = false
            appState.isTranscribing = false
            appState.isProcessingLLM = true
            appState.silenceWarningActive = false
            appState.isModelSelecting = false
            appState.isToneSelecting = false
            NotchManager.shared.showProcessingLLM()

        case .outputting:
            appState.isRecording = false
            appState.isWarmingUp = false
            appState.isTranscribing = false
            appState.isProcessingLLM = false
            appState.silenceWarningActive = false
            appState.isModelSelecting = false
            appState.isToneSelecting = false
            // Success/clipboard shown from outputText() method
            break

        case .modelSelecting:
            appState.isRecording = false
            appState.isWarmingUp = false
            appState.isTranscribing = false
            appState.isProcessingLLM = false
            appState.silenceWarningActive = false
            appState.isModelSelecting = true
            appState.isToneSelecting = false
            NotchManager.shared.showModelSelector()

        case .toneSelecting:
            appState.isRecording = false
            appState.isWarmingUp = false
            appState.isTranscribing = false
            appState.isProcessingLLM = false
            appState.silenceWarningActive = false
            appState.isModelSelecting = false
            appState.isToneSelecting = true
            NotchManager.shared.showToneSelector()

        case .error(let error):
            appState.isRecording = false
            appState.isWarmingUp = false
            appState.isTranscribing = false
            appState.isProcessingLLM = false
            appState.lastError = error.localizedDescription
            appState.silenceWarningActive = false
            appState.isModelSelecting = false
            appState.isToneSelecting = false
            NotchManager.shared.showError(error.localizedDescription)
        }

        onStateChange?(newState)
    }
}
