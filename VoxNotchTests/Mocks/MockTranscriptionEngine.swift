//
//  MockTranscriptionEngine.swift
//  VoxNotchTests
//

import Foundation
@testable import VoxNotch

final class MockTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    var isReadyValue: Bool = true
    var isReady: Bool { get async { isReadyValue } }

    var preloadCallCount = 0
    var ensureReadyCallCount = 0
    var transcribeCallCount = 0
    var reconfigureCallCount = 0
    var lastTranscribeURL: URL?

    var stubbedResult: TranscriptionResult?
    var stubbedError: Error?
    var stubbedEnsureReadyError: Error?

    func preloadModel() {
        preloadCallCount += 1
    }

    func ensureModelReady() async throws {
        ensureReadyCallCount += 1
        if let error = stubbedEnsureReadyError { throw error }
    }

    func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
        transcribeCallCount += 1
        lastTranscribeURL = audioURL
        if let error = stubbedError { throw error }
        return stubbedResult ?? TranscriptionResult(
            text: "mock transcription",
            confidence: 0.95,
            audioDuration: 2.0,
            processingTime: 0.1,
            provider: "Mock",
            language: language,
            segments: nil
        )
    }

    func reconfigure() {
        reconfigureCallCount += 1
    }
}
