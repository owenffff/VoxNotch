//
//  VadGate.swift
//  VoxNotch
//
//  Pre-transcription speech gate using Silero VAD via FluidAudio
//

import FluidAudio
import Foundation
import os.log

/// Opt-in speech gate that uses Silero VAD to reject non-speech audio
/// before it reaches the ASR model. Lazy-loads the VAD model on first use.
final class VadGate: @unchecked Sendable {

  static let shared = VadGate()

  private let logger = Logger(subsystem: "com.voxnotch", category: "VadGate")
  private let lock = NSLock()
  private var vadManager: VadManager?
  private var isInitializing = false

  private init() {}

  // MARK: - Public

  /// Whether the Silero VAD model is already downloaded on disk.
  var isModelAvailable: Bool {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let modelPath = appSupport
      .appendingPathComponent("FluidAudio/Models/silero-vad-coreml", isDirectory: true)
      .appendingPathComponent(ModelNames.VAD.sileroVadFile, isDirectory: true)
    return FileManager.default.fileExists(atPath: modelPath.path)
  }

  /// Download the VAD model if not present and initialize the manager.
  func ensureModelReady() async throws {
    if lock.withLock({ vadManager != nil }) { return }
    try await initializeManager()
  }

  /// Run VAD on a recorded audio file. Returns true if speech is detected.
  func containsSpeech(audioURL: URL) async throws -> Bool {
    try await ensureModelReady()

    guard let manager = lock.withLock({ vadManager }) else {
      logger.error("VadManager unavailable after initialization")
      return true // fail open — allow transcription
    }

    let results = try await manager.process(audioURL)
    let threshold = manager.config.defaultThreshold
    let hasSpeech = results.contains { $0.probability >= threshold }

    logger.info("VAD speech gate: \(hasSpeech ? "speech detected" : "no speech") (\(results.count) chunks, threshold: \(threshold))")
    return hasSpeech
  }

  // MARK: - Private

  private func initializeManager() async throws {
    let shouldInit: Bool = lock.withLock {
      if vadManager != nil || isInitializing { return false }
      isInitializing = true
      return true
    }

    if !shouldInit {
      // Another call is initializing — wait for it
      for _ in 0..<60 {
        try await Task.sleep(nanoseconds: 500_000_000)
        if lock.withLock({ vadManager != nil }) { return }
      }
      throw VadGateError.initializationTimeout
    }

    do {
      let manager = try await VadManager()
      lock.withLock {
        self.vadManager = manager
        self.isInitializing = false
      }
      logger.info("Silero VAD model loaded")
    } catch {
      lock.withLock { self.isInitializing = false }
      logger.error("Failed to load VAD model: \(error.localizedDescription)")
      throw error
    }
  }
}

enum VadGateError: LocalizedError {
  case initializationTimeout

  var errorDescription: String? {
    switch self {
    case .initializationTimeout:
      return "VAD model initialization timed out"
    }
  }
}
