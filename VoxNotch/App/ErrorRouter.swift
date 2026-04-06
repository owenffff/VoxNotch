//
//  ErrorRouter.swift
//  VoxNotch
//
//  Centralized error routing: user-facing errors → ErrorState,
//  non-blocking warnings → LLM warning state,
//  log-only errors → os.log.
//

import Foundation
import os.log

@MainActor
final class ErrorRouter {

    private let errorState: ErrorState
    private let appState: AppState
    private let logger = Logger(subsystem: "com.voxnotch", category: "ErrorRouter")

    nonisolated init(errorState: ErrorState, appState: AppState) {
        self.errorState = errorState
        self.appState = appState
    }

    /// Convenience init using shared instances. Must be called from MainActor context.
    @MainActor convenience init() {
        self.init(errorState: .shared, appState: .shared)
    }

    /// Surface a user-facing error (shown in notch UI).
    func report(_ error: Error, audioURL: URL? = nil) {
        errorState.lastError = error.localizedDescription
        errorState.lastErrorRecovery = (error as? LocalizedError)?.recoverySuggestion
        errorState.lastAudioURL = audioURL
        logger.error("Reported: \(error.localizedDescription)")
    }

    /// Surface a non-blocking warning (LLM fallback).
    func reportWarning(_ message: String, canRetry: Bool = false) {
        appState.setLLMWarning(message, canRetry: canRetry)
        logger.warning("Warning: \(message)")
    }

    /// Log-only error (database, sound playback, etc.).
    func logOnly(_ error: Error, context: String) {
        logger.error("[\(context)] \(error.localizedDescription)")
    }

    /// Clear user-facing error state.
    func clear() {
        errorState.clear()
    }
}
