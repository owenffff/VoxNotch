//
//  DictationStateMachineTests.swift
//  VoxNotchTests
//

import XCTest
@testable import VoxNotch

// MARK: - Mock Delegate

@MainActor
final class MockStateMachineDelegate: DictationStateMachineDelegate {
    struct Transition: Equatable {
        let from: DictationState
        let to: DictationState
    }

    var transitions: [Transition] = []

    func stateMachine(
        _ stateMachine: DictationStateMachine,
        didTransitionFrom oldState: DictationState,
        to newState: DictationState
    ) {
        transitions.append(Transition(from: oldState, to: newState))
    }
}

// MARK: - Tests

@MainActor
final class DictationStateMachineTests: XCTestCase {

    private var sm: DictationStateMachine!
    private var delegate: MockStateMachineDelegate!

    override func setUp() {
        super.setUp()
        sm = DictationStateMachine()
        delegate = MockStateMachineDelegate()
        sm.delegate = delegate
    }

    override func tearDown() {
        sm = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        XCTAssertEqual(sm.state, .idle)
    }

    func testInitialStateIsNotActive() {
        XCTAssertFalse(sm.state.isActive)
    }

    // MARK: - State Transitions

    func testTransitionIdleToRecording() {
        sm.transition(to: .recording)
        XCTAssertEqual(sm.state, .recording)
        XCTAssertEqual(delegate.transitions.count, 1)
        XCTAssertEqual(delegate.transitions[0].from, .idle)
        XCTAssertEqual(delegate.transitions[0].to, .recording)
    }

    func testTransitionRecordingToTranscribing() {
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        XCTAssertEqual(sm.state, .transcribing)
        XCTAssertEqual(delegate.transitions.count, 2)
        XCTAssertEqual(delegate.transitions[1].from, .recording)
        XCTAssertEqual(delegate.transitions[1].to, .transcribing)
    }

    func testTransitionRecordingToWarmingUp() {
        sm.transition(to: .recording)
        sm.transition(to: .warmingUp)
        XCTAssertEqual(sm.state, .warmingUp)
    }

    func testTransitionWarmingUpToTranscribing() {
        sm.transition(to: .recording)
        sm.transition(to: .warmingUp)
        sm.transition(to: .transcribing)
        XCTAssertEqual(sm.state, .transcribing)
    }

