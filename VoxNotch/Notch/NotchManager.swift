//
//  NotchManager.swift
//  VoxNotch
//
//  Owns the DynamicNotch instance and provides imperative show/hide API
//

import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
final class NotchManager {

    static let shared = NotchManager()

    private var notch: DynamicNotch<NotchContentView, EmptyView, EmptyView>?
    private var autoHideTask: Task<Void, Never>?
    private let appState = AppState.shared

    private init() {}

    // MARK: - Setup

    func setup() {
        let contentView = NotchContentView()
        notch = DynamicNotch(
            hoverBehavior: [.keepVisible],
            style: .auto,
            expanded: { contentView }
        )
    }

    // MARK: - Show Methods

    func showRecording() {
        cancelAutoHide()
        expandIfNeeded()
    }

    func showTranscribing() {
        cancelAutoHide()
        expandIfNeeded()
    }

    func showProcessingLLM() {
        cancelAutoHide()
        expandIfNeeded()
    }

    func showSuccess() {
        cancelAutoHide()
        appState.isShowingSuccess = true
        appState.isShowingClipboard = false
        expandIfNeeded()
        scheduleAutoHide(after: 1.5)
    }

    func showClipboard() {
        cancelAutoHide()
        appState.isShowingClipboard = true
        appState.isShowingSuccess = false
        expandIfNeeded()
        scheduleAutoHide(after: 1.5)
    }

    func showError(_ message: String) {
        cancelAutoHide()
        expandIfNeeded()
        scheduleAutoHide(after: 3.0)
    }

    func showModelSelector() {
        cancelAutoHide()
        expandIfNeeded()
    }

    func showToneSelector() {
        cancelAutoHide()
        expandIfNeeded()
    }

    func showModelsNeeded(_ message: String) {
        cancelAutoHide()
        expandIfNeeded()
    }

    func hide() {
        cancelAutoHide()
        appState.isShowingSuccess = false
        appState.isShowingClipboard = false
        Task {
            await notch?.hide()
        }
    }

    // MARK: - Private

    private func expandIfNeeded() {
        guard let notch, let screen = NSScreen.main else { return }
        Task {
            await notch.expand(on: screen)
        }
    }

    private func scheduleAutoHide(after seconds: Double) {
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await notch?.hide()
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}
