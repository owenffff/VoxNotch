//
//  ModelDownloadManager.swift
//  VoxNotch
//
//  Manages ML model downloads with progress tracking, cancellation, and resumption
//

import Foundation
import os.log

#if canImport(Speech)
import Speech
#endif

/// Available Whisper speech-to-text models with their metadata
/// NOTE: These are for future SwamaKit support (currently parked)
/// Renamed to avoid conflict with LegacyWhisperModel in Models/LegacyWhisperModel.swift
enum LegacyWhisperModel: String, CaseIterable, Identifiable {
  case whisperTiny = "whisper-tiny"
  case whisperBase = "whisper-base"
  case whisperSmall = "whisper-small"
  case whisperMedium = "whisper-medium"
  case whisperLarge = "whisper-large"
  case funasrParaformer = "funasr-paraformer"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .whisperTiny: return "Whisper Tiny"
    case .whisperBase: return "Whisper Base"
    case .whisperSmall: return "Whisper Small"
    case .whisperMedium: return "Whisper Medium"
    case .whisperLarge: return "Whisper Large"
    case .funasrParaformer: return "FunASR Paraformer"
    }
  }

  /// Approximate download size in bytes
  var downloadSize: Int64 {
    switch self {
    case .whisperTiny: return 39 * 1024 * 1024       // 39 MB
    case .whisperBase: return 74 * 1024 * 1024       // 74 MB
    case .whisperSmall: return 244 * 1024 * 1024     // 244 MB
    case .whisperMedium: return 769 * 1024 * 1024    // 769 MB
    case .whisperLarge: return 3 * 1024 * 1024 * 1024 // 3 GB
    case .funasrParaformer: return 840 * 1024 * 1024 // 840 MB
    }
  }

  var downloadSizeFormatted: String {
    ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
  }

  /// Expected SHA256 checksum for integrity verification
  /// NOTE: These are placeholder values - replace with actual checksums
  var expectedChecksum: String? {
    // TODO: Add actual checksums when model URLs are finalized
    nil
  }

  /// Model download URL
  /// NOTE: These are placeholder URLs - replace with actual model hosting URLs
  var downloadURL: URL? {
    // TODO: Replace with actual model hosting URLs (Hugging Face, etc.)
    // Example: URL(string: "https://huggingface.co/openai/whisper-tiny/resolve/main/model.bin")
    nil
  }
}

/// Download state for a model (legacy, used by ModelDownloadManager)
/// Note: There's a simpler ModelDownloadState in SettingsView.swift for UI
enum LegacyModelDownloadState: Equatable {
  case notDownloaded
  case downloading(progress: Double)
  case paused(resumeData: Data?)
  case verifying
  case downloaded
  case failed(message: String)

  var isDownloading: Bool {
    if case .downloading = self {
      return true
    }
    return false
  }
}

/// Error types for model download operations
enum ModelDownloadError: LocalizedError {
  case noDownloadURL
  case networkError(Error)
  case fileSystemError(Error)
  case checksumMismatch
  case cancelled
  case insufficientSpace(required: Int64, available: Int64)

  var errorDescription: String? {
    switch self {
    case .noDownloadURL:
      return "Download URL not available for this model"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .fileSystemError(let error):
      return "File system error: \(error.localizedDescription)"
    case .checksumMismatch:
      return "Downloaded file is corrupted (checksum mismatch)"
    case .cancelled:
      return "Download was cancelled"
    case .insufficientSpace(let required, let available):
      let requiredStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
      let availableStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
      return "Insufficient disk space. Required: \(requiredStr), Available: \(availableStr)"
    }
  }
}

/// Manages downloading, storing, and tracking ML models
@Observable
final class ModelDownloadManager {

  // MARK: - Properties

  static let shared = ModelDownloadManager()

  /// Current download states for all models
  private(set) var downloadStates: [LegacyWhisperModel: LegacyModelDownloadState] = [:]

  /// Currently active download tasks
  private var downloadTasks: [LegacyWhisperModel: URLSessionDownloadTask] = [:]

  /// Resume data for paused downloads
  private var resumeDataStore: [LegacyWhisperModel: Data] = [:]

  /// Models directory URL
  let modelsDirectory: URL

  /// Download delegate for progress tracking
  private let downloadDelegate = ModelDownloadDelegate()

  /// URLSession for downloads (initialized lazily via nonisolated helper)
  @ObservationIgnored
  private var _session: URLSession?
  private var session: URLSession {
    if let existing = _session {
      return existing
    }
    let config = URLSessionConfiguration.default
    config.allowsCellularAccess = true
    config.waitsForConnectivity = true
    let newSession = URLSession(configuration: config, delegate: downloadDelegate, delegateQueue: nil)
    _session = newSession
    return newSession
  }

