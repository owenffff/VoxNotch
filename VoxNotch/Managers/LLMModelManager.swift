//
//  LLMModelManager.swift
//  VoxNotch
//
//  Manages LLM model discovery and configuration for Ollama
//

import Foundation
import os.log

// MARK: - Ollama Model Info

/// Information about an Ollama model
struct OllamaModelInfo: Identifiable, Codable, Sendable {
  let name: String
  let size: Int64
  let modifiedAt: String?

  var id: String { name }

  /// Human-readable size string
  var sizeDescription: String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case size
    case modifiedAt = "modified_at"
  }
}

// MARK: - Curated Model Entry

/// A curated model recommendation for Ollama
struct CuratedOllamaModel: Identifiable, Sendable {
  let id: String
  let displayName: String
  let ollamaTag: String
  let estimatedSizeMB: Int
  let description: String

  var estimatedSizeDescription: String {
    if estimatedSizeMB >= 1024 {
      return String(format: "~%.1f GB", Double(estimatedSizeMB) / 1024.0)
    }
    return "~\(estimatedSizeMB) MB"
  }
}

// MARK: - Ollama Pull State

/// State of an Ollama model pull operation
enum OllamaPullState: Equatable, Sendable {
  case idle
  case pulling(progress: Double)
  case completed
  case failed(message: String)
}

// MARK: - LLM Model Manager

/// Manages LLM model discovery and downloads for local providers (Ollama)
///
/// Thread Safety: All mutable state is accessed on the MainActor.
@MainActor @Observable
final class LLMModelManager {

  // MARK: - Singleton

  static let shared = LLMModelManager()

  // MARK: - Properties

  private let logger = Logger(subsystem: "com.jingyuanliang.VoxNotch", category: "LLMModelManager")

  /// Models currently available on the Ollama server
  private(set) var ollamaModels: [OllamaModelInfo] = []

  /// Pull states for curated models
  private(set) var pullStates: [String: OllamaPullState] = [:]

  /// Whether we're currently fetching the model list
  private(set) var isLoadingModels = false

  /// Last error from model listing
  private(set) var lastError: String?

  /// Whether Ollama server is reachable
  private(set) var isOllamaReachable = false

  // MARK: - Curated Models

  /// Curated list of recommended Ollama models
  static let curatedModels: [CuratedOllamaModel] = [
    CuratedOllamaModel(
      id: "qwen3-0.6b",
      displayName: "Qwen3 0.6B",
      ollamaTag: "qwen3:0.6b",
      estimatedSizeMB: 400,
      description: "Fast, good for cues and quick tasks"
    ),
    CuratedOllamaModel(
      id: "llama3.2-3b",
      displayName: "Llama 3.2 3B",
      ollamaTag: "llama3.2:3b",
      estimatedSizeMB: 2000,
      description: "Good balance of speed and quality"
    ),
    CuratedOllamaModel(
      id: "mistral-7b",
      displayName: "Mistral 7B",
      ollamaTag: "mistral:7b",
      estimatedSizeMB: 4100,
      description: "High quality, instruction-tuned"
    ),
    CuratedOllamaModel(
      id: "phi4-mini",
      displayName: "Phi-4 Mini",
      ollamaTag: "phi4-mini:latest",
      estimatedSizeMB: 2400,
      description: "Microsoft, efficient reasoning"
    ),
  ]

  // MARK: - Initialization

  private init() {
    for model in Self.curatedModels {
      pullStates[model.id] = .idle
    }
  }

  // MARK: - Ollama Server Interaction

  /// Check if the Ollama server is reachable and fetch available models
  func refreshOllamaModels() async {
    await MainActor.run {
      isLoadingModels = true
      lastError = nil
    }

    let settings = SettingsManager.shared
    let baseURLString = settings.llmEndpointURL.isEmpty
      ? "http://localhost:11434"
      : settings.llmEndpointURL

    guard let baseURL = URL(string: baseURLString) else {
      await MainActor.run {
        isLoadingModels = false
        isOllamaReachable = false
        lastError = "Invalid Ollama URL"
      }
      return
    }

    let listURL = baseURL.appendingPathComponent("api/tags")

    do {
      var request = URLRequest(url: listURL)
      request.timeoutInterval = 5

      let (data, response) = try await URLSession.shared.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
      else {
        await MainActor.run {
          isLoadingModels = false
          isOllamaReachable = false
          lastError = "Ollama server returned error"
        }
        return
      }

      let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
      let models = decoded.models

      await MainActor.run {
        ollamaModels = models
        isOllamaReachable = true
        isLoadingModels = false
        updatePullStatesFromAvailable()
      }

      logger.info("Found \(models.count) Ollama models")

    } catch {
      await MainActor.run {
        isLoadingModels = false
        isOllamaReachable = false
        lastError = "Cannot connect to Ollama: \(error.localizedDescription)"
      }
      logger.warning("Failed to reach Ollama: \(error.localizedDescription)")
    }
  }

