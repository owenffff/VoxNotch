//
//  HuggingFaceHubService.swift
//  VoxNotch
//
//  Queries the Hugging Face Hub API for MLX ASR models and discovers local cache.
//

import Foundation
import os.log

// MARK: - HF Model Info

/// Metadata for a Hugging Face model returned by the Hub API.
struct HFModelInfo: Identifiable, Decodable {
  let id: String          // e.g. "mlx-community/GLM-ASR-Nano-2512-4bit"
  let siblings: [Sibling]
  let tags: [String]

  struct Sibling: Decodable {
    let rfilename: String
    let size: Int?

    private enum CodingKeys: String, CodingKey {
      case rfilename, size
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id = "modelId"
    case siblings, tags
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    siblings = (try? c.decode([Sibling].self, forKey: .siblings)) ?? []
    tags = (try? c.decode([String].self, forKey: .tags)) ?? []
  }

  var displayName: String {
    String(id.split(separator: "/").last ?? Substring(id))
  }

  var totalSizeBytes: Int64 {
    Int64(siblings.compactMap(\.size).reduce(0, +))
  }

  var isAlreadyAdded: Bool {
    CustomModelRegistry.shared.contains(repoID: id)
  }

  /// Whether the model is present in the local HF Hub cache
  var isOnDisk: Bool {
    let folder = id.replacingOccurrences(of: "/", with: "_")
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache/huggingface/hub/mlx-audio")
      .appendingPathComponent(folder)
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path)
    return !(contents ?? []).isEmpty
  }

  /// Compatibility family inferred from the model ID
  var family: HFModelFamily {
    let lower = id.lowercased()
    if lower.contains("glm") { return .glm }
    if lower.contains("qwen3") { return .qwen3 }
    if lower.contains("voxtral") { return .voxtral }
    if lower.contains("parakeet") { return .parakeet }
    return .unknown
  }
}

// MARK: - Model Family

enum HFModelFamily: String, CaseIterable, Identifiable {
  case all = "All"
  case glm = "GLM-ASR"
  case qwen3 = "Qwen3-ASR"
  case voxtral = "Voxtral"
  case parakeet = "Parakeet"
  case unknown = "Other"

  var id: String { rawValue }

  var badgeColor: String {
    switch self {
    case .all:      "gray"
    case .glm:      "green"
    case .qwen3:    "blue"
    case .voxtral:  "purple"
    case .parakeet: "orange"
    case .unknown:  "gray"
    }
  }
}

// MARK: - HuggingFace Hub Service

/// Lightweight actor that queries the HF Hub API and discovers local cache entries.
actor HuggingFaceHubService {

  static let shared = HuggingFaceHubService()

  private let logger = Logger(subsystem: "com.voxnotch", category: "HuggingFaceHubService")

  private init() {}

  // MARK: - Network Search

  /// Fetch MLX ASR models from multiple search queries in parallel, merged and deduped by ID.
  /// Throws `URLError` on network failure so callers can fall back to local results.
  func searchASRModels(query: String = "") async throws -> [HFModelInfo] {
    let endpoints: [URL] = buildEndpoints(query: query)

    let results = try await withThrowingTaskGroup(of: [HFModelInfo].self) { group in
      for url in endpoints {
        group.addTask { try await self.fetch(url: url) }
      }
      var all: [HFModelInfo] = []
      for try await batch in group {
        all += batch
      }
      return all
    }

    // Dedupe by id, preserving first occurrence. Exclude Parakeet repos —
    // they aren't MLX-compatible; Parakeet is available as a built-in model.
    var seen = Set<String>()
    return results.filter { model in
      guard model.family != .parakeet else { return false }
      return seen.insert(model.id).inserted
    }
  }

  // MARK: - Local Discovery

  /// Scan `~/.cache/huggingface/hub/mlx-audio/` for downloaded models.
  /// Returns synthetic `HFModelInfo` entries — no network required.
  nonisolated func discoverLocalModels() -> [HFModelInfo] {
    let cacheDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache/huggingface/hub/mlx-audio")

    let contents: [URL]
    do {
      contents = try FileManager.default.contentsOfDirectory(
        at: cacheDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    } catch {
      logger.error("Failed to list local HF cache directory: \(error)")
      return []
    }

    return contents.compactMap { url -> HFModelInfo? in
      guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
        return nil
      }
      let folderName = url.lastPathComponent
      // Folder name is "{org}_{model}" — convert back to "{org}/{model}"
      guard let slashIdx = folderName.firstIndex(of: "_") else { return nil }
      let repoID = folderName.replacingCharacters(
        in: slashIdx...slashIdx,
        with: "/"
      )
      guard repoID.contains("/") else { return nil }

      let sizeBytes = directorySize(at: url)

      // Build a synthetic HFModelInfo from local data
      do {
        return try JSONDecoder().decode(
          HFModelInfo.self,
          from: makeLocalJSON(repoID: repoID, size: Int(sizeBytes))
        )
      } catch {
        logger.error("Failed to decode local model info for \(repoID): \(error)")
        return nil
      }
    }
  }

  // MARK: - Private Helpers

  private func buildEndpoints(query: String) -> [URL] {
    let base = "https://huggingface.co/api/models"
    let trimmed = query.trimmingCharacters(in: .whitespaces)

    if !trimmed.isEmpty {
      // Single search for custom query
      let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
      let urlStr = "\(base)?search=\(encoded)&library=mlx&pipeline_tag=automatic-speech-recognition&full=true&limit=30"
      if let url = URL(string: urlStr) { return [url] }
      return []
    }

    // Default: parallel queries for MLX-compatible families. Parakeet is
    // excluded — it's handled by the built-in FluidAudio engine.
    let queries: [String] = [
      "\(base)?search=GLM-ASR&library=mlx&pipeline_tag=automatic-speech-recognition&full=true&limit=30",
      "\(base)?search=Qwen3-ASR&library=mlx&full=true&limit=30",
      "\(base)?search=Voxtral&library=mlx&pipeline_tag=automatic-speech-recognition&full=true&limit=30",
    ]
    return queries.compactMap { URL(string: $0) }
  }

  private func fetch(url: URL) async throws -> [HFModelInfo] {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    // Decode each model individually so one malformed entry doesn't drop the whole batch
    guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return try JSONDecoder().decode([HFModelInfo].self, from: data)
    }
    let decoder = JSONDecoder()
    return jsonArray.compactMap { dict in
      guard let itemData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
      return try? decoder.decode(HFModelInfo.self, from: itemData)
    }
  }

  private nonisolated func directorySize(at url: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else { return 0 }
    var size: Int64 = 0
    for case let fileURL as URL in enumerator {
      if let s = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        size += Int64(s)
      }
    }
    return size
  }

  private nonisolated func makeLocalJSON(repoID: String, size: Int) -> Data {
    // Build minimal JSON matching HFModelInfo's CodingKeys
    let json: [String: Any] = [
      "modelId": repoID,
      "siblings": [["rfilename": "model", "size": size]],
      "tags": [],
    ]
    return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
  }
}
