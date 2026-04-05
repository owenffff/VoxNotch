//
//  MockLLMProcessing.swift
//  VoxNotchTests
//

import Foundation
@testable import VoxNotch

final class MockLLMProcessing: LLMProcessing {
    var isEnabled: Bool = false

    var processCallCount = 0
    var lastProcessedText: String?
    var stubbedResult: LLMProcessingResult?

    func processWithResult(text: String) async -> LLMProcessingResult {
        processCallCount += 1
        lastProcessedText = text
        return stubbedResult ?? .skipped(originalText: text)
    }
}
