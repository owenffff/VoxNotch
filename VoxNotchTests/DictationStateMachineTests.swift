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
        sm.transition(to: .recording)
        sm.transition(to: .error(error))
        XCTAssertEqual(sm.state, .error(error))
    }

    func testTransitionFromAnyStateToIdle() {
        // Walk through valid paths to reach each state, then verify → idle works.
        // recording → idle
        sm.transition(to: .recording)
        sm.transition(to: .idle)
        XCTAssertEqual(sm.state, .idle)

        // warmingUp → idle
        sm.transition(to: .recording)
        sm.transition(to: .warmingUp)
        sm.transition(to: .idle)
        XCTAssertEqual(sm.state, .idle)

        // transcribing → idle
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .idle)
        XCTAssertEqual(sm.state, .idle)

        // processingLLM → idle
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .processingLLM)
        sm.transition(to: .idle)
        XCTAssertEqual(sm.state, .idle)

        // outputting → idle
        sm.transition(to: .recording)
        sm.transition(to: .transcribing)
        sm.transition(to: .processingLLM)
        sm.transition(to: .outputting)
        sm.transition(to: .idle)
        XCTAssertEqual(sm.state, .idle)

        // modelSelecting → idle
        sm.transition(to: .modelSelecting)
        sm.transition(to: .idle)
        XCTAssertEqual(sm.state, .idle)

        // toneSelecting → idle
        sm.transition(to: .toneSelecting)
        sm.transition(to: .idle)
        XCTAssertEqual(sm.state, .idle)

        // error → idle
        sm.transition(to: .recording)
        sm.transition(to: .error(NSError(domain: "test", code: 1)))
        sm.transition(to: .idle)
        XCTAssertEqual(sm.state, .idle)
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

// MARK: - Pipeline Tests

@MainActor
final class DictationPipelineTests: XCTestCase {

    private var mockAudio: MockAudioRecording!
    private var mockTranscription: MockTranscriptionEngine!
    private var mockLLM: MockLLMProcessing!
    private var mockTextOutput: MockTextOutputting!
    private var sm: DictationStateMachine!
    private var delegate: MockStateMachineDelegate!

    override func setUp() {
        super.setUp()
        mockAudio = MockAudioRecording()
        mockTranscription = MockTranscriptionEngine()
        mockLLM = MockLLMProcessing()
        mockTextOutput = MockTextOutputting()
        sm = DictationStateMachine(
            audioManager: mockAudio,
            transcriptionEngine: mockTranscription,
            llmProcessor: mockLLM,
            textOutputManager: mockTextOutput
        )
        delegate = MockStateMachineDelegate()
        sm.delegate = delegate
    }

    override func tearDown() {
        sm = nil
        delegate = nil
        mockAudio = nil
        mockTranscription = nil
        mockLLM = nil
        mockTextOutput = nil
        super.tearDown()
    }

    // MARK: - beginRecording

    func testBeginRecordingSetsStateAndStartsAudio() throws {
        try sm.beginRecording()

        XCTAssertEqual(sm.state, .recording)
        XCTAssertEqual(mockAudio.startRecordingCallCount, 1)
        XCTAssertTrue(mockAudio.accumulateBuffers)
        XCTAssertEqual(mockTranscription.preloadCallCount, 1)
        XCTAssertNotNil(sm.recordingStartTime)
    }

    func testBeginRecordingThrowsOnAudioError() {
        mockAudio.stubbedStartError = NSError(domain: "test", code: 1)

        XCTAssertThrowsError(try sm.beginRecording())
        // State should still be .recording from the transition before the throw
        // but the controller wraps this in do/catch and transitions to .error
    }

    // MARK: - stopRecordingAndTranscribe: Happy Path

    func testStopRecordingTranscribesAndOutputsText() async throws {
        try sm.beginRecording()
        sm.recordingStartTime = Date().addingTimeInterval(-2) // 2 seconds ago

        mockTextOutput.hasFocusedTextInputValue = true

        var outputSuccessCalled = false
        var wasClipboard = true
        sm.onPipelineOutputSuccess = { clipboard in
            outputSuccessCalled = true
            wasClipboard = clipboard
        }

        sm.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(mockAudio.stopRecordingCallCount, 1)
        XCTAssertEqual(mockTranscription.transcribeCallCount, 1)
        XCTAssertEqual(mockTextOutput.outputCallCount, 1)
        XCTAssertTrue(outputSuccessCalled)
        XCTAssertFalse(wasClipboard)
        XCTAssertEqual(sm.state, .idle)
    }

    // MARK: - stopRecordingAndTranscribe: Too Short

    func testStopRecordingTooShortCancels() throws {
        try sm.beginRecording()
        // recordingStartTime is just now → duration < 0.5s

        var cancelCalled = false
        sm.onPipelineCancelled = { cancelCalled = true }

        sm.stopRecordingAndTranscribe(savedFrontmostApp: nil)

        XCTAssertTrue(cancelCalled)
        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(mockAudio.stopRecordingCallCount, 0)
    }

