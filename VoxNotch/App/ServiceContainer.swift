//
//  ServiceContainer.swift
//  VoxNotch
//
//  Lightweight, compile-time-safe dependency container.
//  Production code uses `ServiceContainer.shared` (which wires up all real singletons).
//  Tests create a custom instance with mock overrides.
//

import Foundation

@MainActor
struct ServiceContainer {

    // MARK: - Pipeline Protocols (already abstracted)

    let audioRecording: AudioRecording
    let transcriptionEngine: TranscriptionEngine
    let llmProcessor: LLMProcessing
    let textOutputting: TextOutputting

    // MARK: - State

    let appState: AppState

    // MARK: - Managers

    let settings: SettingsManager
    let notchPresenter: NotchPresenting
    let soundManager: SoundManager
    let hotkeyManager: HotkeyManager
    let databaseManager: DatabaseManager

    // MARK: - Services

    let errorRouter: ErrorRouter
    let clock: AppClock

    // MARK: - Shared Instance

    static let shared = ServiceContainer()

    // MARK: - Init

    init(
        audioRecording: AudioRecording = AudioCaptureManager.shared,
        transcriptionEngine: TranscriptionEngine = TranscriptionService.shared,
        llmProcessor: LLMProcessing = LLMService.shared,
        textOutputting: TextOutputting = TextOutputManager.shared,
        appState: AppState = .shared,
        settings: SettingsManager = .shared,
        notchPresenter: NotchPresenting = NotchManager.shared,
        soundManager: SoundManager = .shared,
        hotkeyManager: HotkeyManager = .shared,
        databaseManager: DatabaseManager = .shared,
        errorRouter: ErrorRouter? = nil,
        clock: AppClock? = nil
    ) {
        self.audioRecording = audioRecording
        self.transcriptionEngine = transcriptionEngine
        self.llmProcessor = llmProcessor
        self.textOutputting = textOutputting
        self.appState = appState
        self.settings = settings
        self.notchPresenter = notchPresenter
        self.soundManager = soundManager
        self.hotkeyManager = hotkeyManager
        self.databaseManager = databaseManager
        self.errorRouter = errorRouter ?? ErrorRouter()
        self.clock = clock ?? SystemClock()
    }
}
