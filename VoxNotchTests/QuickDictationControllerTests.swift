//
//  QuickDictationControllerTests.swift
//  VoxNotchTests
//
//  Tests the injectable dependency paths of QuickDictationController.
//  Uses mock AudioRecording, TranscriptionEngine, LLMProcessing, and TextOutputting.
//

import XCTest
@testable import VoxNotch

@MainActor
final class QuickDictationControllerTests: XCTestCase {

    private var mockAudio: MockAudioRecording!
    private var mockTranscription: MockTranscriptionEngine!
    private var mockLLM: MockLLMProcessing!
    private var mockTextOutput: MockTextOutputting!
    private var appState: AppState!
    private var controller: QuickDictationController!

    override func setUp() {
        super.setUp()
        mockAudio = MockAudioRecording()
        mockTranscription = MockTranscriptionEngine()
        mockLLM = MockLLMProcessing()
        mockTextOutput = MockTextOutputting()
        appState = AppState.shared

        appState.reset()

        controller = QuickDictationController(
            audioManager: mockAudio,
            textOutputManager: mockTextOutput,
            transcriptionEngine: mockTranscription,
            llmProcessor: mockLLM
        )
    }

    override func tearDown() {
        controller.stop()
        controller = nil
        mockAudio = nil
        mockTranscription = nil
        mockLLM = nil
        mockTextOutput = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isActive)
    }

    // MARK: - stop()

    func testStopTransitionsToIdle() {
        controller.stop()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isActive)
    }

    // MARK: - retryTranscription() — success

    func testRetryTranscriptionOutputsText() async throws {
        // Set up: simulate a previous failed transcription with saved audio
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_retry.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.lastAudioURL = tempFile
        appState.lastError = "Previous error"

        mockTranscription.stubbedResult = TranscriptionResult(
            text: "hello world",
            confidence: 0.95,
            audioDuration: 2.0,
            processingTime: 0.1,
            provider: "Mock",
            language: nil,
            segments: nil
        )

        controller.retryTranscription()

        // Wait for the async pipeline to complete
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(mockTranscription.ensureReadyCallCount, 1)
        XCTAssertEqual(mockTranscription.transcribeCallCount, 1)
        XCTAssertEqual(mockTranscription.lastTranscribeURL, tempFile)
        // Text should have been output (paste or clipboard)
        let outputted = (mockTextOutput.outputCallCount > 0) || (mockTextOutput.copyCallCount > 0)
        XCTAssertTrue(outputted, "Text should have been output via paste or clipboard")
    }

    // MARK: - retryTranscription() — empty text

    func testRetryTranscriptionEmptyTextShowsError() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_empty.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.lastAudioURL = tempFile
        appState.lastError = "Previous error"

        mockTranscription.stubbedResult = TranscriptionResult(
            text: "",
            confidence: nil,
            audioDuration: 1.0,
            processingTime: 0.1,
            provider: "Mock",
            language: nil,
            segments: nil
        )

        controller.retryTranscription()
        try await Task.sleep(for: .milliseconds(200))

        // Empty text → error state (noSpeechDetected)
        if case .error = controller.state {
            // expected
        } else {
            XCTFail("Expected error state for empty transcription, got \(controller.state)")
        }

        // No text should have been output
        XCTAssertEqual(mockTextOutput.outputCallCount, 0)
        XCTAssertEqual(mockTextOutput.copyCallCount, 0)
    }

    // MARK: - retryTranscription() — transcription error

    func testRetryTranscriptionErrorShowsErrorState() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_error.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.lastAudioURL = tempFile
        appState.lastError = "Previous error"

        mockTranscription.stubbedError = NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Transcription failed"]
        )

        controller.retryTranscription()
        try await Task.sleep(for: .milliseconds(200))

        if case .error = controller.state {
            XCTAssertNotNil(appState.lastError)
        } else {
            XCTFail("Expected error state, got \(controller.state)")
        }
    }

    // MARK: - retryTranscription() — missing file

    func testRetryTranscriptionMissingFileClears() {
        appState.lastAudioURL = URL(fileURLWithPath: "/nonexistent/file.wav")
        appState.lastError = "Previous error"

        controller.retryTranscription()

        // Should have cleared the stale URL
        XCTAssertNil(appState.lastAudioURL)
    }

    // MARK: - retryTranscription() — no saved audio

    func testRetryTranscriptionNoAudioIsNoop() {
        appState.lastAudioURL = nil

        controller.retryTranscription()

        // Should remain idle
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(mockTranscription.transcribeCallCount, 0)
    }

    // MARK: - Delegate: AppState sync

    func testDelegateSyncsErrorState() async throws {
        // Verify that AppState booleans are correctly synced for a terminal error state
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_sync.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.lastAudioURL = tempFile
        appState.lastError = "test"

        mockTranscription.stubbedError = NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Sync test error"]
        )

        controller.retryTranscription()
        try await Task.sleep(for: .milliseconds(200))

        // Error is a terminal state — AppState should reflect it
        XCTAssertNotNil(appState.lastError)
        XCTAssertFalse(appState.isRecording)
        XCTAssertFalse(appState.isWarmingUp)
        XCTAssertFalse(appState.isTranscribing)
        XCTAssertFalse(appState.isProcessingLLM)
        XCTAssertFalse(appState.isModelSelecting)
        XCTAssertFalse(appState.isToneSelecting)
    }

    func testDelegateSyncsIdleAfterSuccess() async throws {
        // Verify that AppState is clean after a successful retry
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_idle_sync.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.lastAudioURL = tempFile
        appState.lastError = "test"

        mockTranscription.stubbedResult = TranscriptionResult(
            text: "sync test",
            confidence: 0.9,
            audioDuration: 1.0,
            processingTime: 0.1,
            provider: "Mock",
            language: nil,
            segments: nil
        )

        controller.retryTranscription()
        try await Task.sleep(for: .milliseconds(300))

        // After success, should be back to idle — all flags false
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(appState.isRecording)
        XCTAssertFalse(appState.isWarmingUp)
        XCTAssertFalse(appState.isTranscribing)
        XCTAssertFalse(appState.isProcessingLLM)
    }

    // MARK: - onStateChange callback

    func testOnStateChangeCallbackFires() async throws {
        var receivedStates: [DictationState] = []
        controller.onStateChange = { state in
            receivedStates.append(state)
        }

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_callback.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.lastAudioURL = tempFile
        appState.lastError = "test"
        mockTranscription.stubbedResult = TranscriptionResult(
            text: "test",
            confidence: 0.9,
            audioDuration: 1.0,
            processingTime: 0.1,
            provider: "Mock",
            language: nil,
            segments: nil
        )

        controller.retryTranscription()
        try await Task.sleep(for: .milliseconds(300))

        // Should have received multiple state transitions
        XCTAssertGreaterThan(receivedStates.count, 0, "onStateChange should fire for transitions")
    }
}