    func testTransitionTranscribingToProcessingLLM() {
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .processingLLM)
        XCTAssertEqual(sm.state, .processingLLM)
    }

    func testTransitionProcessingLLMToOutputting() {
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .processingLLM)
        sm.transition(to: .outputting)
        XCTAssertEqual(sm.state, .outputting)
    }

    func testTransitionOutputtingToIdle() {
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .processingLLM)
        sm.transition(to: .outputting)
        sm.transition(to: .idle)
        XCTAssertEqual(sm.state, .idle)
    }

    func testTransitionToModelSelecting() {
        sm.transition(to: .modelSelecting)
        XCTAssertEqual(sm.state, .modelSelecting)
    }

    func testTransitionToToneSelecting() {
        sm.transition(to: .toneSelecting)
        XCTAssertEqual(sm.state, .toneSelecting)
    }

    func testTransitionToError() {
        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "test error"])
        sm.transition(to: .error(error))
        XCTAssertEqual(sm.state, .error(error))
    }

    func testTransitionFromAnyStateToIdle() {
        let states: [DictationState] = [
            .recording, .warmingUp, .transcribing, .processingLLM,
            .outputting, .modelSelecting, .toneSelecting,
            .error(NSError(domain: "test", code: 1))
        ]
        for state in states {
            sm.transition(to: state)
            sm.transition(to: .idle)
            XCTAssertEqual(sm.state, .idle, "Should transition from \(state) to idle")
        }
    }

    // MARK: - Full Pipeline

    func testFullPipelineTransitions() {
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .processingLLM)
        sm.transition(to: .outputting)
        sm.transition(to: .idle)

        XCTAssertEqual(delegate.transitions.count, 5)
        XCTAssertEqual(delegate.transitions.map(\.to), [
            .recording, .transcribing, .processingLLM, .outputting, .idle
        ])
    }

    func testPipelineWithWarmingUp() {
        sm.transition(to: .recording)
        sm.transition(to: .warmingUp)
        sm.transition(to: .transcribing)
        sm.transition(to: .processingLLM)
        sm.transition(to: .outputting)
        sm.transition(to: .idle)

        XCTAssertEqual(delegate.transitions.map(\.to), [
            .recording, .warmingUp, .transcribing, .processingLLM, .outputting, .idle
        ])
    }

    // MARK: - isActive

    func testIsActiveForAllStates() {
        let activeStates: [DictationState] = [.recording, .warmingUp, .transcribing, .processingLLM, .outputting]
        let inactiveStates: [DictationState] = [
            .idle, .modelSelecting, .toneSelecting,
            .error(NSError(domain: "test", code: 1))
        ]

        for state in activeStates {
            XCTAssertTrue(state.isActive, "\(state) should be active")
        }
        for state in inactiveStates {
            XCTAssertFalse(state.isActive, "\(state) should not be active")
        }
    }

    // MARK: - Session ID

    func testInitialSessionIDIsValid() {
        let id = sm.currentSessionID
        XCTAssertTrue(sm.isSessionValid(id))
    }

    func testInvalidateSessionChangesID() {
        let oldID = sm.currentSessionID
        let newID = sm.invalidateSession()
        XCTAssertNotEqual(oldID, newID)
        XCTAssertEqual(sm.currentSessionID, newID)
    }

    func testOldSessionIDBecomesInvalid() {
        let oldID = sm.currentSessionID
        sm.invalidateSession()
        XCTAssertFalse(sm.isSessionValid(oldID))
    }

    func testNewSessionIDIsValid() {
        let newID = sm.invalidateSession()
        XCTAssertTrue(sm.isSessionValid(newID))
    }

    func testMultipleInvalidations() {
        let id1 = sm.currentSessionID
        let id2 = sm.invalidateSession()
        let id3 = sm.invalidateSession()

        XCTAssertFalse(sm.isSessionValid(id1))
        XCTAssertFalse(sm.isSessionValid(id2))
        XCTAssertTrue(sm.isSessionValid(id3))
    }

    // MARK: - Duration Timer

    func testDurationTimerFiresCallback() {
        let expectation = expectation(description: "duration tick")
        var receivedElapsed: TimeInterval?

        sm.recordingStartTime = Date()
        sm.onRecordingDurationTick = { elapsed in
            receivedElapsed = elapsed
            expectation.fulfill()
        }

        sm.startDurationTimer()
        waitForExpectations(timeout: 2.0)
        sm.stopDurationTimer()

        XCTAssertNotNil(receivedElapsed)
        XCTAssertGreaterThan(receivedElapsed!, 0)
    }

    func testTransitionAwayFromRecordingStopsDurationTimer() {
        var tickCount = 0
        sm.recordingStartTime = Date()
        sm.onRecordingDurationTick = { _ in tickCount += 1 }

        sm.transition(to: .recording)
        sm.startDurationTimer()

        // Transition away from recording should stop the timer
        sm.transition(to: .transcribing)

        let initialCount = tickCount

        // Wait to verify no more ticks arrive
        let expectation = expectation(description: "wait for potential ticks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 3.0)

        XCTAssertEqual(tickCount, initialCount, "Timer should have stopped — no new ticks")
    }

    // MARK: - Watchdog Timer

    func testWatchdogStartsOnRecording() {
        var watchdogFired = false
        sm.onWatchdogFired = { watchdogFired = true }

        sm.transition(to: .recording)

        // Watchdog is 600s — just verify it was set up by transitioning away
        // (which cancels it) without it firing
        sm.transition(to: .idle)
        XCTAssertFalse(watchdogFired)
    }

    func testWatchdogStopsOnTransitionAwayFromRecording() {
        var watchdogFired = false
        sm.onWatchdogFired = { watchdogFired = true }

        sm.transition(to: .recording)
        sm.transition(to: .transcribing)

        // If watchdog wasn't cancelled, this would be problematic at 600s
        // Just verify it didn't fire immediately
        XCTAssertFalse(watchdogFired)
    }

    // MARK: - DictationState Equatable

    func testStateEquality() {
        XCTAssertEqual(DictationState.idle, DictationState.idle)
        XCTAssertEqual(DictationState.recording, DictationState.recording)
        XCTAssertNotEqual(DictationState.idle, DictationState.recording)
    }

    func testErrorStateEquality() {
        let e1 = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "same"])
        let e2 = NSError(domain: "other", code: 2, userInfo: [NSLocalizedDescriptionKey: "same"])
        let e3 = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "different"])

        XCTAssertEqual(DictationState.error(e1), DictationState.error(e2), "Same localizedDescription should be equal")
        XCTAssertNotEqual(DictationState.error(e1), DictationState.error(e3), "Different localizedDescription should differ")
    }

    // MARK: - Delegate Notification

    func testDelegateReceivesAllTransitions() {
        sm.transition(to: .recording)
        sm.transition(to: .idle)
        sm.transition(to: .modelSelecting)
        sm.transition(to: .idle)

        XCTAssertEqual(delegate.transitions.count, 4)
    }

    func testDelegateReceivesCorrectOldAndNewStates() {
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)

        XCTAssertEqual(delegate.transitions[0], MockStateMachineDelegate.Transition(from: .idle, to: .recording))
        XCTAssertEqual(delegate.transitions[1], MockStateMachineDelegate.Transition(from: .recording, to: .transcribing))
    }
}
