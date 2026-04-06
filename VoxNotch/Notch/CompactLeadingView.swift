//
//  CompactLeadingView.swift
//  VoxNotch
//
//  Left-side compact content for the notch UI
//

import SwiftUI

struct CompactLeadingView: View {

  @Environment(NotchViewModel.self) private var vm
  @State private var dotBreathing = false

  var body: some View {
    content
      .frame(height: 24)
      .animation(.smooth(duration: 0.4), value: vm.displayPhase)
  }

  @ViewBuilder
  private var content: some View {
    switch vm.displayPhase {
    case .modelSelecting:
      arrowHints(horizontal: true)
    case .toneSelecting:
      arrowHints(horizontal: false)
    case .recording:
      recordingLeading
    case .warmingUp, .transcribing, .processingLLM:
      spinner
    case .downloading:
      ProgressView(value: vm.downloadProgress)
        .frame(maxWidth: .infinity)
    case .modelsNeeded:
      statusIcon("exclamationmark.triangle.fill", color: .notchAmber)
    case .error:
      statusIcon("xmark.circle.fill", color: .notchRed)
    case .outputInserted:
      statusIcon("checkmark.circle.fill", color: .notchGreen)
    case .outputClipboard:
      statusIcon("doc.on.clipboard.fill", color: .notchBlue)
    case .outputClipboardAborted:
      statusIcon("arrow.uturn.left.circle.fill", color: .notchAmber)
    case .confirmation:
      statusIcon("checkmark.circle.fill", color: .notchGreen)
    case .idle:
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

      ScrollingWaveformView(level: vm.audioLevel)
        .frame(maxWidth: .infinity)
    }
  }

  // MARK: - Spinner

  private var spinner: some View {
    ProgressView()
      .controlSize(.small)
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
