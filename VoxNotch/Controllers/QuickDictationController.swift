//
//  QuickDictationController.swift
//  VoxNotch
//
//  Thin wiring layer: hotkey events → DictationStateMachine,
//  state changes → AppState / NotchManager side effects.
//

import AppKit
import Foundation
import os.log
import SwiftUI

/// Controller for Quick Dictation mode (hold-to-record, release to transcribe)
@MainActor
final class QuickDictationController {

    private let logger = Logger(subsystem: "com.voxnotch", category: "QuickDictationController")

    // MARK: - Types

    /// Callback for state changes
    typealias StateCallback = (DictationState) -> Void

    // MARK: - Properties

    static let shared = QuickDictationController()

    /// The state machine that owns the dictation state, session ID, timers, and pipeline.
    let stateMachine: DictationStateMachine

    /// Callback for state changes
    var onStateChange: StateCallback?

    /// Whether dictation is currently active
    var isActive: Bool { stateMachine.state.isActive }

    /// Current dictation state (read-only, delegates to state machine)
    var state: DictationState { stateMachine.state }

    // Dependencies
    private let hotkeyManager: HotkeyManager
    private let audioManager: AudioRecording
    private let appState: AppState

    /// The frontmost application when the user pressed the hotkey.
    /// Captured before the notch panel appears so AX queries target the correct app.
    private var savedFrontmostApp: NSRunningApplication?

    /// Cooldown after a cancel before accepting a new recording (prevents frame drops on rapid presses)
    private let cancelCooldown: TimeInterval = 0.3

    // MARK: - Initialization

    init(
        hotkeyManager: HotkeyManager = .shared,
        audioManager: AudioRecording = AudioCaptureManager.shared,
        textOutputManager: TextOutputting = TextOutputManager.shared,
        transcriptionEngine: TranscriptionEngine = TranscriptionService.shared,
        llmProcessor: LLMProcessing = LLMService.shared,
        appState: AppState = .shared
    ) {
        self.hotkeyManager = hotkeyManager
        self.audioManager = audioManager
        self.appState = appState

        // State machine owns the pipeline dependencies
        self.stateMachine = DictationStateMachine(
            audioManager: audioManager,
            transcriptionEngine: transcriptionEngine,
            llmProcessor: llmProcessor,
            textOutputManager: textOutputManager
        )

        stateMachine.delegate = self

        // Wire state machine callbacks
        stateMachine.onRecordingDurationTick = { [weak self] elapsed in
            self?.appState.recordingDuration = elapsed
        }
        stateMachine.onWatchdogFired = { [weak self] in
            print("QuickDictationController: Watchdog triggered - force resetting stuck recording state")
            self?.cancelCurrentSession()
        }
        stateMachine.onPipelineOutputSuccess = { [weak self] wasClipboard in
            self?.appState.lastAudioURL = nil
            self?.appState.lastOutputWasClipboard = wasClipboard
            if wasClipboard {
                NotchManager.shared.showClipboard()
            } else {
                NotchManager.shared.showSuccess()
            }
            SoundManager.shared.playSuccessSound()
        }
        stateMachine.onPipelineCancelled = {
            NotchManager.shared.hide()
        }
        stateMachine.onLLMWarning = { [weak self] message in
            self?.appState.setLLMWarning(message, canRetry: false)
        }
        stateMachine.onPipelineErrorWithAudio = { [weak self] audioURL in
            self?.appState.lastAudioURL = audioURL
        }

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
                if case .modelSelecting = self?.stateMachine.state {
                    print("QuickDictationController: Confirming model selection...")
                    self?.confirmModelSelection()
                } else if case .toneSelecting = self?.stateMachine.state {
                    print("QuickDictationController: Confirming tone selection...")
                    self?.confirmToneSelection()
                } else {
                    print("QuickDictationController: Stopping recording...")
                    self?.stateMachine.stopRecordingAndTranscribe(savedFrontmostApp: self?.savedFrontmostApp)
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
        audioManager.onSilenceWarning = { [weak self] in
            guard let self = self,
                  case .recording = self.stateMachine.state
            else { return }
            self.appState.silenceWarningActive = true
        }

        audioManager.onSilenceThresholdReached = { [weak self] in
            guard let self = self,
                  case .recording = self.stateMachine.state
            else { return }
            self.appState.silenceWarningActive = false
            self.stateMachine.stopRecordingAndTranscribe(savedFrontmostApp: self.savedFrontmostApp)
        }
    }

    /// Timer for retrying hotkey listener after permission is granted
    private var permissionCheckTimer: Timer?

    /// Start the Quick Dictation controller
    func start() {
        if !hotkeyManager.hasAccessibilityPermission {
            hotkeyManager.requestAccessibilityPermission()
        }
        if !audioManager.hasMicrophonePermission {
            audioManager.requestMicrophonePermission { _ in }
        }
        if hotkeyManager.startListening() {
            print("QuickDictationController: Hotkey listener started successfully")
        } else {
            print("QuickDictationController: Waiting for accessibility permission...")
            startPermissionCheck()
        }
    }

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
        stateMachine.cancelPipeline()
    }

