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

    // MARK: - LLM Warning (non-blocking, transcription still succeeded)

    /// Warning message when LLM failed but transcription succeeded
    var llmWarning: String?

    /// Whether LLM processing failed and retry is available
    var llmFailedWithRetry: Bool = false

    private init() {}
    init(forTesting: Void) {}

    func clear() {
        lastError = nil
        lastErrorRecovery = nil
    }

    func clearLLMWarning() {
        llmWarning = nil
        llmFailedWithRetry = false
    }

    func reset() {
        lastError = nil
        lastErrorRecovery = nil
        lastAudioURL = nil
        llmWarning = nil
        llmFailedWithRetry = false
    }
}
