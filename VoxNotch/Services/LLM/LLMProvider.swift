//
//  LLMProvider.swift
//  VoxNotch
//
//  Protocol and implementations for LLM text post-processing
//

import Foundation

// MARK: - LLM Provider Protocol

/// Protocol for LLM text processing providers
protocol LLMProvider: Sendable {

  /// Process text through the LLM
  /// - Parameters:
  ///   - text: The text to process
  ///   - prompt: The system/user prompt for processing
  /// - Returns: The processed text
  func process(text: String, prompt: String) async throws -> String
}

// MARK: - LLM Errors

enum LLMError: LocalizedError {
  case noAPIKey
  case invalidURL
  case networkError(Error)
  case invalidResponse
  case apiError(String)
  case timeout
  case rateLimited
  case decodingError(Error)

  var errorDescription: String? {
    switch self {
    case .noAPIKey:
      return "API key not found"
    case .invalidURL:
      return "Invalid API endpoint URL"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .invalidResponse:
      return "Invalid response from API"
    case .apiError(let message):
      return "API error: \(message)"
    case .timeout:
      return "Request timed out"
    case .rateLimited:
      return "Rate limited by API"
    case .decodingError(let error):
      return "Failed to decode response: \(error.localizedDescription)"
    }
  }
}

