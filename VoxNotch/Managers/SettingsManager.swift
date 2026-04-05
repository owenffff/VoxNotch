//
//  SettingsManager.swift
//  VoxNotch
//
//  Centralized settings management with UserDefaults persistence
//

import Foundation
import os.log

// MARK: - Notification Names

extension Notification.Name {
  static let hotkeyConfigurationChanged = Notification.Name("hotkeyConfigurationChanged")
  static let settingsNavigateTo = Notification.Name("settingsNavigateTo")
  static let hideFromScreenRecordingChanged = Notification.Name("hideFromScreenRecordingChanged")
}

/// Manages all user settings with automatic persistence
@Observable
final class SettingsManager {

  // MARK: - Singleton

  static let shared = SettingsManager()

  private let logger = Logger(subsystem: "com.voxnotch", category: "SettingsManager")

  // MARK: - Settings Keys

  private enum Keys {
    static let settingsVersion = "settingsVersion"

    /// General
    static let launchAtLogin = "launchAtLogin"
    static let useEscToCancel = "useEscToCancel"
    static let hideFromScreenRecording = "hideFromScreenRecording"

    /// Hotkey
    static let hotkeyModifiers = "hotkeyModifiers"
    static let hotkeyModifierFlags = "hotkeyModifierFlags"
    static let holdToRecord = "holdToRecord"
    static let minimumRecordingDuration = "minimumRecordingDuration"

    /// Model
    static let selectedModel = "selectedModel"
    static let transcriptionLanguage = "transcriptionLanguage"

    /// Output
    static let restoreClipboard = "restoreClipboard"
    static let addSpaceAfterTranscription = "addSpaceAfterTranscription"
    static let removeFillerWords = "removeFillerWords"
    static let applyITN = "applyITN"
    static let useClipboardForOutput = "useClipboardForOutput"
    /// LLM
    static let enablePostProcessing = "enablePostProcessing"
    static let llmProvider = "llmProvider"
    static let llmEndpointURL = "llmEndpointURL"
    static let llmModel = "llmModel"
    static let promptTemplate = "promptTemplate"
    static let customPrompt = "customPrompt"

    /// OpenAI API (for STT fallback and LLM)
    static let openAIAPIKey = "openAIAPIKey"
    static let openAIBaseURL = "openAIBaseURL"

    /// STT Provider
    static let sttProvider = "sttProvider"

    /// Silence Detection
    static let enableAutoStopOnSilence = "enableAutoStopOnSilence"
    static let silenceThresholdDB = "silenceThresholdDB"
    static let silenceDurationSeconds = "silenceDurationSeconds"

    /// Microphone Selection
    static let selectedMicrophoneDeviceID = "selectedMicrophoneDeviceID"

    /// ASR Engine
    static let asrEngine = "asrEngine"
    static let mlxAudioModel = "mlxAudioModel"

    /// Unified Speech Model
    static let speechModel = "speechModel"

    /// Pinned model IDs for quick-switch cycling (hotkey + left/right)
    static let pinnedModelIDs = "pinnedModelIDs"

    /// Active tone ID for post-processing
    static let activeToneID = "activeToneID"

    /// Pinned tone IDs for quick-switch cycling (hotkey + up/down)
    static let pinnedToneIDs = "pinnedToneIDs"

    /// FluidAudio Settings
    static let fluidAudioModel = "fluidAudioModel"

    /// Sound Feedback
    static let successSoundEnabled = "successSoundEnabled"
    static let customSuccessSoundPath = "customSuccessSoundPath"

    /// History
    static let historyEnabled = "historyEnabled"
    static let historyRetentionDays = "historyRetentionDays"
    static let saveAudioRecordings = "saveAudioRecordings"

    /// Onboarding
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let onboardingPermissionsState = "onboardingPermissionsState"
    static let onboardingModelState = "onboardingModelState"
    static let onboardingTutorialState = "onboardingTutorialState"
  }

  /// Current settings version for migrations
  private static let currentVersion = 1

