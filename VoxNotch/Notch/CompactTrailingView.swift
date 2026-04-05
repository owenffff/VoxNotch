//
//  CompactTrailingView.swift
//  VoxNotch
//
//  Right-side compact content for the notch UI
//

import SwiftUI

struct CompactTrailingView: View {

  private let appState = AppState.shared

  /// Single animation driver derived from AppState, avoiding
  /// competing `.animation()` modifiers.
  private var displayPhase: CompactPhase {
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
    if appState.isDownloadingModel { return .downloading }
    if appState.modelsNeeded       { return .modelsNeeded }
    if appState.lastError != nil   { return .error }
    if appState.isShowingSuccess   { return .success }
    if appState.isShowingClipboard { return .clipboard }
    return .idle
  }

  var body: some View {
    content
      .frame(height: 24)
      .animation(.smooth(duration: 0.4), value: displayPhase)
  }

  @ViewBuilder
  private var content: some View {
    if case .modelSelecting = appState.dictationPhase {
      modelName
    } else if case .toneSelecting = appState.dictationPhase {
      toneName
    } else if case .recording = appState.dictationPhase {
      durationTimer
    } else if case .warmingUp = appState.dictationPhase {
      statusText("Warming up...")
    } else if case .transcribing = appState.dictationPhase {
      statusText("Transcribing...")
    } else if case .processingLLM = appState.dictationPhase {
      statusText("Processing...")
    } else if appState.isDownloadingModel {
      percentageText
    } else if appState.modelsNeeded {
      statusText(appState.modelsNeededMessage)
    } else if let error = appState.lastError {
      statusText(error)
    } else if appState.isShowingSuccess {
      statusText("Text inserted")
    } else if appState.isShowingClipboard {
      statusText("Copied to clipboard")
    } else {
      statusText("VoxNotch")
    }
  }

  // MARK: - Duration Timer

  private var durationTimer: some View {
    Text(formatDuration(appState.recordingDuration))
      .font(.system(size: 12, design: .monospaced))
      .foregroundStyle(.secondary)
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
  }

  // MARK: - Status Text

  private func statusText(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 13))
      .foregroundStyle(.primary)
      .lineLimit(1)
  }

  // MARK: - Percentage

  private var percentageText: some View {
    Text("\(Int(appState.modelDownloadProgress * 100))%")
      .font(.system(size: 12, design: .monospaced))
      .foregroundStyle(.secondary)
  }

  // MARK: - Model Name

  private var modelName: some View {
    Group {
      let candidates = appState.modelSelectionCandidates
      let index = appState.modelSelectionIndex

      if index < candidates.count {
        Text(candidates[index].displayName)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.primary)
      } else {
        Text("More Models...")
          .font(.system(size: 13))
          .foregroundStyle(.purple)
      }
    }
  }

  // MARK: - Tone Name

  private var toneName: some View {
    Group {
      let candidates = appState.toneSelectionCandidates
      let index = appState.toneSelectionIndex

      if index < candidates.count {
        Text(candidates[index].displayName)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.primary)
      } else {
        Text("More Tones...")
          .font(.system(size: 13))
          .foregroundStyle(.purple)
      }
    }
  }
}

// MARK: - Compact Phase

private enum CompactPhase: Equatable {
  case idle, recording, warmingUp, transcribing, processingLLM
  case downloading, modelsNeeded, error, success, clipboard
  case modelSelecting, toneSelecting
}
