//
//  QuickDictationControllerTests.swift
//  VoxNotchTests
//
//  Tests the injectable dependency paths of QuickDictationController.
//  Uses mock AudioRecording, TranscriptionEngine, LLMProcessing, TextOutputting,
//  and MockNotchPresenter.
//

import XCTest
@testable import VoxNotch

@MainActor
final class QuickDictationControllerTests: XCTestCase {

    private var mockAudio: MockAudioRecording!
    private var mockTranscription: MockTranscriptionEngine!
    private var mockLLM: MockLLMProcessing!
    private var mockTextOutput: MockTextOutputting!
    private var mockNotch: MockNotchPresenter!
    private var appState: AppState!
    private var controller: QuickDictationController!

    override func setUp() {
        super.setUp()
        mockAudio = MockAudioRecording()
        mockTranscription = MockTranscriptionEngine()
        mockLLM = MockLLMProcessing()
        mockTextOutput = MockTextOutputting()
        mockNotch = MockNotchPresenter()
        appState = AppState(forTesting: ())

        controller = QuickDictationController(
            audioManager: mockAudio,
            textOutputManager: mockTextOutput,
            transcriptionEngine: mockTranscription,
            llmProcessor: mockLLM,
            appState: appState,
            notchPresenter: mockNotch,
            errorRouter: ErrorRouter(errorState: appState.error)
        )
    }

    override func tearDown() {
        controller.stop()
        controller = nil
        mockAudio = nil
        mockTranscription = nil
        mockLLM = nil
        mockTextOutput = nil
        mockNotch = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Wait for the pipeline to reach a terminal state (.idle or .error) via onStateChange.
    private func waitForPipelineCompletion(timeout: TimeInterval = 2.0) async throws {
        let expectation = XCTestExpectation(description: "Pipeline reached terminal state")
        let previousCallback = controller.onStateChange
        controller.onStateChange = { state in
            previousCallback?(state)
            if case .idle = state { expectation.fulfill() }
            else if case .error = state { expectation.fulfill() }
        }
        await fulfillment(of: [expectation], timeout: timeout)
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
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_retry.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.error.lastAudioURL = tempFile
        appState.error.lastError = "Previous error"

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
        try await waitForPipelineCompletion()

        XCTAssertEqual(mockTranscription.ensureReadyCallCount, 1)
        XCTAssertEqual(mockTranscription.transcribeCallCount, 1)
        XCTAssertEqual(mockTranscription.lastTranscribeURL, tempFile)
        let outputted = (mockTextOutput.outputCallCount > 0) || (mockTextOutput.copyCallCount > 0)
        XCTAssertTrue(outputted, "Text should have been output via paste or clipboard")
        // Verify notch was called (not silently using real NotchManager)
        XCTAssertGreaterThan(mockNotch.showOutputResultCallCount + mockNotch.showErrorCallCount, 0,
                             "Pipeline should have called notch presenter")
    }

    // MARK: - retryTranscription() — empty text

    func testRetryTranscriptionEmptyTextShowsError() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_empty.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.error.lastAudioURL = tempFile
        appState.error.lastError = "Previous error"

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
        try await waitForPipelineCompletion()

        if case .error = controller.state {
            // expected
        } else {
            XCTFail("Expected error state for empty transcription, got \(controller.state)")
        }

        XCTAssertEqual(mockTextOutput.outputCallCount, 0)
        XCTAssertEqual(mockTextOutput.copyCallCount, 0)
    }

    // MARK: - retryTranscription() — transcription error

    func testRetryTranscriptionErrorShowsErrorState() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_error.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.error.lastAudioURL = tempFile
        appState.error.lastError = "Previous error"

        mockTranscription.stubbedError = NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Transcription failed"]
        )

        controller.retryTranscription()
        try await waitForPipelineCompletion()

        if case .error = controller.state {
            XCTAssertNotNil(appState.error.lastError)
        } else {
            XCTFail("Expected error state, got \(controller.state)")
        }
    }

    // MARK: - retryTranscription() — missing file

    func testRetryTranscriptionMissingFileClears() {
        appState.error.lastAudioURL = URL(fileURLWithPath: "/nonexistent/file.wav")
        appState.error.lastError = "Previous error"

        controller.retryTranscription()

        XCTAssertNil(appState.error.lastAudioURL)
    }

    // MARK: - retryTranscription() — no saved audio

    func testRetryTranscriptionNoAudioIsNoop() {
        appState.error.lastAudioURL = nil

        controller.retryTranscription()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(mockTranscription.transcribeCallCount, 0)
    }

    // MARK: - Delegate: AppState sync

    func testDelegateSyncsErrorState() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_sync.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.error.lastAudioURL = tempFile
        appState.error.lastError = "test"

        mockTranscription.stubbedError = NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Sync test error"]
        )

        controller.retryTranscription()
        try await waitForPipelineCompletion()

        XCTAssertNotNil(appState.error.lastError)
        if case .error = appState.dictationPhase {} else {
            XCTFail("Expected dictationPhase to be .error, got \(appState.dictationPhase)")
        }
    }

    func testDelegateSyncsIdleAfterSuccess() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_idle_sync.wav")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        appState.error.lastAudioURL = tempFile
        appState.error.lastError = "test"

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
        try await waitForPipelineCompletion()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(appState.dictationPhase, .idle)
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

        appState.error.lastAudioURL = tempFile
        appState.error.lastError = "test"
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
        // Use expectation-based wait via helper — captures states deterministically
        let expectation = XCTestExpectation(description: "Pipeline done")
        let previousCallback = controller.onStateChange
        controller.onStateChange = { state in
            previousCallback?(state)
            receivedStates.append(state)
            if case .idle = state { expectation.fulfill() }
            else if case .error = state { expectation.fulfill() }
        }
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertGreaterThan(receivedStates.count, 0, "onStateChange should fire for transitions")
    }
}
