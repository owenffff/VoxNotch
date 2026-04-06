//
//  ASREngine.swift
//  VoxNotch
//
//  Available ASR (Automatic Speech Recognition) engines
//

import Foundation

/// Available ASR engines for speech-to-text transcription
enum ASREngine: String, CaseIterable, Identifiable, Sendable {
  case fluidAudio = "fluidAudio"
  case mlxAudio = "mlxAudio"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .fluidAudio: "FluidAudio (Parakeet)"
    case .mlxAudio: "MLX Audio (GLM-ASR)"
    }
  }

  var description: String {
    switch self {
    case .fluidAudio: "English-optimized, fast inference"
    case .mlxAudio: "Multilingual, 13+ languages"
    }
  }
}