  // MARK: - General Settings

  var hideFromScreenRecording: Bool {
    didSet {
      save(hideFromScreenRecording, forKey: Keys.hideFromScreenRecording)
      NotificationCenter.default.post(name: .hideFromScreenRecordingChanged, object: nil)
    }
  }

  var launchAtLogin: Bool {
    didSet { save(launchAtLogin, forKey: Keys.launchAtLogin) }
  }

  var useEscToCancel: Bool {
    didSet { save(useEscToCancel, forKey: Keys.useEscToCancel) }
  }

  // MARK: - Hotkey Settings

  var hotkeyModifiers: String {
    didSet { save(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
  }

  /// Raw modifier flags stored as UInt64
  var hotkeyModifierFlags: UInt64 {
    didSet {
      save(hotkeyModifierFlags, forKey: Keys.hotkeyModifierFlags)
      /// Notify HotkeyManager to update
      NotificationCenter.default.post(name: .hotkeyConfigurationChanged, object: nil)
    }
  }

  var holdToRecord: Bool {
    didSet { save(holdToRecord, forKey: Keys.holdToRecord) }
  }

  var minimumRecordingDuration: Double {
    didSet { save(minimumRecordingDuration, forKey: Keys.minimumRecordingDuration) }
  }

  // MARK: - Hotkey Helper Methods

  /// Update hotkey configuration from modifier flags
  func updateHotkey(modifierFlags: UInt64, displayString: String) {
    self.hotkeyModifierFlags = modifierFlags
    self.hotkeyModifiers = displayString
  }

  // MARK: - Model Settings

  var selectedModel: String {
    didSet { save(selectedModel, forKey: Keys.selectedModel) }
  }

  var transcriptionLanguage: String {
    didSet { save(transcriptionLanguage, forKey: Keys.transcriptionLanguage) }
  }

  // MARK: - Output Settings

  var restoreClipboard: Bool {
    didSet { save(restoreClipboard, forKey: Keys.restoreClipboard) }
  }

  var addSpaceAfterTranscription: Bool {
    didSet { save(addSpaceAfterTranscription, forKey: Keys.addSpaceAfterTranscription) }
  }

  var useClipboardForOutput: Bool {
    didSet { save(useClipboardForOutput, forKey: Keys.useClipboardForOutput) }
  }

  var removeFillerWords: Bool {
    didSet { save(removeFillerWords, forKey: Keys.removeFillerWords) }
  }

  var applyITN: Bool {
    didSet { save(applyITN, forKey: Keys.applyITN) }
  }

  // MARK: - LLM Settings

  /// Derived from activeToneID: selecting "No Processing" disables post-processing
  var enablePostProcessing: Bool { activeToneID != "none" }

  var llmProvider: String {
    didSet { save(llmProvider, forKey: Keys.llmProvider) }
  }

  var llmEndpointURL: String {
    didSet { save(llmEndpointURL, forKey: Keys.llmEndpointURL) }
  }

  var llmModel: String {
    didSet { save(llmModel, forKey: Keys.llmModel) }
  }

  var promptTemplate: String {
    didSet {
      save(promptTemplate, forKey: Keys.promptTemplate)
      /// Update customPrompt when template changes (unless custom)
      if promptTemplate != "custom" {
        customPrompt = PromptTemplate(rawValue: promptTemplate)?.prompt ?? PromptTemplate.formal.prompt
      }
    }
  }

  var customPrompt: String {
    didSet { save(customPrompt, forKey: Keys.customPrompt) }
  }

  // MARK: - OpenAI API Settings

  /// OpenAI API key (stored in Keychain via KeychainManager)
  /// Returns nil if no key is configured
  var openAIAPIKey: String? {
    get {
      KeychainManager.shared.getAPIKey(for: .openAI)
    }
    set {
      if let key = newValue, !key.isEmpty {
        do {
          try KeychainManager.shared.saveAPIKey(key, for: .openAI)
        } catch {
          logger.error("Failed to save OpenAI API key to Keychain: \(error.localizedDescription)")
        }
      } else {
        do {
          try KeychainManager.shared.deleteAPIKey(for: .openAI)
        } catch {
          logger.error("Failed to delete OpenAI API key from Keychain: \(error.localizedDescription)")
        }
      }
    }
  }

  /// OpenAI-compatible API base URL (for custom endpoints)
  var openAIBaseURL: URL? {
    get {
      guard let urlString = UserDefaults.standard.string(forKey: Keys.openAIBaseURL),
            !urlString.isEmpty
      else {
        return nil
      }
      return URL(string: urlString)
    }
    set {
      save(newValue?.absoluteString ?? "", forKey: Keys.openAIBaseURL)
    }
  }

  // MARK: - STT Provider Settings

  /// Selected STT provider: "apple" or "openai"
  var sttProvider: String {
    didSet { save(sttProvider, forKey: Keys.sttProvider) }
  }

  // MARK: - Silence Detection Settings

  /// Whether to auto-stop recording after extended silence
  var enableAutoStopOnSilence: Bool {
    didSet { save(enableAutoStopOnSilence, forKey: Keys.enableAutoStopOnSilence) }
  }

  /// Silence threshold in decibels (e.g., -50 dB)
  /// Audio below this level is considered silence
  var silenceThresholdDB: Double {
    didSet { save(silenceThresholdDB, forKey: Keys.silenceThresholdDB) }
  }

  /// Duration of continuous silence before auto-stop (in seconds)
  var silenceDurationSeconds: Double {
    didSet { save(silenceDurationSeconds, forKey: Keys.silenceDurationSeconds) }
  }

  // MARK: - Microphone Selection

  /// Persisted audio device ID for microphone selection. 0 = system default.
  var selectedMicrophoneDeviceID: UInt32 {
    didSet { save(selectedMicrophoneDeviceID, forKey: Keys.selectedMicrophoneDeviceID) }
  }

  // MARK: - Tone Settings

  /// The currently active tone ID (maps to a ToneTemplate in ToneRegistry)
  var activeToneID: String {
    didSet { save(activeToneID, forKey: Keys.activeToneID) }
  }

  /// IDs of tones pinned to the hotkey quick-switch (hotkey + up/down)
  var pinnedToneIDs: [String] {
    didSet { save(pinnedToneIDs, forKey: Keys.pinnedToneIDs) }
  }

  /// Get the effective prompt using ToneRegistry (falls back to legacy promptTemplate/customPrompt)
  var effectivePrompt: String {
    if let tone = ToneRegistry.shared.tone(forID: activeToneID) {
      return tone.prompt
    }
    // Fallback to legacy behaviour during first launch before ToneRegistry is seeded
    if promptTemplate == "custom" {
      return customPrompt
    }
    return PromptTemplate(rawValue: promptTemplate)?.prompt ?? customPrompt
  }

  // MARK: - ASR Engine Settings

  /// Selected ASR engine: "fluidAudio" or "mlxAudio"
  var asrEngine: String {
    didSet { save(asrEngine, forKey: Keys.asrEngine) }
  }

  /// Unified speech model selection
  var speechModel: String {
    didSet {
      save(speechModel, forKey: Keys.speechModel)
      // Auto-sync engine and model version based on unified model
      if let model = SpeechModel(rawValue: speechModel) {
        asrEngine = model.engine.rawValue
        // Also sync the specific model version
        switch model {
        case .parakeetV2:
          fluidAudioModel = "v2"
        case .parakeetV3:
          fluidAudioModel = "v3"
        case .glmAsrNano:
          mlxAudioModel = MLXAudioModelVersion.glmAsrNano.rawValue
        case .qwen3Asr:
          mlxAudioModel = MLXAudioModelVersion.qwen3Asr.rawValue
        }
      } else {
        // Custom model — always uses the MLX Audio engine
        asrEngine = ASREngine.mlxAudio.rawValue
      }
    }
  }

  /// IDs of models pinned to the hotkey quick-switch (max 3).
  /// Defaults to first 3 built-in models on first launch.
  var pinnedModelIDs: [String] {
    didSet { save(pinnedModelIDs, forKey: Keys.pinnedModelIDs) }
  }

  /// Selected MLX Audio model version
  var mlxAudioModel: String {
    didSet { save(mlxAudioModel, forKey: Keys.mlxAudioModel) }
  }

  // MARK: - FluidAudio Settings

  /// Selected FluidAudio model version: "v2" (English) or "v3" (Multilingual)
  var fluidAudioModel: String {
    didSet { save(fluidAudioModel, forKey: Keys.fluidAudioModel) }
  }

  // MARK: - Sound Feedback Settings

  /// Whether to play a sound on successful dictation output
  var successSoundEnabled: Bool {
    didSet { save(successSoundEnabled, forKey: Keys.successSoundEnabled) }
  }

  /// Path to a custom success sound file (empty = use default system sound)
  var customSuccessSoundPath: String {
    didSet { save(customSuccessSoundPath, forKey: Keys.customSuccessSoundPath) }
  }

  // MARK: - History Settings

  /// Whether to save transcriptions to history
  var historyEnabled: Bool {
    didSet { save(historyEnabled, forKey: Keys.historyEnabled) }
  }

  /// Number of days to retain history (0 = keep forever)
  var historyRetentionDays: Int {
    didSet { save(historyRetentionDays, forKey: Keys.historyRetentionDays) }
  }

  /// Whether to save audio recordings alongside transcriptions
  var saveAudioRecordings: Bool {
    didSet { save(saveAudioRecordings, forKey: Keys.saveAudioRecordings) }
  }

  // MARK: - Onboarding Settings

  /// Whether the first-run wizard has been completed
  var hasCompletedOnboarding: Bool {
    get { UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding) }
    set { UserDefaults.standard.set(newValue, forKey: Keys.hasCompletedOnboarding) }
  }

  /// Per-step onboarding state (pending / completed / skipped)
  var onboardingPermissionsState: OnboardingStepState {
    get { OnboardingStepState(rawValue: UserDefaults.standard.string(forKey: Keys.onboardingPermissionsState) ?? "") ?? .pending }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.onboardingPermissionsState) }
  }

  var onboardingModelState: OnboardingStepState {
    get { OnboardingStepState(rawValue: UserDefaults.standard.string(forKey: Keys.onboardingModelState) ?? "") ?? .pending }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.onboardingModelState) }
  }

  var onboardingTutorialState: OnboardingStepState {
    get { OnboardingStepState(rawValue: UserDefaults.standard.string(forKey: Keys.onboardingTutorialState) ?? "") ?? .pending }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.onboardingTutorialState) }
  }

  // MARK: - Initialization

  private init() {
    /// Load all settings from UserDefaults
    let defaults = UserDefaults.standard

    /// General
    self.hideFromScreenRecording = defaults.object(forKey: Keys.hideFromScreenRecording) as? Bool ?? true
    self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    self.useEscToCancel = defaults.object(forKey: Keys.useEscToCancel) as? Bool ?? false

    /// Hotkey
    self.hotkeyModifiers = defaults.string(forKey: Keys.hotkeyModifiers) ?? "⌃⌥"
    /// Default: Control + Option (0x40000 | 0x80000 = 0xC0000)
    self.hotkeyModifierFlags = defaults.object(forKey: Keys.hotkeyModifierFlags) as? UInt64 ?? 0xC0000
    self.holdToRecord = defaults.object(forKey: Keys.holdToRecord) as? Bool ?? true
    self.minimumRecordingDuration = defaults.object(forKey: Keys.minimumRecordingDuration) as? Double ?? 0.2

    /// Model
    self.selectedModel = defaults.string(forKey: Keys.selectedModel) ?? "whisper-base"
    self.transcriptionLanguage = defaults.string(forKey: Keys.transcriptionLanguage) ?? "auto"

    /// Output
    self.restoreClipboard = defaults.object(forKey: Keys.restoreClipboard) as? Bool ?? true
    self.addSpaceAfterTranscription = defaults.object(forKey: Keys.addSpaceAfterTranscription) as? Bool ?? true
    self.removeFillerWords = defaults.object(forKey: Keys.removeFillerWords) as? Bool ?? false
    self.applyITN = defaults.object(forKey: Keys.applyITN) as? Bool ?? true
    self.useClipboardForOutput = defaults.object(forKey: Keys.useClipboardForOutput) as? Bool ?? true
    /// LLM
    self.llmProvider = defaults.string(forKey: Keys.llmProvider) ?? "local"
    self.llmEndpointURL = defaults.string(forKey: Keys.llmEndpointURL) ?? "http://localhost:11434"
    self.llmModel = defaults.string(forKey: Keys.llmModel) ?? "llama3.2"
    self.promptTemplate = defaults.string(forKey: Keys.promptTemplate) ?? "formal"
    self.customPrompt = defaults.string(forKey: Keys.customPrompt) ?? PromptTemplate.formal.prompt

    /// STT Provider (default to Apple if available, otherwise OpenAI)
    self.sttProvider = defaults.string(forKey: Keys.sttProvider) ?? "apple"

    /// Silence Detection
    self.enableAutoStopOnSilence = defaults.bool(forKey: Keys.enableAutoStopOnSilence)
    self.silenceThresholdDB = defaults.object(forKey: Keys.silenceThresholdDB) as? Double ?? -50.0
    self.silenceDurationSeconds = defaults.object(forKey: Keys.silenceDurationSeconds) as? Double ?? 3.0

    /// Microphone Selection (0 = system default)
    self.selectedMicrophoneDeviceID = defaults.object(forKey: Keys.selectedMicrophoneDeviceID) as? UInt32 ?? 0

    /// ASR Engine Settings
    self.asrEngine = defaults.string(forKey: Keys.asrEngine) ?? "fluidAudio"
    self.mlxAudioModel = defaults.string(forKey: Keys.mlxAudioModel) ?? MLXAudioModelVersion.glmAsrNano.rawValue
    self.speechModel = defaults.string(forKey: Keys.speechModel) ?? SpeechModel.defaultModel.rawValue
    self.pinnedModelIDs = defaults.stringArray(forKey: Keys.pinnedModelIDs)
      ?? Array(SpeechModel.allCases.prefix(3)).map(\.rawValue)

    /// Tone Settings
    self.activeToneID = defaults.string(forKey: Keys.activeToneID) ?? Self.migratedToneID(defaults: defaults)
    /// Migration: existing users who had enablePostProcessing=false get mapped to the "none" tone
    if defaults.object(forKey: Keys.activeToneID) == nil,
       defaults.object(forKey: Keys.enablePostProcessing) != nil,
       !defaults.bool(forKey: Keys.enablePostProcessing)
    {
      self.activeToneID = "none"
    }
    self.pinnedToneIDs = (defaults.stringArray(forKey: Keys.pinnedToneIDs)
      ?? ["formal", "casual"]).filter { $0 != "none" }

    /// FluidAudio Settings
    self.fluidAudioModel = defaults.string(forKey: Keys.fluidAudioModel) ?? "v2"

    /// Sound Feedback
    self.successSoundEnabled = defaults.object(forKey: Keys.successSoundEnabled) as? Bool ?? true
    self.customSuccessSoundPath = defaults.string(forKey: Keys.customSuccessSoundPath) ?? ""

    /// History
    self.historyEnabled = defaults.object(forKey: Keys.historyEnabled) as? Bool ?? true
    self.historyRetentionDays = defaults.object(forKey: Keys.historyRetentionDays) as? Int ?? 0
    self.saveAudioRecordings = defaults.object(forKey: Keys.saveAudioRecordings) as? Bool ?? false

    /// Run migrations if needed
    runMigrations()
  }

  // MARK: - Migration Helpers

  /// Derive activeToneID from the legacy promptTemplate key on first upgrade
  private static func migratedToneID(defaults: UserDefaults) -> String {
    let oldTemplate = defaults.string(forKey: "promptTemplate") ?? "none"
    // "custom" case is handled by ToneRegistry.migrateCustomTone() -> writes activeToneID directly
    if oldTemplate == "custom" { return "none" }
    // Map removed built-in tones to "none"
    let removedTones: Set<String> = ["cleanup", "punctuation", "filler-removal"]
    if removedTones.contains(oldTemplate) { return "none" }
    return oldTemplate
  }

  // MARK: - Persistence Helpers

  private func save(_ value: Any, forKey key: String) {
    UserDefaults.standard.set(value, forKey: key)
  }

  // MARK: - Migrations

  private func runMigrations() {
    let defaults = UserDefaults.standard
    let storedVersion = defaults.integer(forKey: Keys.settingsVersion)

    if storedVersion < Self.currentVersion {
      defaults.set(Self.currentVersion, forKey: Keys.settingsVersion)
    }
  }

  // MARK: - Reset

  /// Reset all settings to defaults
  func resetToDefaults() {
    let defaults = UserDefaults.standard
    let allKeys = [
      Keys.launchAtLogin, Keys.useEscToCancel,
      Keys.hotkeyModifiers, Keys.hotkeyModifierFlags, Keys.holdToRecord, Keys.minimumRecordingDuration,
      Keys.selectedModel, Keys.transcriptionLanguage,
      Keys.addSpaceAfterTranscription, Keys.removeFillerWords, Keys.applyITN,
      Keys.restoreClipboard, Keys.useClipboardForOutput,
      Keys.llmProvider, Keys.llmEndpointURL, Keys.llmModel,
      Keys.promptTemplate, Keys.customPrompt,
      Keys.openAIBaseURL, Keys.sttProvider,
      Keys.enableAutoStopOnSilence, Keys.silenceThresholdDB, Keys.silenceDurationSeconds,
      Keys.selectedMicrophoneDeviceID,
      Keys.asrEngine, Keys.mlxAudioModel, Keys.speechModel,
      Keys.fluidAudioModel,
      Keys.activeToneID, Keys.pinnedToneIDs,
      Keys.historyEnabled, Keys.historyRetentionDays, Keys.saveAudioRecordings,
      Keys.successSoundEnabled, Keys.customSuccessSoundPath
    ]

    for key in allKeys {
      defaults.removeObject(forKey: key)
    }

    /// Reload defaults
    launchAtLogin = false
    useEscToCancel = false
    hotkeyModifiers = "⌃⌥"
    hotkeyModifierFlags = 0xC0000
    holdToRecord = true
    minimumRecordingDuration = 0.2
    selectedModel = "whisper-base"
    transcriptionLanguage = "auto"
    restoreClipboard = true
    addSpaceAfterTranscription = true
    removeFillerWords = false
    applyITN = true
    useClipboardForOutput = true
    llmProvider = "local"
    llmEndpointURL = "http://localhost:11434"
    llmModel = "llama3.2"
    promptTemplate = "formal"
    customPrompt = PromptTemplate.formal.prompt
    sttProvider = "apple"
    openAIAPIKey = nil
    openAIBaseURL = nil
    enableAutoStopOnSilence = false
    silenceThresholdDB = -50.0
    silenceDurationSeconds = 3.0
    selectedMicrophoneDeviceID = 0
    asrEngine = "fluidAudio"
    mlxAudioModel = MLXAudioModelVersion.glmAsrNano.rawValue
    speechModel = SpeechModel.defaultModel.rawValue
    pinnedModelIDs = Array(SpeechModel.allCases.prefix(3)).map(\.rawValue)
    activeToneID = "none"
    pinnedToneIDs = ["formal", "casual"]
    fluidAudioModel = "v2"
    historyEnabled = true
    historyRetentionDays = 0
    saveAudioRecordings = false
    successSoundEnabled = true
    customSuccessSoundPath = ""
  }
}
