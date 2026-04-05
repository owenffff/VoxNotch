//
//  LLMProcessing.swift
//  VoxNotch
//
//  Protocol abstracting LLMService for testability.
//

import Foundation

/// Abstraction over LLM post-processing so QuickDictationController can be tested with mocks.
protocol LLMProcessing: AnyObject {
    var isEnabled: Bool { get }
    func processWithResult(text: String) async -> LLMProcessingResult
}

extension LLMService: LLMProcessing {}
