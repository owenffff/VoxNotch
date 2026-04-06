//
//  CompactTrailingView.swift
//  VoxNotch
//
//  Right-side compact content for the notch UI
//

import SwiftUI

struct CompactTrailingView: View {

  @Environment(NotchViewModel.self) private var vm

  var body: some View {
    content
      .frame(height: 24)
      .animation(.smooth(duration: 0.4), value: vm.displayPhase)
  }

  @ViewBuilder
  private var content: some View {
    switch vm.displayPhase {
    case .modelSelecting:
      modelName
    case .toneSelecting:
      toneName
    case .recording:
      durationTimer
    case .downloading:
      percentageText
    case .modelsNeeded, .error, .warmingUp, .transcribing, .processingLLM,
         .outputInserted, .outputClipboard, .outputClipboardAborted,
         .confirmation, .idle:
      statusText(vm.statusText)
    }
  }

  // MARK: - Duration Timer

  private var durationTimer: some View {
    Text(vm.statusText)
      .font(.system(size: 12, design: .monospaced))
      .foregroundStyle(.secondary)
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
    Text("\(Int(vm.downloadProgress * 100))%")
      .font(.system(size: 12, design: .monospaced))
      .foregroundStyle(.secondary)
  }

  // MARK: - Model Name

  private var modelName: some View {
    Group {
      if let name = vm.modelSelectionName {
        Text(name)
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
      if let name = vm.toneSelectionName {
        Text(name)
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
