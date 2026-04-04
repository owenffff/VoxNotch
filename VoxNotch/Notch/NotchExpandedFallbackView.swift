//
//  NotchExpandedFallbackView.swift
//  VoxNotch
//
//  Expanded view shown below the notch for all states.
//

import SwiftUI

struct NotchExpandedFallbackView: View {

  private let appState = AppState.shared

  /// Single value that captures which phase the UI is in, used as the
  /// sole animation driver so that simultaneous boolean changes don't
  /// produce competing animations.
  private var displayPhase: DisplayPhase {
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
      .id(displayPhase)
      .transition(.blurReplace)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .frame(minWidth: 280)
      .animation(.smooth(duration: 0.35), value: displayPhase)
      .animation(.smooth(duration: 0.2), value: appState.modelSelectionIndex)
      .animation(.smooth(duration: 0.2), value: appState.toneSelectionIndex)
  }

  @ViewBuilder
  private var content: some View {
    if appState.isModelSelecting {
      modelSelectionView
    } else if appState.isToneSelecting {
      toneSelectionView
    } else if appState.isRecording {
      recordingView
    } else if appState.isWarmingUp {
      spinnerRow(title: "Warming up…")
    } else if appState.isTranscribing {
      spinnerRow(title: "Transcribing…")
    } else if appState.isProcessingLLM {
      spinnerRow(title: "Processing…")
    } else if appState.isDownloadingModel {
      downloadRow
    } else if appState.modelsNeeded {
      transientRow(
        icon: "exclamationmark.triangle.fill",
        color: .yellow,
        title: appState.modelsNeededMessage
      )
    } else if let error = appState.lastError {
      transientRow(
        icon: "xmark.circle.fill",
        color: .red,
        title: error
      )
    } else if appState.isShowingSuccess {
      transientRow(
        icon: "checkmark.circle.fill",
        color: .green,
        title: "Text inserted"
      )
    } else if appState.isShowingClipboard {
      transientRow(
        icon: "doc.on.clipboard.fill",
        color: .green,
        title: "Copied to clipboard"
      )
    } else {
      EmptyView()
    }
  }

  // MARK: - Recording

  private var recordingView: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(.red)
        .frame(width: 10, height: 10)

      ScrollingWaveformView(level: appState.audioLevel)
        .frame(maxWidth: .infinity)
        .frame(height: 24)

      Text(formatDuration(appState.recordingDuration))
        .font(.system(size: 13, design: .monospaced))
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
    }
  }

  // MARK: - Spinner Row

  private func spinnerRow(title: String) -> some View {
    HStack(spacing: 12) {
      ProgressView()
        .controlSize(.small)

      Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
    }
  }

  // MARK: - Download

  private var downloadRow: some View {
    HStack(spacing: 12) {
      ProgressView(value: appState.modelDownloadProgress)
        .frame(maxWidth: .infinity)

      Text("\(Int(appState.modelDownloadProgress * 100))%")
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
    }
  }

  // MARK: - Model Selection

  private var modelSelectionView: some View {
    HStack(spacing: 16) {
      Image(systemName: "arrow.left")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)

      modelNameLabel
        .frame(maxWidth: .infinity)

      Image(systemName: "arrow.right")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
  }

  private var modelNameLabel: some View {
    Group {
      let candidates = appState.modelSelectionCandidates
      let index = appState.modelSelectionIndex

      if index < candidates.count {
        Text(candidates[index].displayName)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.primary)
          .id("model-\(index)")
          .transition(.blurReplace)
      } else {
        Text("More Models…")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.purple)
          .id("model-more")
          .transition(.blurReplace)
      }
    }
  }

  // MARK: - Tone Selection

  private var toneSelectionView: some View {
    HStack(spacing: 16) {
      Image(systemName: "arrow.up")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)

      toneNameLabel
        .frame(maxWidth: .infinity)

      Image(systemName: "arrow.down")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
  }

  private var toneNameLabel: some View {
    Group {
      let candidates = appState.toneSelectionCandidates
      let index = appState.toneSelectionIndex

      if index < candidates.count {
        Text(candidates[index].displayName)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.primary)
          .id("tone-\(index)")
          .transition(.blurReplace)
      } else {
        Text("More Tones…")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.purple)
          .id("tone-more")
          .transition(.blurReplace)
      }
    }
  }

  // MARK: - Transient Row

  private func transientRow(icon: String, color: Color, title: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 20))
        .foregroundStyle(color)

      Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(2)
    }
  }

  // MARK: - Helpers

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
  }
}

// MARK: - Display Phase

private enum DisplayPhase: Equatable {
  case idle
  case recording
  case warmingUp
  case transcribing
  case processingLLM
  case downloading
  case modelsNeeded
  case error
  case success
  case clipboard
  case modelSelecting
  case toneSelecting
}
