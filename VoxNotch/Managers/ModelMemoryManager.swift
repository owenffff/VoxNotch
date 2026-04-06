//
//  ModelMemoryManager.swift
//  VoxNotch
//
//  Manages ML model loading/unloading with memory optimization
//

import Foundation
import os.log

/// Model loading state
enum ModelLoadState: Equatable {
  case unloaded
  case loading
  case loaded
  case unloading
  case failed(message: String)

  var isLoaded: Bool {
    if case .loaded = self {
      return true
    }
    return false
  }

  var isLoading: Bool {
    if case .loading = self {
      return true
    }
    return false
  }
}

/// Manages ML model memory lifecycle
@Observable
final class ModelMemoryManager {

  // MARK: - Singleton

  static let shared = ModelMemoryManager()

  // MARK: - Properties

  /// Current load state for each model
  private(set) var loadStates: [LegacyWhisperModel: ModelLoadState] = [:]

  /// Currently loaded model (only one at a time to conserve memory)
  private(set) var currentModel: LegacyWhisperModel?

  /// Time when current model was last used
  private var lastUsedTime: Date?

  /// Idle timeout before unloading model (default: 5 minutes)
  var idleTimeout: TimeInterval = 300

  /// Whether auto-unload on idle is enabled
  var autoUnloadEnabled: Bool = true

  /// Timer for checking idle timeout
  private var idleTimer: Timer?

  /// Memory pressure observer
  private var memoryPressureSource: DispatchSourceMemoryPressure?

  private let logger = Logger(subsystem: "com.voxnotch", category: "ModelMemoryManager")
  private let settings = SettingsManager.shared

  // MARK: - Initialization

  private init() {
    /// Initialize all models as unloaded
    for model in LegacyWhisperModel.allCases {
      loadStates[model] = .unloaded
    }

    setupMemoryPressureObserver()
  }

  deinit {
    idleTimer?.invalidate()
    memoryPressureSource?.cancel()
  }

  // MARK: - Public Methods

  /// Load a model into memory
  /// - Parameter model: The model to load
  /// - Throws: Error if loading fails
  func loadModel(_ model: LegacyWhisperModel) async throws {
    /// Check if already loaded
    if currentModel == model && loadStates[model]?.isLoaded == true {
      logger.debug("Model \(model.rawValue) already loaded")
      touchLastUsed()
      return
    }

    /// Unload current model first if different
    if let current = currentModel, current != model {
      await unloadModel(current)
    }

    /// Check if model is downloaded
    guard ModelDownloadManager.shared.isModelDownloaded(model) else {
      let error = "Model not downloaded"
      loadStates[model] = .failed(message: error)
      throw ModelMemoryError.modelNotDownloaded
    }

    logger.info("Loading model: \(model.rawValue)")
    loadStates[model] = .loading

    do {
      /// TODO: Replace with actual SwamaKit model loading
      /// This is a placeholder that simulates loading time
      try await simulateModelLoad(model)

      loadStates[model] = .loaded
      currentModel = model
      touchLastUsed()
      startIdleTimer()

      logger.info("Model loaded successfully: \(model.rawValue)")

    } catch {
      loadStates[model] = .failed(message: error.localizedDescription)
      logger.error("Failed to load model \(model.rawValue): \(error.localizedDescription)")
      throw error
    }
  }

  /// Unload a model from memory
  /// - Parameter model: The model to unload
  func unloadModel(_ model: LegacyWhisperModel) async {
    guard loadStates[model]?.isLoaded == true else {
      return
    }

    logger.info("Unloading model: \(model.rawValue)")
    loadStates[model] = .unloading

    /// TODO: Replace with actual SwamaKit model unloading
    /// This is a placeholder
    await simulateModelUnload(model)

    loadStates[model] = .unloaded

    if currentModel == model {
      currentModel = nil
      stopIdleTimer()
    }

    logger.info("Model unloaded: \(model.rawValue)")
  }

  /// Unload all models to free memory
  func unloadAllModels() async {
    for model in LegacyWhisperModel.allCases {
      if loadStates[model]?.isLoaded == true {
        await unloadModel(model)
      }
    }
  }

