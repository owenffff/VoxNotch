//
//  CompactLeadingView.swift
//  VoxNotch
//
//  Left-side compact content for the notch UI
//

import SwiftUI

struct CompactLeadingView: View {

  private let appState = AppState.shared
  @State private var dotBreathing = false

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
    if let output = appState.outputNotification {
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
      statusIcon("exclamationmark.triangle.fill", color: .notchAmber)
    } else if appState.lastError != nil {
      statusIcon("xmark.circle.fill", color: .notchRed)
    } else if let result = appState.outputNotification {
      switch result {
      case .inserted:
        statusIcon("checkmark.circle.fill", color: .notchGreen)
      case .clipboard:
        statusIcon("doc.on.clipboard.fill", color: .notchBlue)
      case .clipboardAborted:
        statusIcon("arrow.uturn.left.circle.fill", color: .notchAmber)
      }
    } else {
      statusIcon("waveform", color: .secondary)
    }
  }

  // MARK: - Recording

  private var recordingLeading: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(Color.notchRed)
        .frame(width: 8, height: 8)
        .opacity(dotBreathing ? 0.3 : 1.0)
        .onAppear { dotBreathing = true }
        .onDisappear { dotBreathing = false }
        .animation(
          .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
          value: dotBreathing
        )

      ScrollingWaveformView(level: AudioVisualizationState.shared.audioLevel)
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
  case modelsNeeded, error, success, clipboard, clipboardAborted
  case modelSelecting, toneSelecting
}
