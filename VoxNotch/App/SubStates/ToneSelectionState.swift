//
//  ToneSelectionState.swift
//  VoxNotch
//
//  Observable sub-state for the tone cycling UI.
//

import Foundation

@MainActor @Observable
final class ToneSelectionState {

    static let shared = ToneSelectionState()

    /// The tones shown in the cycling UI (populated from pinned tone IDs on entry)
    var candidates: [ToneTemplate] = []

    /// Current cycle index: 0...(candidates.count-1) = tones, candidates.count = "More Tones..."
    var index: Int = 0

    private init() {}
    init(forTesting: Void) {}

    func reset() {
        candidates = []
        index = 0
    }
}
