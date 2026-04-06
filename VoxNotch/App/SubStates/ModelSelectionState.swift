//
//  ModelSelectionState.swift
//  VoxNotch
//
//  Observable sub-state for the model cycling UI.
//

import Foundation

@MainActor @Observable
final class ModelSelectionState {

    static let shared = ModelSelectionState()

    /// The models shown in the cycling UI (populated on entry; includes custom models)
    var candidates: [AnyModel] = []

    /// Current cycle index: 0...(candidates.count-1) = models, candidates.count = "More Models..."
    var index: Int = 0

    private init() {}
    init(forTesting: Void) {}

    func reset() {
        candidates = []
        index = 0
    }
}