  /// Ensure the selected model is loaded (called before transcription)
  func ensureModelReady() async throws {
    guard let selectedModelId = LegacyWhisperModel(rawValue: settings.selectedModel) else {
      throw ModelMemoryError.invalidModel
    }

    try await loadModel(selectedModelId)
  }

  /// Mark model as recently used (resets idle timer)
  func touchLastUsed() {
    lastUsedTime = Date()
  }

  /// Check if a model is ready for inference
  func isModelReady(_ model: LegacyWhisperModel) -> Bool {
    loadStates[model]?.isLoaded == true
  }

  /// Get current memory usage estimate for loaded model
  var estimatedMemoryUsage: Int64 {
    guard let model = currentModel,
          loadStates[model]?.isLoaded == true
    else {
      return 0
    }

    /// Rough estimate: loaded model size ~= disk size
    return model.downloadSize
  }

  // MARK: - Memory Pressure Handling

  private func setupMemoryPressureObserver() {
    memoryPressureSource = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical],
      queue: .main
    )

    memoryPressureSource?.setEventHandler { [weak self] in
      guard let self else {
        return
      }

      let event = self.memoryPressureSource?.data ?? []

      if event.contains(.critical) {
        self.logger.warning("Critical memory pressure - unloading all models")
        Task {
          await self.unloadAllModels()
        }
      } else if event.contains(.warning) {
        self.logger.info("Memory pressure warning - considering model unload")
        /// Only unload if idle
        if self.isIdle {
          Task {
            await self.unloadAllModels()
          }
        }
      }
    }

    memoryPressureSource?.resume()
  }

  // MARK: - Idle Timer

  private func startIdleTimer() {
    guard idleTimer == nil else { return }
    idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      self?.checkIdleTimeout()
    }
  }

  func stopIdleTimer() {
    idleTimer?.invalidate()
    idleTimer = nil
  }

  private func checkIdleTimeout() {
    guard autoUnloadEnabled,
          currentModel != nil,
          let lastUsed = lastUsedTime
    else {
      return
    }

    let idleTime = Date().timeIntervalSince(lastUsed)

    if idleTime >= idleTimeout {
      logger.info("Model idle for \(Int(idleTime))s - unloading")
      Task {
        await unloadAllModels()
      }
    }
  }

  private var isIdle: Bool {
    guard let lastUsed = lastUsedTime else {
      return true
    }
    return Date().timeIntervalSince(lastUsed) >= 60 /// Consider idle after 1 minute
  }

  // MARK: - Placeholder Methods (Replace with SwamaKit)

  /// Simulates model loading - replace with actual SwamaKit integration
  private func simulateModelLoad(_ model: LegacyWhisperModel) async throws {
    /// Simulate loading time based on model size
    let loadTime: TimeInterval
    switch model {
    case .whisperTiny:
      loadTime = 0.5
    case .whisperBase:
      loadTime = 0.8
    case .whisperSmall:
      loadTime = 1.2
    case .whisperMedium:
      loadTime = 2.0
    case .whisperLarge:
      loadTime = 4.0
    case .funasrParaformer:
      loadTime = 1.5
    }

    try await Task.sleep(nanoseconds: UInt64(loadTime * 1_000_000_000))

    /// TODO: Actually load model with SwamaKit
    /// Example:
    /// let modelPath = ModelDownloadManager.shared.modelPath(for: model)
    /// self.loadedModel = try await SwamaKit.loadModel(at: modelPath)
  }

  /// Simulates model unloading - replace with actual SwamaKit integration
  private func simulateModelUnload(_ model: LegacyWhisperModel) async {
    try? await Task.sleep(nanoseconds: 100_000_000) /// 0.1 seconds

    /// TODO: Actually unload model with SwamaKit
    /// Example:
    /// self.loadedModel = nil
  }
}

// MARK: - Errors

enum ModelMemoryError: LocalizedError {
  case modelNotDownloaded
  case invalidModel
  case loadFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotDownloaded:
      return "Model must be downloaded before loading"
    case .invalidModel:
      return "Invalid model selection"
    case .loadFailed(let message):
      return "Failed to load model: \(message)"
    }
  }
}
