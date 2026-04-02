//
//  NotchContentView.swift
//  VoxNotch
//
//  SwiftUI content rendered inside the DynamicNotchKit notch panel
//

import SwiftUI

struct NotchContentView: View {

    // DynamicNotchKit hosts this view in its own NSWindow, so @Environment
    // may not propagate. Use AppState.shared directly via @Observable.
    private let appState = AppState.shared

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minWidth: 200)
        .animation(.smooth(duration: 0.3), value: appState.isRecording)
        .animation(.smooth(duration: 0.3), value: appState.isTranscribing)
        .animation(.smooth(duration: 0.3), value: appState.isProcessingLLM)
        .animation(.smooth(duration: 0.3), value: appState.isModelSelecting)
        .animation(.smooth(duration: 0.3), value: appState.isToneSelecting)
    }

    @ViewBuilder
    private var content: some View {
        if appState.isModelSelecting {
            modelSelectorContent
        } else if appState.isToneSelecting {
            toneSelectorContent
        } else if appState.isRecording {
            recordingContent
        } else if appState.isWarmingUp {
            statusContent(icon: "gear", color: .orange, text: "Warming up...")
        } else if appState.isTranscribing {
            statusContent(icon: "waveform", color: .blue, text: "Transcribing...")
        } else if appState.isProcessingLLM {
            statusContent(icon: "sparkles", color: .purple, text: "Processing...")
        } else if appState.isDownloadingModel {
            downloadContent
        } else if appState.modelsNeeded {
            statusContent(icon: "exclamationmark.triangle", color: .yellow, text: appState.modelsNeededMessage)
        } else if let error = appState.lastError {
            statusContent(icon: "xmark.circle.fill", color: .red, text: error)
        } else if appState.isShowingSuccess {
            statusContent(icon: "checkmark.circle.fill", color: .green, text: "Text inserted")
        } else if appState.isShowingClipboard {
            statusContent(icon: "doc.on.clipboard", color: .green, text: "Copied to clipboard")
        } else {
            // Fallback — should rarely show since notch is hidden when idle
            statusContent(icon: "waveform", color: .secondary, text: "VoxNotch")
        }
    }

    // MARK: - Recording

    private var recordingContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            // Frequency bars
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.red.opacity(0.8))
                        .frame(width: 3, height: barHeight(for: i))
                }
            }
            .frame(height: 20)

            Text(formatDuration(appState.recordingDuration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Text(SettingsManager.shared.hotkeyModifiers)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let bands = appState.audioFrequencyBands
        guard index < bands.count else { return 4 }
        let normalized = CGFloat(bands[index])
        return max(4, min(20, normalized * 20))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Status (generic single-row)

    private func statusContent(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Download Progress

    private var downloadContent: some View {
        HStack(spacing: 10) {
            ProgressView(value: appState.modelDownloadProgress)
                .frame(width: 100)
            Text("\(Int(appState.modelDownloadProgress * 100))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Model Selector

    private var modelSelectorContent: some View {
        HStack(spacing: 8) {
            Text("\u{2190} \u{2192}")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

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

    // MARK: - Tone Selector

    private var toneSelectorContent: some View {
        HStack(spacing: 8) {
            Text("\u{2191} \u{2193}")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

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
