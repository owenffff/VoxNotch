//
//  CompactLeadingView.swift
//  VoxNotch
//
//  Left-side compact content for the notch UI
//

import SwiftUI

struct CompactLeadingView: View {

  private let appState = AppState.shared

  /// Single animation driver derived from AppState, avoiding
  /// competing `.animation()` modifiers.
  private var displayPhase: CompactPhase {
    switch appState.dictationPhase {
    case .modelSelecting: return .modelSelecting
    case .toneSelecting:  return .toneSelecting
    case .recording:      return .recording
    case .warmingUp, .transcribing, .processingLLM:
      return .processing
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
      arrowHints(horizontal: true)
    } else if case .toneSelecting = appState.dictationPhase {
      arrowHints(horizontal: false)
    } else if case .recording = appState.dictationPhase {
      recordingLeading
    } else if case .warmingUp = appState.dictationPhase {
      spinner
    } else if case .transcribing = appState.dictationPhase {
      spinner
    } else if case .processingLLM = appState.dictationPhase {
      spinner
    } else if appState.isDownloadingModel {
      progressBar
    } else if appState.modelsNeeded {
      statusIcon("exclamationmark.triangle", color: .yellow)
    } else if appState.lastError != nil {
      statusIcon("xmark.circle.fill", color: .red)
    } else if appState.isShowingSuccess {
      statusIcon("checkmark.circle.fill", color: .green)
    } else if appState.isShowingClipboard {
      statusIcon("doc.on.clipboard", color: .green)
    } else {
      statusIcon("waveform", color: .secondary)
    }
  }

  // MARK: - Recording

  private var recordingLeading: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(.red)
        .frame(width: 8, height: 8)

      ScrollingWaveformView(level: appState.audioLevel)
        .frame(maxWidth: .infinity)
    }
  }

  // MARK: - Spinner

  private var spinner: some View {
    ProgressView()
      .controlSize(.small)
  }

  // MARK: - Progress Bar

  private var progressBar: some View {
    ProgressView(value: appState.modelDownloadProgress)
      .frame(maxWidth: .infinity)
  }

  // MARK: - Arrow Hints

  /// `horizontal: true` → ← →, `horizontal: false` → ↑ ↓
  private func arrowHints(horizontal: Bool) -> some View {
    Text(horizontal ? "\u{2190} \u{2192}" : "\u{2191} \u{2193}")
      .font(.system(size: 11))
      .foregroundStyle(.tertiary)
  }

  // MARK: - Status Icon

  private func statusIcon(_ name: String, color: Color) -> some View {
    Image(systemName: name)
      .foregroundStyle(color)
      .font(.system(size: 14))
  }
}

// MARK: - Compact Phase

private enum CompactPhase: Equatable {
  case idle, recording, processing, downloading
  case modelsNeeded, error, success, clipboard
  case modelSelecting, toneSelecting
}
