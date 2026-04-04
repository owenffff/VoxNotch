//
//  FluidAudioModelManager.swift
//  VoxNotch
//
//  Manages FluidAudio ASR model downloads and lifecycle
//

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

// MARK: - Model State

/// State of a FluidAudio model
enum FluidAudioModelState: Equatable, Sendable {
  case notDownloaded
  case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64, speedBytesPerSecond: Double)
  case downloaded
  case loading
  case ready
  case failed(message: String)

  var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  var isDownloading: Bool {
    if case .downloading = self { return true }
    return false
  }
}

// MARK: - FluidAudio Model Manager

/// Manages FluidAudio model downloads and lifecycle
@Observable
final class FluidAudioModelManager: @unchecked Sendable {

  // MARK: - Singleton

  static let shared = FluidAudioModelManager()

  // MARK: - Properties

  private let logger = Logger(subsystem: "com.voxnotch", category: "FluidAudioModelManager")

  /// Current state of each batch ASR model version
  private(set) var modelStates: [FluidAudioModelVersion: FluidAudioModelState] = [:]

  /// Streaming model states per chunk size variant
  private(set) var streamingModelStates: [String: FluidAudioModelState] = [
    "160ms": .notDownloaded, "320ms": .notDownloaded,
  ]

  /// Diarization model state
  private(set) var diarizationModelState: FluidAudioModelState = .notDownloaded

  /// Currently loaded ASR models
  private var loadedModels: AsrModels?

  /// Currently loaded model version
  private(set) var loadedVersion: FluidAudioModelVersion?

  /// Download progress (0.0 to 1.0)
  private(set) var downloadProgress: Double = 0

