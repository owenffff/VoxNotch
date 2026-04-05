//
//  DictationStateMachine.swift
//  VoxNotch
//
//  Owns the dictation state enum, session ID lifecycle, and timer management.
//  QuickDictationController becomes a thin wiring layer that delegates here
//  and translates state changes into AppState / NotchManager side effects.
//

import Foundation

// MARK: - Delegate

/// Notified on every state transition so the controller can sync AppState / UI.
@MainActor protocol DictationStateMachineDelegate: AnyObject {
    func stateMachine(
        _ stateMachine: DictationStateMachine,
        didTransitionFrom oldState: DictationState,
        to newState: DictationState
    )
}

// MARK: - State Machine

@MainActor
final class DictationStateMachine {

    // MARK: - Properties

    /// Current dictation state.
    private(set) var state: DictationState = .idle

    /// Session ID — incremented on cancel so in-flight async tasks know to discard.
    private(set) var currentSessionID = UUID()

    /// Recording start time (set by controller when audio capture begins).
    var recordingStartTime: Date?

    /// Timestamp of last cancel — used for cooldown between rapid presses.
    var lastCancelTime: Date?

    /// Delegate receives every state transition.
    weak var delegate: DictationStateMachineDelegate?

    // MARK: - Timers

    /// Watchdog to prevent stuck recording state (10 minutes).
    private var watchdogTimer: Timer?

    /// Updates recording duration every second.
    private var durationTimer: Timer?

    /// Callback fired every second while recording, providing elapsed time.
    /// The controller uses this to update `appState.recordingDuration`.
    var onRecordingDurationTick: ((TimeInterval) -> Void)?

    /// Callback fired when the watchdog triggers (stuck recording).
    /// The controller uses this to force-cancel the session.
    var onWatchdogFired: (() -> Void)?

    // MARK: - Public API

    /// Transition to a new state. Manages timers and notifies the delegate.
    func transition(to newState: DictationState) {
        let oldState = state
        state = newState

        // Duration timer: only runs during .recording
        if case .recording = newState {
            // will be started by controller after setting recordingStartTime
        } else {
            stopDurationTimer()
        }

        // Watchdog timer: start on recording, stop on anything else
        stopWatchdog()
        if case .recording = newState {
            startWatchdog()
        }

        delegate?.stateMachine(self, didTransitionFrom: oldState, to: newState)
    }

    /// Invalidate the current session (cancel in-flight work).
    /// Returns the new session ID.
    @discardableResult
    func invalidateSession() -> UUID {
        let newID = UUID()
        currentSessionID = newID
        return newID
    }

    /// Check whether a captured session ID still matches the current session.
    func isSessionValid(_ sessionID: UUID) -> Bool {
        return sessionID == currentSessionID
    }

    /// Start the duration timer. Called by the controller after recording begins.
    func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.recordingStartTime else { return }
                self.onRecordingDurationTick?(Date().timeIntervalSince(start))
            }
        }
    }

    /// Stop and nil out the duration timer.
    func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 600.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onWatchdogFired?()
            }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }
}
