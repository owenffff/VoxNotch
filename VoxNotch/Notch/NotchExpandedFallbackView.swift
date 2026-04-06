//
//  NotchExpandedFallbackView.swift
//  VoxNotch
//
//  Expanded view shown below the notch for all states.
//

import SwiftUI

struct NotchExpandedFallbackView: View {

  @Environment(NotchViewModel.self) private var vm
  @State private var dotBreathing = false

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, 14)
      .padding(.vertical, 2)
      .frame(width: 280)
      .clipped()
      .animation(.smooth(duration: 0.4), value: vm.displayPhase)
  }

  @ViewBuilder
  private var content: some View {
    switch vm.displayPhase {
    case .modelSelecting:
      modelSelectionView
    case .toneSelecting:
      toneSelectionView
    case .recording:
      recordingView
    case .warmingUp:
      spinnerRow(title: "Warming up…")
    case .transcribing:
      spinnerRow(title: "Transcribing…")
    case .processingLLM:
      spinnerRow(title: "Processing…")
    case .downloading:
      downloadRow
    case .modelsNeeded:
      transientRow(
        icon: "exclamationmark.triangle.fill",
        color: .notchAmber,
        title: vm.modelsNeededMessage
      )
    case .error:
      transientRow(
        icon: "xmark.circle.fill",
        color: .notchRed,
        title: shortenError(vm.errorMessage ?? "Error"),
        subtitle: vm.canRetry ? "Press hotkey to retry" : vm.errorRecovery
      )
    case .outputInserted:
      transientRow(icon: "checkmark.circle.fill", color: .notchGreen, title: "Text inserted",
                   subtitle: vm.hasLLMWarning ? "Tone skipped — LLM unavailable" : nil)
    case .outputClipboard:
      transientRow(icon: "doc.on.clipboard.fill", color: .notchBlue, title: "Copied — ⌘V to paste",
                   subtitle: vm.hasLLMWarning ? "Tone skipped — LLM unavailable" : nil)
    case .outputClipboardAborted:
      transientRow(icon: "arrow.uturn.left.circle.fill", color: .notchAmber, title: "App switched — ⌘V to paste",
                   subtitle: vm.hasLLMWarning ? "Tone skipped — LLM unavailable" : nil)
    case .confirmation:
      transientRow(icon: "checkmark.circle.fill", color: .notchGreen, title: vm.confirmationMessage)
    case .idle:
      EmptyView()
    }
  }

  // MARK: - Recording

  private var recordingView: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(Color.notchRed)
        .frame(width: 6, height: 6)
        .opacity(dotBreathing ? 0.3 : 1.0)
        .onAppear { dotBreathing = true }
        .onDisappear { dotBreathing = false }
        .animation(
          .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
          value: dotBreathing
        )

      ScrollingWaveformView(level: vm.audioLevel)
        .frame(maxWidth: .infinity)
        .frame(height: 14)

      Text(vm.statusText)
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
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
    }
  }

  // MARK: - Download

  private var downloadRow: some View {
    HStack(spacing: 10) {
      ProgressView(value: vm.downloadProgress)
        .frame(maxWidth: .infinity)

      Text("\(Int(vm.downloadProgress * 100))%")
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

      HStack(spacing: 6) {
        Image(systemName: "waveform")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        modelNameLabel
      }
      .frame(maxWidth: .infinity)

      Image(systemName: "arrow.right")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
    .animation(.smooth(duration: 0.2), value: vm.modelSelectionIndex)
  }

  private var modelNameLabel: some View {
    Group {
      if let name = vm.modelSelectionName {
        Text(name)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.primary)
          .id("model-\(vm.modelSelectionIndex)")
          .transition(.opacity)
      } else {
        Text("More Models…")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.purple)
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

      HStack(spacing: 6) {
        Image(systemName: "textformat")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        toneNameLabel
      }
      .frame(maxWidth: .infinity)

      Image(systemName: "arrow.down")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
    .animation(.smooth(duration: 0.2), value: vm.toneSelectionIndex)
  }

  private var toneNameLabel: some View {
    Group {
      if let name = vm.toneSelectionName {
        Text(name)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.primary)
          .id("tone-\(vm.toneSelectionIndex)")
          .transition(.opacity)
      } else {
        Text("More Tones…")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.purple)
          .id("tone-more")
          .transition(.opacity)
      }
    }
  }

  // MARK: - Transient Row

  private func transientRow(icon: String, color: Color, title: String, subtitle: String? = nil) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 12))
        .foregroundStyle(color)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.tail)

        if let subtitle {
          Text(subtitle)
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
    }
  }

  // MARK: - Helpers

  private func shortenError(_ message: String) -> String {
    var msg = message
    for prefix in ["The operation couldn't be completed. ", "The operation could not be completed. "] {
      if msg.hasPrefix(prefix) { msg = String(msg.dropFirst(prefix.count)) }
    }
    if let range = msg.range(of: #"\s*\([^)]*error\s+\d+[^)]*\)\.?$"#, options: [.regularExpression, .caseInsensitive]) {
      msg = String(msg[msg.startIndex..<range.lowerBound])
    }
    return msg
  }
}