  /// Whether any model is ready
  var isReady: Bool {
    loadedModels != nil
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
    let currentState = lock.withLock { modelStates[version] }

    // Already ready, return cached models
    if currentState == .ready, let models = loadedModels, loadedVersion == version {
      return models
    }

    // Already downloading, wait with timeout
    if case .downloading = currentState {
      logger.info("Model \(version.rawValue) already downloading, waiting...")
      let deadline = Date().addingTimeInterval(300) // 5-minute timeout
      while Date() < deadline {
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        let state = lock.withLock { modelStates[version] }
        if case .ready = state, let models = loadedModels {
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

  /// Get the model directory for streaming ASR models
  /// - Parameter chunkSize: The streaming chunk size (determines which model variant to use)
  /// - Returns: URL to the streaming model directory
  func getStreamingModelDirectory(for chunkSize: StreamingChunkSize) -> URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!

    let repo: Repo = (chunkSize == .ms160) ? .parakeetEou160 : .parakeetEou320
    return appSupport
      .appendingPathComponent("FluidAudio", isDirectory: true)
      .appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent(repo.folderName, isDirectory: true)
  }

  /// Download streaming ASR models for a specific chunk size
  /// - Parameter chunkSize: The streaming chunk size
  /// - Returns: URL to the downloaded model directory
  func downloadStreamingModels(for chunkSize: StreamingChunkSize) async throws -> URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!

    let modelsDir = appSupport
      .appendingPathComponent("FluidAudio", isDirectory: true)
      .appendingPathComponent("Models", isDirectory: true)

    let repo: Repo = (chunkSize == .ms160) ? .parakeetEou160 : .parakeetEou320

    logger.info("Downloading streaming models for chunk size: \(chunkSize.durationMs)ms")

    // Use downloadRepo (download only) instead of loadModels, because
    // requiredModels includes vocab.json which is a flat file, not an
    // MLModel directory. StreamingEouAsrManager.loadModels() handles
    // loading the individual models and vocab file correctly.
    try await DownloadUtils.downloadRepo(repo, to: modelsDir)

    let modelDir = modelsDir.appendingPathComponent(repo.folderName)
    logger.info("Streaming models downloaded to: \(modelDir.path)")
    return modelDir
  }

  /// Check if streaming models exist for a chunk size
  func streamingModelsExist(for chunkSize: StreamingChunkSize) -> Bool {
    let modelDir = getStreamingModelDirectory(for: chunkSize)
    let requiredModels = ModelNames.ParakeetEOU.requiredModels

    return requiredModels.allSatisfy { model in
      let modelPath = modelDir.appendingPathComponent(model)
      return FileManager.default.fileExists(atPath: modelPath.path)
    }
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

  /// Check filesystem for all model types and update states without downloading
  func refreshAllModelStates() {
    // Check batch ASR models
    for version in FluidAudioModelVersion.allCases {
      let isDownloaded = isVersionDownloaded(version)
      if isDownloaded {
        // If loaded in memory, mark ready; otherwise just downloaded
        if loadedVersion == version && loadedModels != nil {
          modelStates[version] = .ready
        } else {
          modelStates[version] = .downloaded
        }
      } else if !(modelStates[version]?.isDownloading ?? false) {
        modelStates[version] = .notDownloaded
      }
    }

    // Check streaming models
    for chunkKey in ["160ms", "320ms"] {
      let chunkSize: StreamingChunkSize = (chunkKey == "160ms") ? .ms160 : .ms320
      let exists = streamingModelsExist(for: chunkSize)
      if exists {
        streamingModelStates[chunkKey] = .downloaded
      } else if !(streamingModelStates[chunkKey]?.isDownloading ?? false) {
        streamingModelStates[chunkKey] = .notDownloaded
      }
    }

    // Check diarization models
    let diarizationExists = diarizationModelsExist()
    if diarizationExists {
      diarizationModelState = .downloaded
    } else if !diarizationModelState.isDownloading {
      diarizationModelState = .notDownloaded
    }
  }

  // MARK: - Readiness Queries

  /// Check if a specific batch ASR version is downloaded on disk
  func isVersionDownloaded(_ version: FluidAudioModelVersion) -> Bool {
    let cacheDir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
    return AsrModels.modelsExist(at: cacheDir, version: version.asrModelVersion)
  }

  /// Check if diarization models exist on disk
  func diarizationModelsExist() -> Bool {
    let modelsDir = diarizationModelsDirectory()
    let requiredModels = ModelNames.OfflineDiarizer.requiredModels

    return requiredModels.allSatisfy { model in
      let modelPath = modelsDir.appendingPathComponent(model)
      return FileManager.default.fileExists(atPath: modelPath.path)
    }
  }

  /// Get the diarization models directory
  private func diarizationModelsDirectory() -> URL {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    return appSupport
      .appendingPathComponent("FluidAudio", isDirectory: true)
      .appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
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
      /// Poll directory size every 2s to show progress without excessive I/O
      let cacheDir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
      let expectedBytes = Int64(version.estimatedSizeMB) * 1_000_000
      let pollingTask = Task {
        var lastBytes: Int64 = 0
        var lastTime = Date()

        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          let current = directorySize(at: cacheDir)
          guard current > 0, expectedBytes > 0 else { continue }
          
          let now = Date()
          let timeDiff = now.timeIntervalSince(lastTime)
          let bytesDiff = current - lastBytes
          let speed = timeDiff > 0 ? Double(bytesDiff) / timeDiff : 0
          
          lastBytes = current
          lastTime = now
          
          let p = min(Double(current) / Double(expectedBytes), 0.95)
          await MainActor.run {
            if case .downloading = self.modelStates[version] {
              self.modelStates[version] = .downloading(progress: p, downloadedBytes: current, totalBytes: expectedBytes, speedBytesPerSecond: speed)
              self.downloadProgress = p
            }
          }
        }
      }
      defer { pollingTask.cancel() }

      let models = try await AsrModels.downloadAndLoad(version: version.asrModelVersion)

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

  /// Download streaming models for a specific chunk size (called from Settings)
  func downloadStreamingModelsManual(for chunkSize: StreamingChunkSize) async throws {
    let chunkKey = (chunkSize == .ms160) ? "160ms" : "320ms"

    await MainActor.run {
      streamingModelStates[chunkKey] = .downloading(progress: 0, downloadedBytes: 0, totalBytes: 120_000_000, speedBytesPerSecond: 0)
    }

    logger.info("Downloading streaming models for chunk size: \(chunkKey)")

    do {
      /// Poll directory size every 2s to show progress without excessive I/O
      let modelDir = getStreamingModelDirectory(for: chunkSize)
      let expectedBytes: Int64 = 120_000_000
      let pollingTask = Task {
        var lastBytes: Int64 = 0
        var lastTime = Date()

        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          let current = directorySize(at: modelDir)
          guard current > 0 else { continue }
          
          let now = Date()
          let timeDiff = now.timeIntervalSince(lastTime)
          let bytesDiff = current - lastBytes
          let speed = timeDiff > 0 ? Double(bytesDiff) / timeDiff : 0
          
          lastBytes = current
          lastTime = now
          
          let p = min(Double(current) / Double(expectedBytes), 0.95)
          await MainActor.run {
            if self.streamingModelStates[chunkKey]?.isDownloading == true {
              self.streamingModelStates[chunkKey] = .downloading(progress: p, downloadedBytes: current, totalBytes: expectedBytes, speedBytesPerSecond: speed)
            }
          }
        }
      }
      defer { pollingTask.cancel() }

      _ = try await downloadStreamingModels(for: chunkSize)

      await MainActor.run {
        streamingModelStates[chunkKey] = .downloaded
      }

      logger.info("Streaming models downloaded for \(chunkKey)")
    } catch {
      let errorMessage = error.localizedDescription
      await MainActor.run {
        streamingModelStates[chunkKey] = .failed(message: errorMessage)
      }
      logger.error("Failed to download streaming models: \(errorMessage)")
      throw FluidAudioError.modelDownloadFailed(errorMessage)
    }
  }

  /// Convenience overload accepting a chunk size string ("160ms" or "320ms")
  func downloadStreamingModelsManual(forKey chunkKey: String) async throws {
    let chunkSize: StreamingChunkSize = (chunkKey == "160ms") ? .ms160 : .ms320
    try await downloadStreamingModelsManual(for: chunkSize)
  }

  /// Download diarization models (called from Settings)
  func downloadDiarizationModels() async throws {
    await MainActor.run {
      diarizationModelState = .downloading(progress: 0, downloadedBytes: 0, totalBytes: 50_000_000, speedBytesPerSecond: 0)
    }

    logger.info("Downloading diarization models...")

    do {
      // We don't have a good way to poll diarization model size during download
      // as it's handled internally by OfflineDiarizerManager, so we just show indeterminate progress
      let diarizer = OfflineDiarizerManager()
      try await diarizer.prepareModels()

      await MainActor.run {
        diarizationModelState = .downloaded
      }

      logger.info("Diarization models downloaded")
    } catch {
      let errorMessage = error.localizedDescription
      await MainActor.run {
        diarizationModelState = .failed(message: errorMessage)
      }
      logger.error("Failed to download diarization models: \(errorMessage)")
      throw FluidAudioError.modelDownloadFailed(errorMessage)
    }
  }

  // MARK: - Delete Methods

  /// Delete batch ASR model files
  func deleteBatchModel(version: FluidAudioModelVersion) throws {
    // Unload if currently loaded
    if loadedVersion == version {
      lock.withLock {
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

  /// Delete streaming model files for a chunk size
  func deleteStreamingModels(for chunkSize: StreamingChunkSize) throws {
    let modelDir = getStreamingModelDirectory(for: chunkSize)
    let chunkKey = (chunkSize == .ms160) ? "160ms" : "320ms"

    if FileManager.default.fileExists(atPath: modelDir.path) {
      try FileManager.default.removeItem(at: modelDir)
    }

    streamingModelStates[chunkKey] = .notDownloaded
    logger.info("Deleted streaming models: \(chunkKey)")
  }

  /// Convenience overload accepting a chunk size string ("160ms" or "320ms")
  func deleteStreamingModels(forKey chunkKey: String) throws {
    let chunkSize: StreamingChunkSize = (chunkKey == "160ms") ? .ms160 : .ms320
    try deleteStreamingModels(for: chunkSize)
  }

  /// Delete diarization model files
  func deleteDiarizationModels() throws {
    let modelDir = diarizationModelsDirectory()

    if FileManager.default.fileExists(atPath: modelDir.path) {
      try FileManager.default.removeItem(at: modelDir)
    }

    diarizationModelState = .notDownloaded
    logger.info("Deleted diarization models")
  }

  /// Delete all downloaded models
  func deleteAllModels() throws {
    for version in FluidAudioModelVersion.allCases {
      try? deleteBatchModel(version: version)
    }
    try? deleteStreamingModels(for: .ms160)
    try? deleteStreamingModels(for: .ms320)
    try? deleteDiarizationModels()

    logger.info("Deleted all models")
  }

  /// Calculate total storage used by all downloaded models
  func totalStorageUsedBytes() -> Int64 {
    var total: Int64 = 0

    for version in FluidAudioModelVersion.allCases {
      let dir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
      total += directorySize(at: dir)
    }

    for chunkSize in [StreamingChunkSize.ms160, .ms320] {
      let dir = getStreamingModelDirectory(for: chunkSize)
      total += directorySize(at: dir)
    }

    total += directorySize(at: diarizationModelsDirectory())

    return total
  }

  /// Calculate size of a directory in bytes
  private func directorySize(at url: URL) -> Int64 {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path) else { return 0 }

    guard let enumerator = fileManager.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else { return 0 }

    var size: Int64 = 0
    for case let fileURL as URL in enumerator {
      if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        size += Int64(fileSize)
      }
    }
    return size
  }
}

// MARK: - FluidAudio Errors

enum FluidAudioError: LocalizedError {
  case modelNotLoaded
  case modelDownloadFailed(String)
  case transcriptionFailed(String)
  case vadFailed(String)
  case streamingNotSupported
  case streamingModelsNotDownloaded
  case diarizationModelsNotDownloaded
  case invalidAudioFormat

  var errorDescription: String? {
    switch self {
    case .modelNotLoaded:
      return "FluidAudio model not loaded"
    case .modelDownloadFailed(let message):
      return "Model download failed: \(message)"
    case .transcriptionFailed(let message):
      return "Transcription failed: \(message)"
    case .vadFailed(let message):
      return "Voice activity detection failed: \(message)"
    case .streamingNotSupported:
      return "Streaming transcription not supported"
    case .streamingModelsNotDownloaded:
      return "Streaming models not downloaded. Open Settings to download."
    case .diarizationModelsNotDownloaded:
      return "Diarization models not downloaded. Open Settings to download."
    case .invalidAudioFormat:
      return "Invalid audio format - expected 16kHz mono Float32"
    }
  }
}
