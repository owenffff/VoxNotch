//
//  CompactTrailingView.swift
//  VoxNotch
//
//  Right-side compact content for the notch UI
//

import SwiftUI

struct CompactTrailingView: View {

  @Environment(AppState.self) private var appState
  @Environment(NotchManager.self) private var notchManager

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
    if appState.modelDownload.isDownloadingModel { return .downloading }
    if appState.modelDownload.modelsNeeded       { return .modelsNeeded }
    if appState.error.lastError != nil           { return .error }
    if let output = notchManager.outputNotification {
      switch output {
      case .inserted:        return .success
      case .clipboard:       return .clipboard
      case .clipboardAborted: return .clipboardAborted
      }
    }
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
    } else if appState.modelDownload.isDownloadingModel {
      percentageText
    } else if appState.modelDownload.modelsNeeded {
      statusText(appState.modelDownload.modelsNeededMessage)
    } else if let error = appState.error.lastError {
      statusText(error)
    } else if let result = notchManager.outputNotification {
      switch result {
      case .inserted:
        statusText("Text inserted")
      case .clipboard:
        statusText("Copied — ⌘V to paste")
      case .clipboardAborted:
        statusText("App switched — ⌘V to paste")
      }
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
    Text("\(Int(appState.modelDownload.modelDownloadProgress * 100))%")
      .font(.system(size: 12, design: .monospaced))
      .foregroundStyle(.secondary)
  }

  // MARK: - Model Name

  private var modelName: some View {
    Group {
      let candidates = appState.modelSelection.candidates
      let index = appState.modelSelection.index

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
      let candidates = appState.toneSelection.candidates
      let index = appState.toneSelection.index

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
  case downloading, modelsNeeded, error, success, clipboard, clipboardAborted
  case modelSelecting, toneSelecting
}