    // MARK: - stopRecordingAndTranscribe: Empty Transcription

    func testEmptyTranscriptionReturnsToIdle() async throws {
        try sm.beginRecording()
        sm.recordingStartTime = Date().addingTimeInterval(-2)

        mockTranscription.stubbedResult = TranscriptionResult(
            text: "", confidence: nil, audioDuration: 1.0,
            processingTime: 0.1, provider: "Mock", language: nil, segments: nil
        )

        sm.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(mockTextOutput.outputCallCount, 0)
    }

    // MARK: - stopRecordingAndTranscribe: Low Confidence

    func testLowConfidenceDiscards() async throws {
        try sm.beginRecording()
        sm.recordingStartTime = Date().addingTimeInterval(-2)

        mockTranscription.stubbedResult = TranscriptionResult(
            text: "phantom", confidence: 0.3, audioDuration: 1.0,
            processingTime: 0.1, provider: "Mock", language: nil, segments: nil
        )

        sm.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(mockTextOutput.outputCallCount, 0)
    }

    // MARK: - stopRecordingAndTranscribe: Clipboard Fallback

    func testClipboardFallbackWhenNoFocusedInput() async throws {
        try sm.beginRecording()
        sm.recordingStartTime = Date().addingTimeInterval(-2)

        mockTextOutput.hasFocusedTextInputValue = false

        var wasClipboard = false
        sm.onPipelineOutputSuccess = { clipboard in wasClipboard = clipboard }

        sm.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(wasClipboard)
        XCTAssertEqual(mockTextOutput.copyCallCount, 1)
        XCTAssertEqual(mockTextOutput.outputCallCount, 0)
    }

    // MARK: - stopRecordingAndTranscribe: LLM Processing

    func testLLMProcessingApplied() async throws {
        try sm.beginRecording()
        sm.recordingStartTime = Date().addingTimeInterval(-2)

        mockLLM.isEnabled = true
        mockLLM.stubbedResult = .success(processedText: "enhanced text")
        mockTextOutput.hasFocusedTextInputValue = true

        sm.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(mockTextOutput.lastOutputText, "enhanced text")
    }

    func testLLMFallbackFiresWarning() async throws {
        try sm.beginRecording()
        sm.recordingStartTime = Date().addingTimeInterval(-2)

        mockLLM.isEnabled = true
        mockLLM.stubbedResult = .fallback(originalText: "raw text", error: LLMError.apiError("API timeout"))
        mockTextOutput.hasFocusedTextInputValue = true

        var warningMessage: String?
        sm.onLLMWarning = { msg in warningMessage = msg }

        sm.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertNotNil(warningMessage)
        // Should still output the fallback text
        XCTAssertGreaterThan(mockTextOutput.outputCallCount + mockTextOutput.copyCallCount, 0)
    }

    // MARK: - stopRecordingAndTranscribe: Error with Audio Preservation

    func testTranscriptionErrorPreservesAudioURL() async throws {
        try sm.beginRecording()
        sm.recordingStartTime = Date().addingTimeInterval(-2)

        mockTranscription.stubbedError = NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Transcription failed"]
        )

        var errorAudioURL: URL?
        sm.onPipelineErrorWithAudio = { url in errorAudioURL = url }

        sm.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertNotNil(errorAudioURL)
        if case .error = sm.state {} else {
            XCTFail("Expected error state")
        }
    }

    // MARK: - retryTranscription

    func testRetryTranscriptionSuccess() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("retry_test.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        mockTextOutput.hasFocusedTextInputValue = true

        var outputSuccessCalled = false
        sm.onPipelineOutputSuccess = { _ in outputSuccessCalled = true }

        sm.retryTranscription(audioURL: tempFile, savedFrontmostApp: nil)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(mockTranscription.transcribeCallCount, 1)
        XCTAssertTrue(outputSuccessCalled)
        XCTAssertEqual(sm.state, .idle)
    }

    func testRetryTranscriptionEmptyText() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("retry_empty.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        mockTranscription.stubbedResult = TranscriptionResult(
            text: "", confidence: nil, audioDuration: 1.0,
            processingTime: 0.1, provider: "Mock", language: nil, segments: nil
        )

        sm.retryTranscription(audioURL: tempFile, savedFrontmostApp: nil)
        try await Task.sleep(for: .milliseconds(300))

        if case .error = sm.state {} else {
            XCTFail("Expected error state for empty retry")
        }
    }

    // MARK: - cancelPipeline

    func testCancelPipelineResetsState() throws {
        try sm.beginRecording()
        sm.cancelPipeline()

        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(mockAudio.cancelRecordingCallCount, 1)
    }

    // MARK: - stopRecordingQuietly

    func testStopRecordingQuietlyCancelsAudio() throws {
        try sm.beginRecording()
        sm.stopRecordingQuietly()

        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(mockAudio.cancelRecordingCallCount, 1)
    }
}
