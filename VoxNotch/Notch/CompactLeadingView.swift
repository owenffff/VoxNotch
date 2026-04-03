//
//  CompactLeadingView.swift
//  VoxNotch
//
//  Left-side content for DynamicNotchKit compact mode
//

import SwiftUI

struct CompactLeadingView: View {

  private let appState = AppState.shared

  var body: some View {
    content
      .frame(height: 24)
      .animation(.smooth(duration: 0.3), value: appState.isRecording)
      .animation(.smooth(duration: 0.3), value: appState.isTranscribing)
      .animation(.smooth(duration: 0.3), value: appState.isProcessingLLM)
      .animation(.smooth(duration: 0.3), value: appState.isModelSelecting)
      .animation(.smooth(duration: 0.3), value: appState.isToneSelecting)
  }

  @ViewBuilder
  private var content: some View {
    if appState.isModelSelecting {
      arrowHints(horizontal: true)
    } else if appState.isToneSelecting {
      arrowHints(horizontal: false)
    } else if appState.isRecording {
      recordingLeading
    } else if appState.isWarmingUp || appState.isTranscribing || appState.isProcessingLLM {
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
