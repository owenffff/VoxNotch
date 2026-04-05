//
//  ModelDownloadState.swift
//  VoxNotch
//
//  Unified download state for all ASR model managers
//

import Foundation

/// State of an ASR model's download and readiness lifecycle.
/// Used by both FluidAudioModelManager and MLXAudioModelManager.
enum ModelDownloadState: Equatable, Sendable {
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

  var isDownloaded: Bool {
    switch self {
    case .downloaded, .ready, .loading: return true
    default: return false
    }
  }

  /// Simplified state for UI display (no internal details like loading)
  var uiState: UIDownloadState {
    switch self {
    case .notDownloaded: return .notDownloaded
    case .downloading(let progress, let downloadedBytes, let totalBytes, let speedBytesPerSecond):
      return .downloading(progress: progress, downloadedBytes: downloadedBytes, totalBytes: totalBytes, speedBytesPerSecond: speedBytesPerSecond)
    case .downloaded, .loading, .ready: return .ready
    case .failed: return .failed
    }
  }
}

/// Simplified download state for Settings UI display.
/// Collapses internal states (downloaded/loading/ready) into a single `.ready`.
enum UIDownloadState: Equatable {
  case notDownloaded
  case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64, speedBytesPerSecond: Double)
  case ready
  case failed
}
