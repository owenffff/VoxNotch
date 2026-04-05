//
//  AudioVisualizationState.swift
//  VoxNotch
//
//  High-frequency audio visualization state, separated from AppState
//  to avoid triggering SwiftUI redraws in views that don't use it.
//

import SwiftUI
import Observation

@MainActor @Observable
final class AudioVisualizationState {

  // MARK: - Singleton

  static let shared = AudioVisualizationState()

  // MARK: - Properties

  /// Current audio level (0.0–1.0), updated at ~60fps during recording.
  var audioLevel: Float = 0.0

  /// 6-band frequency spectrum for visualization, updated at ~60fps during recording.
  var audioFrequencyBands: [Float] = [Float](repeating: 0, count: 6)

  // MARK: - Initialization

  private init() {}

  // MARK: - Methods

  func reset() {
    audioLevel = 0.0
    audioFrequencyBands = [Float](repeating: 0, count: 6)
  }
}
