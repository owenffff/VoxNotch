//
//  ErrorState.swift
//  VoxNotch
//
//  Observable sub-state for user-facing error display and retry.
//

import Foundation

@MainActor @Observable
final class ErrorState {

    static let shared = ErrorState()

    var lastError: String?
    var lastErrorRecovery: String?

    /// URL of the last recorded audio file (for retry)
    var lastAudioURL: URL?

    /// Whether transcription retry is available
    var canRetryTranscription: Bool {
        lastError != nil && lastAudioURL != nil
    }

    private init() {}

    func clear() {
        lastError = nil
        lastErrorRecovery = nil
    }

    func reset() {
        lastError = nil
        lastErrorRecovery = nil
        lastAudioURL = nil
    }
}
