//
//  MockNotchPresenter.swift
//  VoxNotchTests
//

import Foundation
@testable import VoxNotch

@MainActor
final class MockNotchPresenter: NotchPresenting {
    nonisolated init() {}

    var showRecordingCallCount = 0
    var showTranscribingCallCount = 0
    var showProcessingLLMCallCount = 0
    var showOutputResultCallCount = 0
    var lastOutputResult: OutputResult?
    var showErrorCallCount = 0
    var lastErrorMessage: String?
    var showModelSelectorCallCount = 0
    var showToneSelectorCallCount = 0
    var showModelsNeededCallCount = 0
    var showConfirmationCallCount = 0
    var hideCallCount = 0
    var clearTransientCallCount = 0

    func showRecording() { showRecordingCallCount += 1 }
    func showTranscribing() { showTranscribingCallCount += 1 }
    func showProcessingLLM() { showProcessingLLMCallCount += 1 }
    func showOutputResult(_ result: OutputResult) {
        showOutputResultCallCount += 1
        lastOutputResult = result
    }
    func showError(_ message: String) {
        showErrorCallCount += 1
        lastErrorMessage = message
    }
    func showModelSelector() { showModelSelectorCallCount += 1 }
    func showToneSelector() { showToneSelectorCallCount += 1 }
    func showModelsNeeded(_ message: String) { showModelsNeededCallCount += 1 }
    func showConfirmation(_ message: String) { showConfirmationCallCount += 1 }
    func hide() { hideCallCount += 1 }
    func clearTransient() { clearTransientCallCount += 1 }
}
