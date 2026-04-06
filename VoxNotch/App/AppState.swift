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

  let modelDownload: ModelReadinessState
  let modelSelection: ModelSelectionState
  let toneSelection: ToneSelectionState
  let error: ErrorState

  // MARK: - Dictation Phase

  /// Single source of truth for the dictation flow phase.
  var dictationPhase: DictationState = .idle

  // MARK: - Current Transcription

  var currentTranscription: String = ""

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

  private init() {
    self.modelDownload = .shared
    self.modelSelection = .shared
    self.toneSelection = .shared
    self.error = .shared
  }

  /// Test-only initializer for hermetic test isolation.
  /// Creates fresh sub-state instances that don't share state with production singletons.
  init(forTesting: Void) {
    self.modelDownload = ModelReadinessState(forTesting: ())
    self.modelSelection = ModelSelectionState(forTesting: ())
    self.toneSelection = ToneSelectionState(forTesting: ())
    self.error = ErrorState(forTesting: ())
  }

  // MARK: - Methods

  func clearError() {
    error.clear()
  }

  func reset() {
    dictationPhase = .idle
    modelDownload.reset()
    currentTranscription = ""
    error.reset()
    lastOutputResult = nil
    silenceWarningActive = false
    recordingDuration = 0
    noMicrophoneDetected = false
    modelSelection.reset()
    toneSelection.reset()
    navigateToSettingsPanel = nil
  }

}
