//
//  DictationState.swift
//  VoxNotch
//
//  The dictation state enum, extracted from QuickDictationController
//  so the state machine can be tested in isolation.
//

import Foundation

/// All states the dictation flow can be in.
enum DictationState {
    case idle
    case recording
    case warmingUp
    case transcribing
    case processingLLM
    case outputting
    case modelSelecting
    case toneSelecting
    case error(Error)

    /// Whether the dictation flow is actively processing (recording through outputting).
    var isActive: Bool {
        switch self {
        case .recording, .warmingUp, .transcribing, .processingLLM, .outputting:
            return true
        case .idle, .modelSelecting, .toneSelecting, .error:
            return false
        }
    }
}

// MARK: - Equatable

extension DictationState: Equatable {
    static func == (lhs: DictationState, rhs: DictationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.recording, .recording),
             (.warmingUp, .warmingUp),
             (.transcribing, .transcribing),
             (.processingLLM, .processingLLM),
             (.outputting, .outputting),
             (.modelSelecting, .modelSelecting),
             (.toneSelecting, .toneSelecting):
            return true
        case (.error(let a), .error(let b)):
            return a.localizedDescription == b.localizedDescription
        default:
            return false
        }
    }
}