    // MARK: - Click-to-Dictate

    func toggleDictation() {
        switch stateMachine.state {
        case .idle, .error, .modelSelecting, .toneSelecting:
            startRecording()
        case .recording:
            stateMachine.stopRecordingAndTranscribe(savedFrontmostApp: savedFrontmostApp)
        case .warmingUp, .transcribing, .processingLLM, .outputting:
            break
        }
    }

    // MARK: - Recording Flow (Pre-flight Checks Only)

    private func startRecording() {
        print("QuickDictationController: startRecording called, state: \(stateMachine.state)")

        if case .recording = stateMachine.state { return }

        // Cooldown after a recent cancel
        if let lastCancel = stateMachine.lastCancelTime,
           Date().timeIntervalSince(lastCancel) < cancelCooldown {
            print("QuickDictationController: Ignoring startRecording during cooldown")
            return
        }

        // Retry redirect
        if appState.canRetryTranscription {
            retryTranscription()
            return
        }

        // Clear stale transient flags
        appState.clearError()
        appState.lastAudioURL = nil
        appState.modelsNeeded = false
        appState.isShowingSuccess = false
        appState.isShowingClipboard = false
        appState.isShowingConfirmation = false

        // Cancel if busy
        if case .warmingUp = stateMachine.state {
            cancelCurrentSession()
        } else if case .transcribing = stateMachine.state {
            cancelCurrentSession()
        } else if case .processingLLM = stateMachine.state {
            cancelCurrentSession()
        } else if case .outputting = stateMachine.state {
            cancelCurrentSession()
        } else if case .error = stateMachine.state {
            cancelCurrentSession()
        }

        stateMachine.transition(to: .idle)

        // Model download pre-check
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
            let message: String
            if SettingsManager.shared.onboardingModelState == .skipped {
                message = "Download a speech model in Settings to start dictating"
            } else {
                message = "Not downloaded: \(modelDisplayName)"
            }
            withAnimation(.smooth(duration: 0.4)) {
                appState.modelsNeeded = true
                appState.modelsNeededMessage = message
            }
            NotchManager.shared.showModelsNeeded(appState.modelsNeededMessage)
            return
        }

        // Mic permission pre-check
        guard audioManager.hasMicrophonePermission else {
            print("QuickDictationController: No mic permission, requesting...")
            audioManager.requestMicrophonePermission { [weak self] granted in
                print("QuickDictationController: Mic permission result: \(granted)")
                if granted { self?.startRecording() }
            }
            return
        }

        print("QuickDictationController: Starting audio capture...")

        savedFrontmostApp = NSWorkspace.shared.frontmostApplication
        appState.recordingDuration = 0