  // MARK: - Initialization

  private init() {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let appDir = appSupport.appendingPathComponent("VoxNotch", isDirectory: true)
    self.modelsDirectory = appDir.appendingPathComponent("Models", isDirectory: true)

    /// Create directory if needed
    try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

    /// Initialize download states
    refreshDownloadStates()

    /// Set up delegate callback
    downloadDelegate.onProgress = { [weak self] (model: LegacyWhisperModel, progress: Double) in
      Task { @MainActor in
        self?.downloadStates[model] = .downloading(progress: progress)
      }
    }

    downloadDelegate.onComplete = { [weak self] (model: LegacyWhisperModel, location: URL?, error: Error?) in
      Task { @MainActor in
        await self?.handleDownloadComplete(model: model, location: location, error: error)
      }
    }
  }

  // MARK: - Public Methods

  /// Check if a model is downloaded
  func isModelDownloaded(_ model: LegacyWhisperModel) -> Bool {
    let modelPath = modelPath(for: model)
    return FileManager.default.fileExists(atPath: modelPath.path)
  }

  /// Get the local path for a model
  func modelPath(for model: LegacyWhisperModel) -> URL {
    modelsDirectory.appendingPathComponent(model.rawValue)
  }

  /// Refresh download states based on file system
  func refreshDownloadStates() {
    for model in LegacyWhisperModel.allCases {
      if isModelDownloaded(model) {
        downloadStates[model] = .downloaded
      } else if let resumeData = resumeDataStore[model] {
        downloadStates[model] = .paused(resumeData: resumeData)
      } else {
        downloadStates[model] = .notDownloaded
      }
    }
  }

  /// Start downloading a model
  func startDownload(model: LegacyWhisperModel) async throws {
    guard let url = model.downloadURL else {
      throw ModelDownloadError.noDownloadURL
    }

    /// Check available disk space
    try checkDiskSpace(for: model)

    /// Check for resume data
    if let resumeData = resumeDataStore[model] {
      let task = session.downloadTask(withResumeData: resumeData)
      downloadTasks[model] = task
      downloadDelegate.registerTask(task, for: model)
      task.resume()
    } else {
      let task = session.downloadTask(with: url)
      downloadTasks[model] = task
      downloadDelegate.registerTask(task, for: model)
      task.resume()
    }

    await MainActor.run {
      downloadStates[model] = .downloading(progress: 0)
    }
  }

  /// Cancel an active download
  func cancelDownload(model: LegacyWhisperModel) {
    guard let task = downloadTasks[model] else {
      return
    }

    task.cancel { [weak self] resumeData in
      self?.resumeDataStore[model] = resumeData
      Task { @MainActor in
        if let resumeData {
          self?.downloadStates[model] = .paused(resumeData: resumeData)
        } else {
          self?.downloadStates[model] = .notDownloaded
        }
      }
    }

    downloadTasks[model] = nil
  }

  /// Delete a downloaded model
  func deleteModel(_ model: LegacyWhisperModel) throws {
    let path = modelPath(for: model)

    guard FileManager.default.fileExists(atPath: path.path) else {
      return
    }

    try FileManager.default.removeItem(at: path)
    downloadStates[model] = .notDownloaded
  }

  /// Get available disk space
  func availableDiskSpace() -> Int64? {
    let fileURL = URL(fileURLWithPath: NSHomeDirectory())
    do {
      let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      return values.volumeAvailableCapacityForImportantUsage
    } catch {
      return nil
    }
  }

  // MARK: - Private Methods

  private func checkDiskSpace(for model: LegacyWhisperModel) throws {
    guard let available = availableDiskSpace() else {
      return
    }

    let required = model.downloadSize
    /// Require 20% buffer
    let requiredWithBuffer = Int64(Double(required) * 1.2)

    if available < requiredWithBuffer {
      throw ModelDownloadError.insufficientSpace(required: requiredWithBuffer, available: available)
    }
  }

