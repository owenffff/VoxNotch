//
//  NotchPresenting.swift
//  VoxNotch
//
//  Protocol abstracting NotchManager for testability.
//

import Foundation

/// Abstraction over NotchManager so QuickDictationController can be tested
/// without real panel manipulation.
@MainActor
protocol NotchPresenting: AnyObject {
    func showRecording()
    func showTranscribing()
    func showProcessingLLM()
    func showOutputResult(_ result: OutputResult)
    func showError(_ message: String)
    func showModelSelector()
    func showToneSelector()
    func showModelsNeeded(_ message: String)
    func showConfirmation(_ message: String)
    func hide()
    func clearTransient()
}

extension NotchManager: NotchPresenting {}
