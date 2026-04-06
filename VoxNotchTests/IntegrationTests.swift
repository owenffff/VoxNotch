//
//  IntegrationTests.swift
//  VoxNotchTests
//
//  Integration tests covering the full hotkey → record → transcribe → output path
//  using fully injected mocks. No real audio, transcription, or UI.
//

import XCTest
@testable import VoxNotch

@MainActor
final class IntegrationTests: XCTestCase {

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

        mockTextOutput.hasFocusedTextInputValue = true

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
        appState = nil
        super.tearDown()
    }

    /// Helper: wait for pipeline terminal state
    private func waitForCompletion(timeout: TimeInterval = 2.0) async throws {
        let expectation = XCTestExpectation(description: "Pipeline completed")
        controller.onStateChange = { state in
            if case .idle = state { expectation.fulfill() }
            else if case .error = state { expectation.fulfill() }
        }
        await fulfillment(of: [expectation], timeout: timeout)
    }

    // MARK: - Full Pipeline: record → transcribe → output

    func testFullPipelineRecordTranscribeOutput() async throws {
        // Simulate: hotkey press → beginRecording
        try controller.stateMachine.beginRecording()

        // Verify recording started
        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(mockAudio.startRecordingCallCount, 1)
        XCTAssertEqual(mockNotch.showRecordingCallCount, 1)

        // Simulate: held for 2 seconds, then released
        controller.stateMachine.recordingStartTime = Date().addingTimeInterval(-2)

        mockTranscription.stubbedResult = TranscriptionResult(
            text: "Hello world",
            confidence: 0.95,
            audioDuration: 2.0,
            processingTime: 0.1,
            provider: "Mock",
            language: nil,
            segments: nil
        )

        // Release hotkey → stop and transcribe
        controller.stateMachine.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await waitForCompletion()

        // Verify full pipeline executed
        XCTAssertEqual(mockAudio.stopRecordingCallCount, 1, "Audio should be stopped")
        XCTAssertEqual(mockTranscription.transcribeCallCount, 1, "Transcription should run")
        XCTAssertEqual(mockTextOutput.outputCallCount, 1, "Text should be output")
        XCTAssertEqual(mockTextOutput.lastOutputText, "Hello world")

        // Verify notch showed output result
        XCTAssertEqual(mockNotch.showOutputResultCallCount, 1)

        // Verify state returned to idle
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(appState.dictationPhase, .idle)
    }

    // MARK: - Full Pipeline with LLM Enhancement

    func testFullPipelineWithLLMEnhancement() async throws {
        mockLLM.isEnabled = true
        mockLLM.stubbedResult = .success(processedText: "Hello, world.")

        try controller.stateMachine.beginRecording()
        controller.stateMachine.recordingStartTime = Date().addingTimeInterval(-2)

        mockTranscription.stubbedResult = TranscriptionResult(
            text: "hello world",
            confidence: 0.95,
            audioDuration: 2.0,
            processingTime: 0.1,
            provider: "Mock",
            language: nil,
            segments: nil
        )

        controller.stateMachine.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await waitForCompletion()

        // LLM should have enhanced the text
        XCTAssertEqual(mockTextOutput.lastOutputText, "Hello, world.")
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: - Error Recovery via Retry

    func testErrorThenRetrySucceeds() async throws {
        // Create a temp audio file for the mock to return
        let tempAudio = FileManager.default.temporaryDirectory.appendingPathComponent("integration_error.wav")
        FileManager.default.createFile(atPath: tempAudio.path, contents: Data([0]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempAudio) }
        mockAudio.stubbedCaptureResult = AudioCaptureManager.CaptureResult(
            fileURL: tempAudio, duration: 2.0, sampleRate: 16000
        )

        // First attempt: transcription fails
        try controller.stateMachine.beginRecording()
        controller.stateMachine.recordingStartTime = Date().addingTimeInterval(-2)

        mockTranscription.stubbedError = NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Network timeout"]
        )

        controller.stateMachine.stopRecordingAndTranscribe(savedFrontmostApp: nil)
        try await waitForCompletion()

        // Verify error state
        if case .error = controller.state {} else {
            XCTFail("Expected error state after failed transcription")
        }
        XCTAssertNotNil(appState.error.lastError)

        // Second attempt: retry via state machine with the saved audio file
        mockTranscription.stubbedError = nil
        mockTranscription.stubbedResult = TranscriptionResult(
            text: "Recovered text",
            confidence: 0.9,
            audioDuration: 2.0,
            processingTime: 0.1,
            provider: "Mock",
            language: nil,
            segments: nil
        )
        mockTranscription.transcribeCallCount = 0

        controller.stateMachine.retryTranscription(audioURL: tempAudio, savedFrontmostApp: nil)
        try await waitForCompletion()

        // Verify recovery
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(mockTranscription.transcribeCallCount, 1)
        XCTAssertGreaterThan(mockTextOutput.outputCallCount + mockTextOutput.copyCallCount, 0,
                             "Text should have been output on retry")
    }

    // MARK: - Too Short Recording Cancels

    func testTooShortRecordingCancels() throws {
        try controller.stateMachine.beginRecording()
        // recordingStartTime is just now → duration < 0.5s minimum

        controller.stateMachine.stopRecordingAndTranscribe(savedFrontmostApp: nil)

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(mockTranscription.transcribeCallCount, 0, "Transcription should not run")
        // Notch hide is called by the onPipelineCancelled callback wired in QDC init
        XCTAssertGreaterThan(mockNotch.hideCallCount, 0, "Notch should hide on cancel")
    }
}
