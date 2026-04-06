//
//  NotchViewModel.swift
//  VoxNotch
//
//  Derives display state from AppState + NotchManager for the notch UI.
//  Eliminates duplicated displayPhase logic across CompactLeadingView,
//  CompactTrailingView, and NotchExpandedFallbackView.
//

import Foundation

/// Unified display phase for the notch UI — single source of truth
/// for what the notch should be showing at any moment.
enum NotchDisplayPhase: Equatable {
    case idle
    case recording
    case warmingUp
    case transcribing
    case processingLLM
    case downloading
    case modelsNeeded
    case error
    case outputInserted
    case outputClipboard
    case outputClipboardAborted
    case confirmation
    case modelSelecting
    case toneSelecting
}

/// View model for the notch UI. Reads AppState + NotchManager and exposes
/// simple, view-ready properties. Testable without SwiftUI.
@MainActor @Observable
final class NotchViewModel {

    private let appState: AppState
    private let notchManager: NotchManager
    private let audioViz: AudioVisualizationState

    init(
        appState: AppState = .shared,
        notchManager: NotchManager = .shared,
        audioViz: AudioVisualizationState = .shared
    ) {
        self.appState = appState
        self.notchManager = notchManager
        self.audioViz = audioViz
    }

    // MARK: - Display Phase

    var displayPhase: NotchDisplayPhase {
        switch appState.dictationPhase {
        case .modelSelecting: return .modelSelecting
        case .toneSelecting:  return .toneSelecting
        case .recording:      return .recording
        case .warmingUp:      return .warmingUp
        case .transcribing:   return .transcribing
        case .processingLLM:  return .processingLLM
        case .outputting, .error, .idle:
            break
        }
        if appState.modelDownload.isDownloadingModel { return .downloading }
        if appState.modelDownload.modelsNeeded       { return .modelsNeeded }
        if appState.error.lastError != nil           { return .error }
        if let output = notchManager.outputNotification {
            switch output {
            case .inserted:        return .outputInserted
            case .clipboard:       return .outputClipboard
            case .clipboardAborted: return .outputClipboardAborted
            }
        }
        if notchManager.isShowingConfirmation { return .confirmation }
        return .idle
    }

    // MARK: - View-Ready Properties

    var audioLevel: Float { audioViz.audioLevel }
    var recordingDuration: TimeInterval { appState.recordingDuration }
    var downloadProgress: Double { appState.modelDownload.modelDownloadProgress }
    var modelsNeededMessage: String { appState.modelDownload.modelsNeededMessage }
    var errorMessage: String? { appState.error.lastError }
    var errorRecovery: String? { appState.error.lastErrorRecovery }
    var canRetry: Bool { appState.error.canRetryTranscription }
    var confirmationMessage: String { notchManager.confirmationMessage }
    var llmWarning: String? { appState.error.llmWarning }
    var hasLLMWarning: Bool { appState.error.llmWarning != nil }

    // MARK: - Model Selection

    var modelSelectionName: String? {
        let candidates = appState.modelSelection.candidates
        let index = appState.modelSelection.index
        if index < candidates.count { return candidates[index].displayName }
        return nil
    }
    var isModelSelectionOverflow: Bool {
        appState.modelSelection.index >= appState.modelSelection.candidates.count
    }
    var modelSelectionIndex: Int { appState.modelSelection.index }

    // MARK: - Tone Selection

    var toneSelectionName: String? {
        let candidates = appState.toneSelection.candidates
        let index = appState.toneSelection.index
        if index < candidates.count { return candidates[index].displayName }
        return nil
    }
    var isToneSelectionOverflow: Bool {
        appState.toneSelection.index >= appState.toneSelection.candidates.count
    }
    var toneSelectionIndex: Int { appState.toneSelection.index }

    // MARK: - Status Text (trailing view)

    var statusText: String {
        switch displayPhase {
        case .recording:      return formatDuration(recordingDuration)
        case .warmingUp:      return "Warming up..."
        case .transcribing:   return "Transcribing..."
        case .processingLLM:  return "Processing..."
        case .downloading:    return "\(Int(downloadProgress * 100))%"
        case .modelsNeeded:   return modelsNeededMessage
        case .error:          return errorMessage ?? "Error"
        case .outputInserted:
            return hasLLMWarning ? "Inserted (no tone)" : "Text inserted"
        case .outputClipboard:
            return hasLLMWarning ? "Copied (no tone)" : "Copied — ⌘V to paste"
        case .outputClipboardAborted:
            return hasLLMWarning ? "Clipboard (no tone)" : "App switched — ⌘V to paste"
        case .confirmation:   return confirmationMessage
        case .modelSelecting: return modelSelectionName ?? "More Models..."
        case .toneSelecting:  return toneSelectionName ?? "More Tones..."
        case .idle:           return "VoxNotch"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
