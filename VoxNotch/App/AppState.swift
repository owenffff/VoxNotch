//
//  AppState.swift
//  VoxNotch
//
//  Global application state using @Observable macro
//

import SwiftUI
import Observation

@Observable
final class AppState {

  // MARK: - Singleton

  static let shared = AppState()

  // MARK: - Recording State

  var isRecording: Bool = false
  var isTranscribing: Bool = false
  var isWarmingUp: Bool = false
  var isProcessingLLM: Bool = false
  var isDownloadingModel: Bool = false

  /// Model download progress (0.0 to 1.0)
  var modelDownloadProgress: Double = 0.0

  /// Whether speech model is ready for transcription
  var isModelReady: Bool = false

  /// Whether required models need to be downloaded
  var modelsNeeded: Bool = false

  /// Human-readable message about which models are missing
  var modelsNeededMessage: String = ""

  // MARK: - Current Transcription

  var currentTranscription: String = ""
  var lastError: String?
  var lastErrorRecovery: String?

  /// URL of the last recorded audio file (for retry)
  var lastAudioURL: URL?

  /// Whether transcription retry is available
  var canRetryTranscription: Bool {
    lastError != nil && lastAudioURL != nil
  }

  // MARK: - LLM Status

  /// Warning when LLM failed but transcription succeeded (non-blocking)
  var llmWarning: String?

  /// Whether LLM processing failed and retry is available
  var llmFailedWithRetry: Bool = false

  // MARK: - Output Routing

  /// Set to true when dictation output was sent to clipboard (no focused text field detected)
  var lastOutputWasClipboard: Bool = false

  // MARK: - Microphone State

  /// Whether no input microphone is detected
  var noMicrophoneDetected: Bool = false

  // MARK: - Audio Level (for visualizer)

  var audioLevel: Float = 0.0

  var audioFrequencyBands: [Float] = [Float](repeating: 0, count: 6)

  // MARK: - Silence Detection

  /// Indicates silence warning is active (about to auto-stop)
  var silenceWarningActive: Bool = false

  /// Current recording duration in seconds (updated by timer during recording)
  var recordingDuration: TimeInterval = 0

  // MARK: - Model Selection State

  /// Whether the user is cycling through models via hotkey + arrow keys
  var isModelSelecting: Bool = false

  /// The models shown in the cycling UI (populated on entry; includes custom models)
  var modelSelectionCandidates: [AnyModel] = []

  /// Current cycle index: 0...(candidates.count-1) = models, candidates.count = "More Models..."
  var modelSelectionIndex: Int = 0

  // MARK: - Tone Selection State

  /// Whether the user is cycling through tones via hotkey + up/down arrow keys
  var isToneSelecting: Bool = false

  /// The tones shown in the cycling UI (populated from pinned tone IDs on entry)
  var toneSelectionCandidates: [ToneTemplate] = []

  /// Current cycle index: 0...(candidates.count-1) = tones, candidates.count = "More Tones..."
  var toneSelectionIndex: Int = 0

  /// Deep-link target for Settings navigation (SettingsPanel.rawValue)
  var navigateToSettingsPanel: String? = nil

  // MARK: - Transient Notch States

  /// Set by NotchManager when a success animation should be shown, cleared on hide
  var isShowingSuccess = false

  /// Set by NotchManager when clipboard notification should be shown, cleared on hide
  var isShowingClipboard = false

  /// Brief confirmation shown after model/tone selection before auto-hide
  var isShowingConfirmation = false
  var confirmationMessage: String = ""

  // MARK: - Status

  enum AppStatus: String {
    case ready = "Ready"
    case recording = "Recording"
    case warmingUp = "Warming Up"
    case transcribing = "Transcribing"
    case downloading = "Downloading Model"
    case processing = "Processing"
    case modelsNeeded = "Models Needed"
    case error = "Error"
  }

  var status: AppStatus {
    if lastError != nil {
      return .error
    }
    if isDownloadingModel {
      return .downloading
    }
    if isProcessingLLM {
      return .processing
    }
    if isWarmingUp {
      return .warmingUp
    }
    if isTranscribing {
      return .transcribing
    }
    if isRecording {
      return .recording
    }
    if modelsNeeded {
      return .modelsNeeded
    }
    return .ready
  }

  // MARK: - Initialization

  private init() {}

  // MARK: - Methods

  func clearError() {
    lastError = nil
    lastErrorRecovery = nil
  }

  /// Set LLM warning (non-blocking, transcription still succeeded)
  func setLLMWarning(_ message: String, canRetry: Bool) {
    llmWarning = message
    llmFailedWithRetry = canRetry
  }

  /// Clear LLM warning
  func clearLLMWarning() {
    llmWarning = nil
    llmFailedWithRetry = false
  }

  func reset() {
    isRecording = false
    isTranscribing = false
    isWarmingUp = false
    isProcessingLLM = false
    isDownloadingModel = false
    modelDownloadProgress = 0.0
    isModelReady = false
    modelsNeeded = false
    modelsNeededMessage = ""
    currentTranscription = ""
    lastError = nil
    lastErrorRecovery = nil
    lastAudioURL = nil
    llmWarning = nil
    llmFailedWithRetry = false
    lastOutputWasClipboard = false
    audioLevel = 0.0
    audioFrequencyBands = [Float](repeating: 0, count: 6)
    silenceWarningActive = false
    recordingDuration = 0
    noMicrophoneDetected = false
    isModelSelecting = false
    modelSelectionCandidates = []
    modelSelectionIndex = 0
    isToneSelecting = false
    toneSelectionCandidates = []
    toneSelectionIndex = 0
    navigateToSettingsPanel = nil
    isShowingSuccess = false
    isShowingClipboard = false
  }
}
