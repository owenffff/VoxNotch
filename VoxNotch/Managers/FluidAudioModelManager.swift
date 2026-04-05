//
//  FluidAudioModelManager.swift
//  VoxNotch
//
//  Manages FluidAudio ASR model downloads and lifecycle
//

import CryptoKit
import FluidAudio
import Foundation
import os.log

// MARK: - FluidAudio Model Version

/// Available FluidAudio ASR model versions
enum FluidAudioModelVersion: String, CaseIterable, Identifiable, Sendable {
  case v2English = "v2"
  case v3Multilingual = "v3"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .v2English: return "Parakeet v2 (English)"
    case .v3Multilingual: return "Parakeet v3 (Multilingual)"
    }
  }

  var supportedLanguages: [String] {
    switch self {
    case .v2English: return ["en"]
    case .v3Multilingual: return [
        "en", "zh", "ja", "ko", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "tr", "ar", "cs",
        "el", "fi", "hu", "id", "ro", "sk", "sv", "th", "uk", "vi",
      ]
    }
  }

  var estimatedSizeMB: Int {
    switch self {
    case .v2English: return 500
    case .v3Multilingual: return 800
    }
  }

  /// Convert to FluidAudio's AsrModelVersion
  var asrModelVersion: AsrModelVersion {
    switch self {
    case .v2English: return .v2
    case .v3Multilingual: return .v3
    }
  }
}

// MARK: - FluidAudio Model Manager

/// Manages FluidAudio model downloads and lifecycle
///
/// Thread Safety: uses dual protection —
/// • `lock` (NSLock) guards internal model references (`loadedModels`, `loadedVersion`)
///   that are read/written from async download tasks and background transcription providers.
/// • UI-observable state (`modelStates`, `downloadProgress`) is written via `MainActor.run`
///   from async methods; `refreshAllModelStates()` and `delete*()` must be called from MainActor.
@Observable
final class FluidAudioModelManager: @unchecked Sendable {

  // MARK: - Singleton

  static let shared = FluidAudioModelManager()

  // MARK: - Properties

  private let logger = Logger(subsystem: "com.voxnotch", category: "FluidAudioModelManager")

  /// Current state of each batch ASR model version
  private(set) var modelStates: [FluidAudioModelVersion: ModelDownloadState] = [:]

  /// Currently loaded ASR models
  private var loadedModels: AsrModels?

  /// Currently loaded model version
  private(set) var loadedVersion: FluidAudioModelVersion?

  /// Download progress (0.0 to 1.0)
  private(set) var downloadProgress: Double = 0

  /// Whether any model is ready (lock-protected — safe to call from any thread)
  var isReady: Bool {
    lock.withLock { loadedModels != nil }
  }

  /// Lock for thread safety
  private let lock = NSLock()

  // MARK: - Initialization

  private init() {
    for version in FluidAudioModelVersion.allCases {
      modelStates[version] = .notDownloaded
    }
    refreshAllModelStates()
  }

  // MARK: - Public Methods

