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
    if appState.isModelSelecting      { return .modelSelecting }
    if appState.isToneSelecting       { return .toneSelecting }
    if appState.isRecording           { return .recording }
    if appState.isWarmingUp           { return .warmingUp }
    if appState.isTranscribing        { return .transcribing }
    if appState.isProcessingLLM       { return .processingLLM }
    if appState.isDownloadingModel    { return .downloading }
    if appState.modelsNeeded          { return .modelsNeeded }
    if appState.lastError != nil      { return .error }
    if appState.isShowingSuccess      { return .success }
    if appState.isShowingClipboard    { return .clipboard }
    if appState.isShowingConfirmation { return .confirmation }
    return .idle
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, minHeight: 20, alignment: .center)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .frame(width: 280)
      .clipped()
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
    } else if appState.isShowingConfirmation {
      transientRow(
        icon: "checkmark.circle.fill",
        color: .green,
        title: appState.confirmationMessage
      )
    } else {
      EmptyView()
    }
  }

  // MARK: - Recording

  private var recordingView: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(.red)
        .frame(width: 8, height: 8)

      ScrollingWaveformView(level: appState.audioLevel)
        .frame(maxWidth: .infinity)
        .frame(height: 20)

      Text(formatDuration(appState.recordingDuration))
        .font(.system(size: 13, design: .monospaced))
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
    }
  }

  // MARK: - Spinner Row

  private func spinnerRow(title: String) -> some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)

      Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .contentTransition(.interpolate)
    }
  }

  // MARK: - Download

  private var downloadRow: some View {
    HStack(spacing: 10) {
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
    HStack(spacing: 12) {
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
          .contentTransition(.interpolate)
          .id("model-\(index)")
          .transition(.opacity)
      } else {
        Text("More Models…")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.purple)
          .contentTransition(.interpolate)
          .id("model-more")
          .transition(.opacity)
      }
    }
  }

  // MARK: - Tone Selection

  private var toneSelectionView: some View {
    HStack(spacing: 12) {
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
          .contentTransition(.interpolate)
          .id("tone-\(index)")
          .transition(.opacity)
      } else {
        Text("More Tones…")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.purple)
          .contentTransition(.interpolate)
          .id("tone-more")
          .transition(.opacity)
      }
    }
  }

  // MARK: - Transient Row

  private func transientRow(icon: String, color: Color, title: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundStyle(color)
        .contentTransition(.interpolate)

      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.tail)
        .contentTransition(.interpolate)
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
  case confirmation
  case modelSelecting
  case toneSelecting
}
