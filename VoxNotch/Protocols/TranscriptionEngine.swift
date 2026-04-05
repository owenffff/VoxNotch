//
//  TranscriptionEngine.swift
//  VoxNotch
//
//  Protocol abstracting TranscriptionService for testability.
//

import Foundation

/// Abstraction over speech-to-text so QuickDictationController can be tested with mocks.
protocol TranscriptionEngine: AnyObject, Sendable {
    var isReady: Bool { get async }
    func preloadModel()
    func ensureModelReady() async throws
    func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult
    func reconfigure()
}

extension TranscriptionService: TranscriptionEngine {}