  /// Download and load a model version
  /// - Parameter version: The model version to download and load
  /// - Returns: The loaded AsrModels
  @discardableResult
  func downloadAndLoad(version: FluidAudioModelVersion) async throws -> AsrModels {
    let (currentState, cachedModels, currentVersion) = lock.withLock {
      (modelStates[version], loadedModels, loadedVersion)
    }

    // Already ready, return cached models
    if currentState == .ready, let models = cachedModels, currentVersion == version {
      return models
    }

    // Already downloading, wait with timeout
    if case .downloading = currentState {
      logger.info("Model \(version.rawValue) already downloading, waiting...")
      let deadline = Date().addingTimeInterval(300) // 5-minute timeout
      while Date() < deadline {
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        let (state, models) = lock.withLock { (modelStates[version], loadedModels) }
        if case .ready = state, let models {
          return models
        }
        if case .failed(let message) = state {
          throw FluidAudioError.modelDownloadFailed(message)
        }
      }
      throw FluidAudioError.modelDownloadFailed("Download timed out after 5 minutes")
    }

    // Start download
    await MainActor.run {
      modelStates[version] = .downloading(progress: 0, downloadedBytes: 0, totalBytes: Int64(version.estimatedSizeMB) * 1_000_000, speedBytesPerSecond: 0)
      downloadProgress = 0
    }

    logger.info("Starting download for FluidAudio model: \(version.rawValue)")

    do {
      // Download and load models using FluidAudio API
      let models = try await AsrModels.downloadAndLoad(version: version.asrModelVersion)

      // Verify integrity against saved manifest, or create one for first download
      if !verifyChecksumManifest(for: version) {
        await MainActor.run {
          modelStates[version] = .failed(message: "Model files corrupted (checksum mismatch)")
        }
        logger.error("Checksum verification failed for \(version.rawValue)")
        throw FluidAudioError.modelDownloadFailed("Model files corrupted (checksum mismatch)")
      }
      saveChecksumManifest(for: version)

      lock.withLock {
        loadedModels = models
        loadedVersion = version
      }

      await MainActor.run {
        modelStates[version] = .ready
        downloadProgress = 1.0
      }

      logger.info("FluidAudio model \(version.rawValue) loaded successfully")
      return models

    } catch {
      let errorMessage = error.localizedDescription
      await MainActor.run {
        modelStates[version] = .failed(message: errorMessage)
      }
      logger.error("Failed to download FluidAudio model: \(errorMessage)")
      throw FluidAudioError.modelDownloadFailed(errorMessage)
    }
  }

  /// Get loaded models if available
  func getLoadedModels() -> AsrModels? {
    return lock.withLock { loadedModels }
  }

  /// Check if a specific version is ready
  func isVersionReady(_ version: FluidAudioModelVersion) -> Bool {
    return lock.withLock { modelStates[version]?.isReady ?? false }
  }

  /// Unload current models to free memory
  func unloadModels() {
    let previousVersion: FluidAudioModelVersion? = lock.withLock {
      loadedModels = nil
      let v = loadedVersion
      loadedVersion = nil
      return v
    }
    if let version = previousVersion {
      Task { @MainActor in
        modelStates[version] = .downloaded
      }
    }
    logger.info("Unloaded FluidAudio models")
  }

  /// Get recommended model version for a language
  func recommendedVersion(for language: String) -> FluidAudioModelVersion {
    let normalizedLang = language.lowercased().prefix(2)
    if normalizedLang == "en" {
      return .v2English
    }
    return .v3Multilingual
  }

  // MARK: - Model State Refresh

  /// Check filesystem for all model types and update states without downloading.
  /// Must be called from MainActor (writes UI-observable `modelStates`).
  func refreshAllModelStates() {
    let (currentLoadedVersion, hasLoadedModels) = lock.withLock {
      (loadedVersion, loadedModels != nil)
    }
    for version in FluidAudioModelVersion.allCases {
      let isDownloaded = isVersionDownloaded(version)
      if isDownloaded {
        // If loaded in memory, mark ready; otherwise just downloaded
        if currentLoadedVersion == version && hasLoadedModels {
          modelStates[version] = .ready
        } else {
          modelStates[version] = .downloaded
        }
      } else if !(modelStates[version]?.isDownloading ?? false) {
        modelStates[version] = .notDownloaded
      }
    }
  }

  // MARK: - Readiness Queries

  /// Check if a specific batch ASR version is downloaded on disk
  func isVersionDownloaded(_ version: FluidAudioModelVersion) -> Bool {
    let cacheDir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
    return AsrModels.modelsExist(at: cacheDir, version: version.asrModelVersion)
  }

  /// Whether Quick Dictation models are ready (batch ASR model is downloaded)
  func quickDictationModelsReady() -> Bool {
    let settings = SettingsManager.shared
    let language = settings.transcriptionLanguage
    let version = recommendedVersion(for: language == "auto" ? "en" : language)
    return isVersionDownloaded(version)
  }

