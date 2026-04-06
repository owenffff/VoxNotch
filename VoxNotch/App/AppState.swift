//
//  AppState.swift
//  VoxNotch
//
//  Global application state using @Observable macro.
//  Sub-states group related fields to reduce view invalidation scope.
//

import SwiftUI
import Observation

@MainActor @Observable
final class AppState {

  // MARK: - Singleton

  static let shared = AppState()

  // MARK: - Sub-States

  let modelDownload = ModelReadinessState.shared
  let modelSelection = ModelSelectionState.shared
  let toneSelection = ToneSelectionState.shared
  let error = ErrorState.shared

  // MARK: - Dictation Phase

  /// Single source of truth for the dictation flow phase.
  var dictationPhase: DictationState = .idle

  // MARK: - Current Transcription

  var currentTranscription: String = ""

  // MARK: - LLM Status

  /// Warning when LLM failed but transcription succeeded (non-blocking)
  var llmWarning: String?

  /// Whether LLM processing failed and retry is available
  var llmFailedWithRetry: Bool = false

  // MARK: - Output Routing

  /// How text was delivered in the most recent dictation output.
  var lastOutputResult: OutputResult? = nil

  // MARK: - Microphone State

  /// Whether no input microphone is detected
  var noMicrophoneDetected: Bool = false

  // MARK: - Silence Detection

  /// Indicates silence warning is active (about to auto-stop)
  var silenceWarningActive: Bool = false

  /// Current recording duration in seconds (updated by timer during recording)
  var recordingDuration: TimeInterval = 0

  /// Deep-link target for Settings navigation (SettingsPanel.rawValue)
  var navigateToSettingsPanel: String? = nil

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
    if error.lastError != nil { return .error }
    if modelDownload.isDownloadingModel { return .downloading }
    switch dictationPhase {
    case .processingLLM:  return .processing
    case .warmingUp:      return .warmingUp
    case .transcribing:   return .transcribing
    case .recording:      return .recording
    default:              break
    }
    if modelDownload.modelsNeeded { return .modelsNeeded }
    return .ready
  }

  // MARK: - Initialization

  private init() {}

  // MARK: - Methods

  func clearError() {
    error.clear()
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
    dictationPhase = .idle
    modelDownload.reset()
    currentTranscription = ""
    error.reset()
    llmWarning = nil
    llmFailedWithRetry = false
    lastOutputResult = nil
    silenceWarningActive = false
    recordingDuration = 0
    noMicrophoneDetected = false
    modelSelection.reset()
    toneSelection.reset()
    navigateToSettingsPanel = nil
  }

}
