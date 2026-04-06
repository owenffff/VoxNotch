//
//  LLMService.swift
//  VoxNotch
//
//  Service for LLM text post-processing using configured provider
//

import Foundation
import os.log

// MARK: - LLM Processing Result

/// Result of LLM processing operation
enum LLMProcessingResult: Sendable {

  /// Successfully processed text
  case success(processedText: String)

  /// Processing failed, returning original text with error info
  case fallback(originalText: String, error: LLMError)

  /// Processing skipped (disabled or not configured)
  case skipped(originalText: String)

  /// The text to use (processed or original)
  var text: String {
    switch self {
    case .success(let processedText):
      return processedText

    case .fallback(let originalText, _):
      return originalText

    case .skipped(let originalText):
      return originalText
    }
  }

  /// Whether processing succeeded
  var didSucceed: Bool {
    if case .success = self {
      return true
    }
    return false
  }

  /// The error if processing failed
  var error: LLMError? {
    if case .fallback(_, let error) = self {
      return error
    }
    return nil
  }
}

/// Service for processing transcribed text through LLM
final class LLMService {

  // MARK: - Singleton

  static let shared = LLMService()

  // MARK: - Properties

  private let settings = SettingsManager.shared
  private let logger = Logger(subsystem: "com.voxnotch", category: "LLMService")

  /// Default timeout for LLM requests (in seconds)
  private let defaultTimeout: TimeInterval = 30

  /// Last error for retry functionality
  private(set) var lastError: LLMError?
  private(set) var lastOriginalText: String?

  // MARK: - Initialization

  private init() {}

  // MARK: - Public Methods

  /// Check if LLM processing is enabled and configured
  var isEnabled: Bool {
    guard settings.enablePostProcessing else {
      return false
    }

    /// For Apple Foundation Models, check availability
    if settings.llmProvider == "apple" {
      return AnyLanguageModelProvider.isAppleIntelligenceAvailable
    }

    /// For local providers, just need endpoint
    if settings.llmProvider == "local" {
      return !settings.llmEndpointURL.isEmpty
    }

    /// For cloud providers, need API key
    return hasAPIKey
  }

  /// Check if API key is available for current provider (local-only, always true)
  var hasAPIKey: Bool { true }

  /// Whether a retry is possible (has failed text to retry)
  var canRetry: Bool {
    lastError != nil && lastOriginalText != nil
  }

  /// Process text through the configured LLM provider
  /// - Parameter text: The transcribed text to process
  /// - Returns: The processed text, or original text if processing fails/disabled
  func process(text: String) async -> String {
    let result = await processWithResult(text: text)
    return result.text
  }

  /// Process text with detailed result information
  /// - Parameter text: The transcribed text to process
  /// - Returns: Processing result with success/failure info
  func processWithResult(text: String) async -> LLMProcessingResult {
    guard isEnabled else {
      logger.debug("LLM processing skipped: not enabled")
      return .skipped(originalText: text)
    }

    /// Clear previous retry state
    lastError = nil
    lastOriginalText = nil

    do {
      let provider = try createProvider()

      /// Wrap in timeout task to prevent hanging
      let processedText = try await withTimeout(seconds: defaultTimeout) {
        try await provider.process(text: text, prompt: self.settings.effectivePrompt)
      }

      logger.info("LLM processing succeeded")
      return .success(processedText: processedText)

    } catch let error as LLMError {
      return handleError(error, originalText: text)

    } catch is CancellationError {
      let timeoutError = LLMError.timeout
      return handleError(timeoutError, originalText: text)

    } catch {
      let wrappedError = LLMError.networkError(error)
      return handleError(wrappedError, originalText: text)
    }
  }

  /// Retry the last failed LLM processing
  /// - Returns: Processing result, or nil if no retry available
  func retry() async -> LLMProcessingResult? {
    guard let originalText = lastOriginalText else {
      logger.warning("Retry requested but no previous text available")
      return nil
    }

    logger.info("Retrying LLM processing")
    return await processWithResult(text: originalText)
  }

  /// Skip LLM and use original text (clears retry state)
  func skipLLM() {
    logger.info("LLM processing skipped by user")
    lastError = nil
    lastOriginalText = nil
  }

  // MARK: - Private Methods

  private func handleError(_ error: LLMError, originalText: String) -> LLMProcessingResult {
    /// Store for retry
    lastError = error
    lastOriginalText = originalText

    /// Log the error with appropriate level
    switch error {
    case .timeout:
      logger.warning("LLM processing timed out, using original text")

    case .rateLimited:
      logger.warning("LLM rate limited, using original text")

    case .noAPIKey:
      logger.error("LLM API key not found")

    default:
      logger.error("LLM processing failed: \(error.localizedDescription)")
    }

    return .fallback(originalText: originalText, error: error)
  }

  private func createProvider() throws -> LLMProvider {
    return try AnyLanguageModelProvider.create(
      provider: settings.llmProvider,
      modelName: settings.llmModel,
      endpointURL: settings.llmEndpointURL
    )
  }

  /// Execute async work with a timeout
  private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      /// Add the actual operation
      group.addTask {
        try await operation()
      }

      /// Add timeout task
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw CancellationError()
      }

      /// Return first completed result, cancel remaining
      guard let result = try await group.next() else {
        throw LLMError.timeout
      }

      group.cancelAll()
      return result
    }
  }
}
