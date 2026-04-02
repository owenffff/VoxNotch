//
//  AnyLanguageModelProvider.swift
//  VoxNotch
//
//  Unified LLM provider wrapping AnyLanguageModel for all backends
//

import AnyLanguageModel
import Foundation
import os.log

// MARK: - AnyLanguageModel Provider

/// LLM provider that delegates to AnyLanguageModel's unified API.
///
/// Supports: Apple Intelligence, Ollama, OpenAI, Anthropic, Gemini.
/// Bridges VoxNotch's `LLMProvider.process(text:prompt:)` interface to
/// `LanguageModelSession.respond(to:)`.
final class AnyLanguageModelProvider: LLMProvider, @unchecked Sendable {

  // MARK: - Properties

  private let model: any LanguageModel
  private let logger = Logger(subsystem: "com.voxnotch", category: "AnyLanguageModelProvider")

  // MARK: - Initialization

  init(model: any LanguageModel) {
    self.model = model
  }

  // MARK: - LLMProvider

  func process(text: String, prompt: String) async throws -> String {
    let session = LanguageModelSession(model: model, instructions: prompt)

    do {
      let userMessage = """
      Please edit the following transcription according to the system instructions.
      
      <transcription>
      \(text)
      </transcription>
      """
      let response = try await session.respond(to: userMessage)
      // Strip any leading "Cleaned text:" echo that some models produce
      var content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      if content.lowercased().hasPrefix("cleaned text:") {
        content = String(content.dropFirst("Cleaned text:".count))
          .trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return content
    } catch {
      logger.error("AnyLanguageModel error: \(error.localizedDescription)")
      throw LLMError.apiError(error.localizedDescription)
    }
  }

  // MARK: - Structured Generation

  /// Create a new LanguageModelSession for structured generation
  /// - Parameter instructions: System instructions for the session
  /// - Returns: A configured `LanguageModelSession`
  func createSession(instructions: String) -> LanguageModelSession {
    LanguageModelSession(model: model, instructions: instructions)
  }

  // MARK: - Factory

  /// Create an AnyLanguageModel instance from the current VoxNotch settings.
  /// - Parameters:
  ///   - provider: Provider identifier string ("apple" or "local")
  ///   - modelName: Model identifier string (e.g. "llama3.2")
  ///   - endpointURL: Optional endpoint URL for Ollama
  /// - Returns: A configured `AnyLanguageModelProvider`
  static func create(
    provider: String,
    modelName: String,
    endpointURL: String? = nil
  ) throws -> AnyLanguageModelProvider {
    let languageModel: any LanguageModel

    switch provider {
    case "apple":
      languageModel = try createAppleModel()

    case "local":
      guard let urlString = endpointURL,
            let url = URL(string: urlString)
      else {
        throw LLMError.invalidURL
      }
      languageModel = OllamaLanguageModel(
        baseURL: url,
        model: modelName.isEmpty ? "llama3" : modelName
      )

    default:
      throw LLMError.apiError("Unknown provider: \(provider)")
    }

    return AnyLanguageModelProvider(model: languageModel)
  }

  // MARK: - Apple Intelligence Availability

  /// Whether Apple Intelligence (Foundation Models) is available on this device
  static var isAppleIntelligenceAvailable: Bool {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      return AnyLanguageModel.SystemLanguageModel.default.isAvailable
    }
    #endif
    return false
  }

  // MARK: - Private

  private static func createAppleModel() throws -> any LanguageModel {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      return AnyLanguageModel.SystemLanguageModel.default
    }
    #endif
    throw LLMError.apiError("Apple Intelligence not available on this device")
  }
}
