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
/// Supports: Apple Intelligence, Ollama.
/// Bridges VoxNotch's `LLMProvider.process(text:prompt:)` interface to
/// `LanguageModelSession.respond(to:)`.
// Thread Safety: All stored properties are immutable (`let`). The `any LanguageModel` existential
// may not itself conform to Sendable, so @unchecked is retained for that reason only.
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
      <transcription>
      \(text)
      </transcription>

      Edit the above transcription per your instructions. Output ONLY the edited text — nothing else.
      """
      let response = try await session.respond(to: userMessage)
      let content = sanitizeResponse(response.content)
      return content
    } catch {
      logger.error("AnyLanguageModel error: \(error.localizedDescription)")
      throw LLMError.apiError(error.localizedDescription)
    }
  }

  // MARK: - Response Sanitization

  /// Strip conversational preamble and trailing meta-commentary that LLMs sometimes add
  /// despite being told to output only the edited text.
  private func sanitizeResponse(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // Strip "Cleaned text:" echo some models produce
    if text.lowercased().hasPrefix("cleaned text:") {
      text = String(text.dropFirst("Cleaned text:".count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Strip conversational preamble — only if remainder is non-empty.
    // Each prefix pattern is matched case-insensitively at the start of the response.
    // We strip up to and including the first newline after the preamble sentence.
    let preamblePrefixes = [
      "sure,", "sure!", "sure.", "sure —", "sure–", "sure-",
      "of course,", "of course!", "of course.",
      "certainly,", "certainly!", "certainly.",
      "absolutely,", "absolutely!", "absolutely.",
      "here's the", "here is the", "here's your", "here is your",
      "i've rephrased", "i've rewritten", "i've edited", "i've converted",
      "i'll help", "i'd be happy to", "i would be happy to",
    ]

    let lowered = text.lowercased()
    for prefix in preamblePrefixes {
      if lowered.hasPrefix(prefix) {
        // Find the end of this preamble sentence (first newline or ". " / ":\n")
        if let newlineRange = text.range(of: "\n") {
          let remainder = String(text[newlineRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if !remainder.isEmpty {
            text = remainder
          }
        } else if let periodSpace = text.range(of: ". ", range: text.index(text.startIndex, offsetBy: prefix.count)..<text.endIndex) {
          // Preamble like "Sure, here is the formal version. The quarterly..."
          let remainder = String(text[periodSpace.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if !remainder.isEmpty {
            text = remainder
          }
        }
        break
      }
    }

    // Strip trailing meta-commentary (e.g., "Let me know if you'd like...")
    let trailingSuffixes = [
      "\nlet me know if",
      "\nfeel free to",
      "\nplease let me know",
      "\nhope this helps",
      "\nis there anything",
    ]
    let loweredText = text.lowercased()
    for suffix in trailingSuffixes {
      if let range = loweredText.range(of: suffix) {
        let trimmed = String(text[text.startIndex..<range.lowerBound])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          text = trimmed
        }
        break
      }
    }

    return text
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
      let model = AnyLanguageModel.SystemLanguageModel.default
      let available = model.isAvailable
      if !available {
        let logger = Logger(subsystem: "com.voxnotch", category: "AnyLanguageModelProvider")
        logger.warning("Apple Intelligence not available. Availability: \(String(describing: model.availability))")
      }
      return available
    }
    #endif
    return false
  }

  /// Whether the current platform supports Apple Intelligence (compile-time + OS version check)
  static var isAppleIntelligenceSupported: Bool {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      return true
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