  /// Human-readable description of missing models
  func missingModelsDescription() -> String {
    var missing: [String] = []

    let settings = SettingsManager.shared
    let language = settings.transcriptionLanguage
    let version = recommendedVersion(for: language == "auto" ? "en" : language)
    if !isVersionDownloaded(version) {
      missing.append("Speech Model (\(version.displayName))")
    }

    if missing.isEmpty {
      return "All models downloaded"
    }
    return "Missing: \(missing.joined(separator: ", "))"
  }

  // MARK: - Download Methods (for Settings UI)

  /// Download batch ASR model only (called from Settings)
  func downloadBatchModel(version: FluidAudioModelVersion) async throws {
    await MainActor.run {
      modelStates[version] = .downloading(progress: 0, downloadedBytes: 0, totalBytes: Int64(version.estimatedSizeMB) * 1_000_000, speedBytesPerSecond: 0)
      downloadProgress = 0
    }

    logger.info("Downloading batch ASR model: \(version.rawValue)")

    do {
      let cacheDir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
      let expectedBytes = Int64(version.estimatedSizeMB) * 1_000_000
      let pollingTask = DownloadProgressTracker.poll(
        directory: cacheDir,
        expectedBytes: expectedBytes
      ) { [weak self] progress, downloadedBytes, totalBytes, speed in
        guard let self else { return }
        if case .downloading = self.modelStates[version] {
          self.modelStates[version] = .downloading(
            progress: progress, downloadedBytes: downloadedBytes,
            totalBytes: totalBytes, speedBytesPerSecond: speed
          )
          self.downloadProgress = progress
        }
      }
      defer { pollingTask.cancel() }

      let models = try await AsrModels.downloadAndLoad(version: version.asrModelVersion)

      // Verify integrity against saved manifest, or create one for first download
      if !verifyChecksumManifest(for: version) {
        await MainActor.run {
          modelStates[version] = .failed(message: "Model files corrupted (checksum mismatch)")
        }
        logger.error("Checksum verification failed for \(version.rawValue)")
        throw FluidAudioError.modelDownloadFailed("Model files corrupted (checksum mismatch)")
      }
      saveChecksumManifest(for: version)

      lock.withLock {
        loadedModels = models
        loadedVersion = version
      }

      await MainActor.run {
        modelStates[version] = .ready
        downloadProgress = 1.0
      }

      logger.info("Batch ASR model \(version.rawValue) downloaded and loaded")
    } catch {
      let errorMessage = error.localizedDescription
      await MainActor.run {
        modelStates[version] = .failed(message: errorMessage)
      }
      logger.error("Failed to download batch ASR model: \(errorMessage)")
      throw FluidAudioError.modelDownloadFailed(errorMessage)
    }
  }

  // MARK: - Delete Methods

  /// Delete batch ASR model files.
  /// Must be called from MainActor (writes UI-observable `modelStates`).
  func deleteBatchModel(version: FluidAudioModelVersion) throws {
    // Atomically check and unload if currently loaded
    lock.withLock {
      if loadedVersion == version {
        loadedModels = nil
        loadedVersion = nil
      }
    }

    let cacheDir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
    if FileManager.default.fileExists(atPath: cacheDir.path) {
      try FileManager.default.removeItem(at: cacheDir)
    }

    modelStates[version] = .notDownloaded
    logger.info("Deleted batch ASR model: \(version.rawValue)")
  }

  /// Delete all downloaded models
  func deleteAllModels() throws {
    var errors: [String] = []
    for version in FluidAudioModelVersion.allCases {
      do {
        try deleteBatchModel(version: version)
      } catch {
        errors.append("\(version.rawValue): \(error.localizedDescription)")
      }
    }
    if !errors.isEmpty {
      logger.error("Some models failed to delete: \(errors.joined(separator: "; "))")
    }
    logger.info("Deleted all models")
  }

