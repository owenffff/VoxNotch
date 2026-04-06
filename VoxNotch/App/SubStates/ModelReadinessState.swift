//
//  ModelReadinessState.swift
//  VoxNotch
//
//  Observable sub-state for model download progress and readiness.
//

import Foundation

@MainActor @Observable
final class ModelReadinessState {

    static let shared = ModelReadinessState()

    var isDownloadingModel: Bool = false

    /// Model download progress (0.0 to 1.0)
    var modelDownloadProgress: Double = 0.0

    /// Whether speech model is ready for transcription
    var isModelReady: Bool = false

    /// Whether required models need to be downloaded
    var modelsNeeded: Bool = false

    /// Human-readable message about which models are missing
    var modelsNeededMessage: String = ""

    private init() {}
    init(forTesting: Void) {}

    func reset() {
        isDownloadingModel = false
        modelDownloadProgress = 0.0
        isModelReady = false
        modelsNeeded = false
        modelsNeededMessage = ""
    }
}
