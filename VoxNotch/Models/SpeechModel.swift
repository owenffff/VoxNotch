//
//  SpeechModel.swift
//  VoxNotch
//
//  Unified speech model abstraction that hides engine implementation details
//

import Foundation

// MARK: - Language Support

/// Language support capability
enum LanguageSupport: String, Sendable {
  case englishOptimized
  case multilingual
}

// MARK: - Speech Model

/// Unified speech model that abstracts away the underlying engine
enum SpeechModel: String, CaseIterable, Identifiable, Sendable {
  // FluidAudio models
  case parakeetV2 = "fluidaudio-v2"
  case parakeetV3 = "fluidaudio-v3"

  // MLX Audio models
  case glmAsrNano = "mlx-glm-asr-nano"
  case qwen3Asr = "mlx-qwen3-asr"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .parakeetV2: "Parakeet v2"
    case .parakeetV3: "Parakeet v3"
    case .glmAsrNano: "GLM-ASR Nano"
    case .qwen3Asr: "Qwen3-ASR 1.7B"
    }
  }

  var engine: ASREngine {
    switch self {
    case .parakeetV2, .parakeetV3: .fluidAudio
    case .glmAsrNano, .qwen3Asr: .mlxAudio
    }
  }

  var estimatedSizeMB: Int {
    switch self {
    case .parakeetV2: 500
    case .parakeetV3: 800
    case .glmAsrNano: 400
    case .qwen3Asr: 3400
    }
  }

  var languageSupport: LanguageSupport {
    switch self {
    case .parakeetV2: .englishOptimized
    case .parakeetV3, .glmAsrNano, .qwen3Asr: .multilingual
    }
  }

  var languageDescription: String {
    switch self {
    case .parakeetV2: "English optimized"
    case .parakeetV3: "13+ languages"
    case .glmAsrNano, .qwen3Asr: "Multilingual"
    }
  }

  var supportedLanguages: [String] {
    switch self {
    case .parakeetV2:
      ["en"]
    case .parakeetV3:
      ["en", "zh", "ja", "ko", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "tr", "ar"]
    case .glmAsrNano, .qwen3Asr:
      ["en", "zh", "ja", "ko", "es", "fr", "de", "it", "pt", "ru", "ar"]
    }
  }

  /// Convert to underlying FluidAudio model version
  var fluidAudioVersion: FluidAudioModelVersion? {
    switch self {
    case .parakeetV2: .v2English
    case .parakeetV3: .v3Multilingual
    default: nil
    }
  }

  /// Convert to underlying MLX Audio model version
  var mlxAudioVersion: MLXAudioModelVersion? {
    switch self {
    case .glmAsrNano: .glmAsrNano
    case .qwen3Asr: .qwen3Asr
    default: nil
    }
  }

  /// Whether this model's weights are present on disk and ready to load
  var isDownloaded: Bool {
    switch engine {
    case .fluidAudio:
      guard let version = fluidAudioVersion else { return false }
      return FluidAudioModelManager.shared.isVersionDownloaded(version)
    case .mlxAudio:
      guard let version = mlxAudioVersion else { return false }
      return MLXAudioModelManager.shared.isVersionDownloaded(version)
    }
  }

  /// Default model for new users
  static var defaultModel: SpeechModel { .parakeetV2 }

  // MARK: - Card Metadata

  var tagline: String {
    switch self {
    case .parakeetV2: "Best for English"
    case .parakeetV3: "Best for Multilingual"
    case .glmAsrNano: "Fast & Lightweight"
    case .qwen3Asr: "Best for Asian Languages"
    }
  }

  var modelDescription: String {
    switch self {
    case .parakeetV2:
      "Ultra-fast English transcription powered by NVIDIA Parakeet. Ideal for everyday dictation with the lowest latency."
    case .parakeetV3:
      "Multilingual Parakeet supporting 13+ languages with high accuracy. Great for mixed-language and global use cases."
    case .glmAsrNano:
      "Compact MLX model optimized for speed and low memory. Best when you need quick results with a minimal footprint."
    case .qwen3Asr:
      "High-accuracy multilingual model with strong support for Chinese, Japanese, Korean, and other Asian languages."
    }
  }

  var accuracyRating: Int {
    switch self {
    case .parakeetV2: 4
    case .parakeetV3: 4
    case .glmAsrNano: 3
    case .qwen3Asr: 5
    }
  }

  var speedRating: Int {
    switch self {
    case .parakeetV2: 5
    case .parakeetV3: 4
    case .glmAsrNano: 5
    case .qwen3Asr: 3
    }
  }

  var providerIconName: String {
    switch self {
    case .parakeetV2, .parakeetV3: "waveform"
    case .glmAsrNano: "cpu"
    case .qwen3Asr: "globe.asia.australia"
    }
  }
}

// MARK: - AnyModel Resolution

extension SpeechModel {
  /// Resolve a raw settings ID to either a built-in or custom speech model.
  /// Built-in models match their rawValue; custom models match a UUID string
  /// stored in `CustomModelRegistry`.
  static func resolve(_ rawValue: String) -> (builtin: SpeechModel?, custom: CustomSpeechModel?) {
    if let builtin = SpeechModel(rawValue: rawValue) { return (builtin, nil) }
    return (nil, CustomModelRegistry.shared.model(withID: rawValue))
  }
}