  /// Calculate total storage used by all downloaded models
  func totalStorageUsedBytes() -> Int64 {
    var total: Int64 = 0
    for version in FluidAudioModelVersion.allCases {
      let dir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
      total += DownloadProgressTracker.directorySize(at: dir)
    }
    return total
  }

  // MARK: - Integrity Verification

  /// Compute SHA256 of a single file using chunked reads (safe for large model files)
  private func sha256(of url: URL) -> String? {
    guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? fileHandle.close() }

    var hasher = SHA256()
    let chunkSize = 4 * 1024 * 1024 // 4 MB

    while autoreleasepool(invoking: {
      guard let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
        return false
      }
      hasher.update(data: chunk)
      return true
    }) {}

    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// Build a checksum manifest for all files in a model directory.
  /// Returns a dictionary of relative-path → SHA256.
  private func buildManifest(for directory: URL) -> [String: String] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else { return [:] }

    var manifest: [String: String] = [:]
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
            values.isRegularFile == true,
            fileURL.lastPathComponent != ".voxnotch_checksums.json"
      else { continue }

      if let hash = sha256(of: fileURL) {
        let relativePath = fileURL.path.replacingOccurrences(of: directory.path + "/", with: "")
        manifest[relativePath] = hash
      }
    }
    return manifest
  }

  /// Save a checksum manifest alongside the model directory for future verification.
  func saveChecksumManifest(for version: FluidAudioModelVersion) {
    let cacheDir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
    let manifest = buildManifest(for: cacheDir)
    guard !manifest.isEmpty else { return }

    let manifestURL = cacheDir.appendingPathComponent(".voxnotch_checksums.json")
    do {
      let data = try JSONEncoder().encode(manifest)
      try data.write(to: manifestURL, options: .atomic)
      logger.info("Saved checksum manifest for \(version.rawValue) (\(manifest.count) files)")
    } catch {
      logger.error("Failed to save checksum manifest for \(version.rawValue): \(error)")
    }
  }

  /// Verify a downloaded model's files against its saved checksum manifest.
  /// Returns true if no manifest exists (first download) or all checksums match.
  func verifyChecksumManifest(for version: FluidAudioModelVersion) -> Bool {
    let cacheDir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
    let manifestURL = cacheDir.appendingPathComponent(".voxnotch_checksums.json")

    let data: Data
    do {
      data = try Data(contentsOf: manifestURL)
    } catch {
      return true // No manifest yet — trust first download
    }
    let savedManifest: [String: String]
    do {
      savedManifest = try JSONDecoder().decode([String: String].self, from: data)
    } catch {
      logger.error("Failed to decode checksum manifest for \(version.rawValue): \(error)")
      return false // Corrupted manifest — treat as verification failure
    }

    let currentManifest = buildManifest(for: cacheDir)

    for (path, expectedHash) in savedManifest {
      guard let actualHash = currentManifest[path] else {
        logger.error("Checksum verification failed: missing file \(path)")
        return false
      }
      if actualHash != expectedHash {
        logger.error("Checksum verification failed: \(path) hash mismatch")
        return false
      }
    }

    return true
  }

}

// MARK: - FluidAudio Errors

enum FluidAudioError: LocalizedError {
  case modelNotLoaded
  case modelDownloadFailed(String)
  case transcriptionFailed(String)
  case invalidAudioFormat

  var errorDescription: String? {
    switch self {
    case .modelNotLoaded:
      return "Speech model not loaded"
    case .modelDownloadFailed:
      return "Model download failed"
    case .transcriptionFailed:
      return "Transcription failed"
    case .invalidAudioFormat:
      return "Audio format not supported"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .modelNotLoaded:
      return "Open Settings → Speech Model to download"
    case .modelDownloadFailed:
      return "Check your connection and try again"
    case .transcriptionFailed:
      return "Try again — or switch models in Settings"
    case .invalidAudioFormat:
      return "Try recording again"
    }
  }
}