        do {
            try stateMachine.beginRecording()
            print("QuickDictationController: Audio capture started")
        } catch {
            print("QuickDictationController: Failed to start audio capture: \(error)")
            stateMachine.transition(to: .error(error))
        }
    }

    // MARK: - Retry

    func retryTranscription() {
        guard let audioURL = appState.lastAudioURL else { return }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            appState.lastAudioURL = nil
            return
        }
        appState.lastError = nil
        appState.lastErrorRecovery = nil
        appState.lastAudioURL = nil
        stateMachine.retryTranscription(audioURL: audioURL, savedFrontmostApp: savedFrontmostApp)
    }

    // MARK: - Session Management

    private func stopRecordingQuietly() {
        savedFrontmostApp = nil
        appState.recordingDuration = 0
        stateMachine.stopRecordingQuietly()
    }

    private func cancelCurrentSession() {
        print("QuickDictationController: Cancelling current session")
        savedFrontmostApp = nil
        stateMachine.cancelPipeline()
        NotchManager.shared.hide()
    }

    // MARK: - Tone Selection

    private func handleToneSwitchRequest(direction: Int) {
        if case .modelSelecting = stateMachine.state { return }
        if case .recording = stateMachine.state {
            stopRecordingQuietly()
        }
        if case .toneSelecting = stateMachine.state {
            cycleToneSelection(direction: direction)
        } else {
            enterToneSelectionMode(direction: direction)
        }
    }

    private func getPinnedTones() -> [ToneTemplate] {
        let ids = SettingsManager.shared.pinnedToneIDs.isEmpty
            ? ["formal", "casual"]
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
        stateMachine.transition(to: .toneSelecting)
    }

    private func cycleToneSelection(direction: Int) {
        let total = appState.toneSelectionCandidates.count + 1
        let current = appState.toneSelectionIndex
        appState.toneSelectionIndex = ((current + direction) + total) % total
    }

    private func confirmToneSelection() {
        appState.modelsNeeded = false
        appState.isShowingSuccess = false
        appState.isShowingClipboard = false
        appState.isShowingConfirmation = false

        let index = appState.toneSelectionIndex
        let candidates = appState.toneSelectionCandidates

        if index >= candidates.count {
            appState.navigateToSettingsPanel = SettingsPanel.ai.rawValue
            SettingsWindowController.shared.showNavigatingToAIEnhancement()
            stateMachine.transition(to: .idle)
            NotchManager.shared.hide()
        } else {
            let selected = candidates[index]
            SettingsManager.shared.activeToneID = selected.id
            print("QuickDictationController: Tone switched to \(selected.displayName)")
            NotchManager.shared.showConfirmation(selected.displayName)
            stateMachine.transition(to: .idle)
        }
    }

    // MARK: - Model Selection

    private func handleModelSwitchRequest(direction: Int) {
        if case .toneSelecting = stateMachine.state { return }
        if case .recording = stateMachine.state {
            stopRecordingQuietly()
        }
        if case .modelSelecting = stateMachine.state {
            cycleModelSelection(direction: direction)
        } else {
            enterModelSelectionMode(direction: direction)
        }
    }

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
        stateMachine.transition(to: .modelSelecting)
    }

    private func cycleModelSelection(direction: Int) {
        let total = appState.modelSelectionCandidates.count + 1
        let current = appState.modelSelectionIndex
        appState.modelSelectionIndex = ((current + direction) + total) % total
    }

    private func confirmModelSelection() {
        appState.modelsNeeded = false
        appState.isShowingSuccess = false
        appState.isShowingClipboard = false
        appState.isShowingConfirmation = false

        let index = appState.modelSelectionIndex
        let candidates = appState.modelSelectionCandidates

        if index >= candidates.count {
            appState.navigateToSettingsPanel = SettingsPanel.speechModel.rawValue
            SettingsWindowController.shared.showNavigatingToSpeechModel()
            stateMachine.transition(to: .idle)
            NotchManager.shared.hide()
        } else {
            let selected = candidates[index]
            SettingsManager.shared.speechModel = selected.settingsID
            stateMachine.reconfigureTranscription()
            print("QuickDictationController: Model switched to \(selected.displayName)")

            if selected.isDownloaded {
                NotchManager.shared.showConfirmation(selected.displayName)
            } else {
                withAnimation(.smooth(duration: 0.4)) {
                    appState.modelsNeeded = true
                    appState.modelsNeededMessage = "Not downloaded: \(selected.displayName)"
                }
                NotchManager.shared.showModelsNeeded(appState.modelsNeededMessage)
            }
            stateMachine.transition(to: .idle)
        }
    }
}

// MARK: - DictationStateMachineDelegate

extension QuickDictationController: DictationStateMachineDelegate {

    func stateMachine(
        _ stateMachine: DictationStateMachine,
        didTransitionFrom oldState: DictationState,
        to newState: DictationState
    ) {
        // Reset recording duration when leaving recording
        if case .recording = newState {} else {
            appState.recordingDuration = 0
        }

        // Update app state — wrapped in withAnimation so dictationPhase
        // transitions in the notch get smooth crossfade.
        withAnimation(.smooth(duration: 0.4)) {
            appState.dictationPhase = newState
            appState.silenceWarningActive = false

            if case .error(let error) = newState {
                appState.lastError = error.localizedDescription
                appState.lastErrorRecovery = (error as? LocalizedError)?.recoverySuggestion
            }
        }

        // NotchManager calls outside withAnimation (they do their own async work)
        switch newState {
        case .recording:      NotchManager.shared.showRecording()
        case .warmingUp:      NotchManager.shared.showTranscribing()
        case .transcribing:   NotchManager.shared.showTranscribing()
        case .processingLLM:  NotchManager.shared.showProcessingLLM()
        case .modelSelecting: NotchManager.shared.showModelSelector()
        case .toneSelecting:  NotchManager.shared.showToneSelector()
        case .error(let e):   NotchManager.shared.showError(e.localizedDescription)
        default: break
        }

        onStateChange?(newState)
    }
}
