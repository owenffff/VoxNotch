//
//  CompactTrailingView.swift
//  VoxNotch
//
//  Right-side content for DynamicNotchKit compact mode
//

import SwiftUI

struct CompactTrailingView: View {

  private let appState = AppState.shared

  /// Single animation driver derived from AppState booleans, avoiding
  /// five competing `.animation()` modifiers.
  private var displayPhase: CompactPhase {
    if appState.isModelSelecting   { return .modelSelecting }
    if appState.isToneSelecting    { return .toneSelecting }
    if appState.isRecording        { return .recording }
    if appState.isWarmingUp        { return .warmingUp }
    if appState.isTranscribing     { return .transcribing }
    if appState.isProcessingLLM    { return .processingLLM }
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
      .animation(.smooth(duration: 0.35), value: displayPhase)
  }

  @ViewBuilder
  private var content: some View {
    if appState.isModelSelecting {
      modelName
    } else if appState.isToneSelecting {
      toneName
    } else if appState.isRecording {
      durationTimer
    } else if appState.isWarmingUp {
      statusText("Warming up...")
    } else if appState.isTranscribing {
      statusText("Transcribing...")
    } else if appState.isProcessingLLM {
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