  /// Pull (download) a model via Ollama
  /// - Parameter model: The curated model entry to pull
  func pullModel(_ model: CuratedOllamaModel) async {
    await MainActor.run {
      pullStates[model.id] = .pulling(progress: 0)
    }

    let settings = SettingsManager.shared
    let baseURLString = settings.llmEndpointURL.isEmpty
      ? "http://localhost:11434"
      : settings.llmEndpointURL

    guard let baseURL = URL(string: baseURLString) else {
      await MainActor.run {
        pullStates[model.id] = .failed(message: "Invalid URL")
      }
      return
    }

    let pullURL = baseURL.appendingPathComponent("api/pull")

    do {
      var request = URLRequest(url: pullURL)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.timeoutInterval = 3600 /// 1 hour for large models

      let body = try JSONEncoder().encode(["name": model.ollamaTag])
      request.httpBody = body

      let (bytes, response) = try await URLSession.shared.bytes(for: request)

      guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
      else {
        await MainActor.run {
          pullStates[model.id] = .failed(message: "Server error")
        }
        return
      }

      /// Stream pull progress (Ollama sends newline-delimited JSON)
      var lineBuffer = ""
      for try await byte in bytes {
        let char = Character(UnicodeScalar(byte))
        if char == "\n" {
          if let data = lineBuffer.data(using: .utf8),
             let progress = try? JSONDecoder().decode(OllamaPullProgress.self, from: data)
          {
            if let total = progress.total, total > 0, let completed = progress.completed {
              let pct = Double(completed) / Double(total)
              await MainActor.run {
                pullStates[model.id] = .pulling(progress: pct)
              }
            }

            if progress.status == "success" {
              await MainActor.run {
                pullStates[model.id] = .completed
              }
              logger.info("Successfully pulled \(model.ollamaTag)")
              await refreshOllamaModels()
              return
            }
          }
          lineBuffer = ""
        } else {
          lineBuffer.append(char)
        }
      }

      /// If we get here without "success", treat as completed (some versions don't emit it)
      await MainActor.run {
        pullStates[model.id] = .completed
      }
      await refreshOllamaModels()

    } catch {
      await MainActor.run {
        pullStates[model.id] = .failed(message: error.localizedDescription)
      }
      logger.error("Failed to pull \(model.ollamaTag): \(error.localizedDescription)")
    }
  }

  /// Pull a custom model by tag name
  /// - Parameter tag: The Ollama model tag (e.g. "llama3:latest")
  func pullCustomModel(tag: String) async {
    let customModel = CuratedOllamaModel(
      id: "custom-\(tag)",
      displayName: tag,
      ollamaTag: tag,
      estimatedSizeMB: 0,
      description: "Custom model"
    )
    await pullModel(customModel)
  }

  /// Check if a curated model is already available on the Ollama server
  func isModelAvailable(_ model: CuratedOllamaModel) -> Bool {
    /// Check both exact match and prefix match (Ollama may add `:latest`)
    let tag = model.ollamaTag
    return ollamaModels.contains { m in
      m.name == tag || m.name == "\(tag):latest" || tag.hasPrefix(m.name)
    }
  }

  /// Delete a model from Ollama
  /// - Parameter model: The curated model to delete
  func deleteModel(_ model: CuratedOllamaModel) async {
    let settings = SettingsManager.shared
    let baseURLString = settings.llmEndpointURL.isEmpty
      ? "http://localhost:11434"
      : settings.llmEndpointURL

    guard let baseURL = URL(string: baseURLString) else {
      return
    }

    let deleteURL = baseURL.appendingPathComponent("api/delete")

    do {
      var request = URLRequest(url: deleteURL)
      request.httpMethod = "DELETE"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body = try JSONEncoder().encode(["name": model.ollamaTag])
      request.httpBody = body

      let (_, response) = try await URLSession.shared.data(for: request)

      if let httpResponse = response as? HTTPURLResponse,
         httpResponse.statusCode == 200
      {
        logger.info("Deleted Ollama model: \(model.ollamaTag)")
        await MainActor.run {
          pullStates[model.id] = .idle
        }
        await refreshOllamaModels()
      }
    } catch {
      logger.error("Failed to delete model: \(error.localizedDescription)")
    }
  }

  // MARK: - Private

  private func updatePullStatesFromAvailable() {
    for model in Self.curatedModels {
      if isModelAvailable(model) {
        pullStates[model.id] = .completed
      } else if pullStates[model.id] == nil || pullStates[model.id] == .completed {
        /// Model was removed or not available
        pullStates[model.id] = .idle
      }
    }
  }
}

// MARK: - Ollama API Response Types

private struct OllamaTagsResponse: Decodable {
  let models: [OllamaModelInfo]
}

private struct OllamaPullProgress: Decodable {
  let status: String
  let total: Int64?
  let completed: Int64?
}