  private func handleDownloadComplete(model: LegacyWhisperModel, location: URL?, error: Error?) async {
    downloadTasks[model] = nil
    resumeDataStore[model] = nil

    if let error {
      downloadStates[model] = .failed(message: error.localizedDescription)
      return
    }

    guard let location else {
      downloadStates[model] = .failed(message: "Download completed but file not found")
      return
    }

    downloadStates[model] = .verifying

    /// Verify checksum if available
    if let expectedChecksum = model.expectedChecksum {
      let actualChecksum = await calculateChecksum(for: location)
      if actualChecksum != expectedChecksum {
        downloadStates[model] = .failed(message: ModelDownloadError.checksumMismatch.localizedDescription)
        try? FileManager.default.removeItem(at: location)
        return
      }
    }

    /// Move to final location
    let destination = modelPath(for: model)
    do {
      /// Remove existing file if present
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: location, to: destination)
      downloadStates[model] = .downloaded
    } catch {
      downloadStates[model] = .failed(message: error.localizedDescription)
    }
  }

  private func calculateChecksum(for url: URL) async -> String? {
    /// SHA256 checksum calculation
    guard (try? Data(contentsOf: url)) != nil else {
      return nil
    }

    /// Use CryptoKit for checksum
    // TODO: Implement chunked SHA256 for large model files using CryptoKit
    /// For now, return nil to skip verification (checksums not yet defined)
    return nil
  }
}

// MARK: - Download Delegate

/// Delegate for tracking download progress
private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {

  /// Map task identifiers to models
  private var taskModelMap: [Int: LegacyWhisperModel] = [:]

  /// Progress callback
  var onProgress: ((LegacyWhisperModel, Double) -> Void)?

  /// Completion callback
  var onComplete: ((LegacyWhisperModel, URL?, Error?) -> Void)?

  func registerTask(_ task: URLSessionDownloadTask, for model: LegacyWhisperModel) {
    taskModelMap[task.taskIdentifier] = model
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let model = taskModelMap[downloadTask.taskIdentifier] else {
      return
    }

    let progress: Double
    if totalBytesExpectedToWrite > 0 {
      progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    } else {
      progress = 0
    }

    onProgress?(model, progress)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let model = taskModelMap[downloadTask.taskIdentifier] else {
      return
    }

    /// Copy file to temp location before callback since original will be deleted
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.copyItem(at: location, to: tempURL)

    taskModelMap[downloadTask.taskIdentifier] = nil
    onComplete?(model, tempURL, nil)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let model = taskModelMap[task.taskIdentifier],
          let error
    else {
      return
    }

    taskModelMap[task.taskIdentifier] = nil
    onComplete?(model, nil, error)
  }
}

// MARK: - Apple Language Model Manager

/// Manages Apple SpeechAnalyzer language model downloads (macOS 26+)
@Observable
final class AppleLanguageModelManager {

  // MARK: - Types

  /// Status of a locale's language model
  enum LocaleStatus: Sendable, Equatable {
    case checking
    case installed
    case available
    case downloading(progress: Double)
    case unsupported
    case failed(message: String)
  }

  /// A locale with its display info
  struct LocaleInfo: Identifiable, Sendable {
    let locale: Locale
    var status: LocaleStatus

    var id: String { locale.identifier }

    var displayName: String {
      locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    var languageName: String {
      locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? "") ?? locale.identifier
    }
  }

  // MARK: - Properties

  static let shared = AppleLanguageModelManager()

  private let logger = Logger(subsystem: "com.voxnotch", category: "AppleLanguageModelManager")

  /// Available locales with their status
  private(set) var locales: [LocaleInfo] = []

  /// Currently downloading locales
  private var downloadingLocales: Set<String> = []

  /// Whether the manager is loading locale list
  private(set) var isLoading = false

  // MARK: - Initialization

  private init() {}

  // MARK: - Public Methods

  /// Check if Apple SpeechAnalyzer is available
  /// NOTE: Deprecated - now using FluidAudio. Kept for API compatibility.
  static var isAvailable: Bool {
    false  // FluidAudio is always available
  }

  /// Load available locales and their status
  /// NOTE: Deprecated - now using FluidAudio. Kept for API compatibility.
  func loadLocales() async {
    isLoading = true
    defer { isLoading = false }
    // FluidAudio handles its own model management
    locales = []
  }

  /// Refresh status for all locales
  /// NOTE: Deprecated - now using FluidAudio. Kept for API compatibility.
  func refreshStatus() async {
    // No-op: FluidAudio handles its own model management
  }

  /// Download language model for a locale
  /// NOTE: Deprecated - now using FluidAudio. Kept for API compatibility.
  func downloadLanguageModel(for locale: Locale) async {
    logger.info("AppleLanguageModelManager is deprecated. Use FluidAudioModelManager instead.")
  }

  /// Check if a locale is installed
  /// NOTE: Deprecated - now using FluidAudio. Kept for API compatibility.
  func isLocaleInstalled(_ locale: Locale) async -> Bool {
    false
  }

  /// Get installed locales
  /// NOTE: Deprecated - now using FluidAudio. Kept for API compatibility.
  func installedLocales() async -> [Locale] {
    []
  }
}
