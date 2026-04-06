//
//  NotchViewModelTests.swift
//  VoxNotchTests
//
//  Tests NotchViewModel display phase logic without SwiftUI.
//

import XCTest
@testable import VoxNotch

@MainActor
final class NotchViewModelTests: XCTestCase {

    private var appState: AppState!
    private var notchManager: NotchManager!
    private var vm: NotchViewModel!

    override func setUp() {
        super.setUp()
        appState = AppState(forTesting: ())
        notchManager = NotchManager.shared
        notchManager.clearTransient()
        vm = NotchViewModel(
            appState: appState,
            notchManager: notchManager,
            audioViz: AudioVisualizationState.shared
        )
    }

    override func tearDown() {
        vm = nil
        appState = nil
        super.tearDown()
    }

    // MARK: - Display Phase

    func testIdlePhase() {
        XCTAssertEqual(vm.displayPhase, .idle)
    }

    func testRecordingPhase() {
        appState.dictationPhase = .recording
        XCTAssertEqual(vm.displayPhase, .recording)
    }

    func testTranscribingPhase() {
        appState.dictationPhase = .transcribing
        XCTAssertEqual(vm.displayPhase, .transcribing)
    }

    func testProcessingLLMPhase() {
        appState.dictationPhase = .processingLLM
        XCTAssertEqual(vm.displayPhase, .processingLLM)
    }

    func testDownloadingPhase() {
        appState.modelDownload.isDownloadingModel = true
        XCTAssertEqual(vm.displayPhase, .downloading)
    }

    func testModelsNeededPhase() {
        appState.modelDownload.modelsNeeded = true
        XCTAssertEqual(vm.displayPhase, .modelsNeeded)
    }

    func testErrorPhase() {
        appState.error.lastError = "Something went wrong"
        XCTAssertEqual(vm.displayPhase, .error)
    }

    func testModelSelectingPhase() {
        appState.dictationPhase = .modelSelecting
        XCTAssertEqual(vm.displayPhase, .modelSelecting)
    }

    func testToneSelectingPhase() {
        appState.dictationPhase = .toneSelecting
        XCTAssertEqual(vm.displayPhase, .toneSelecting)
    }

    // MARK: - Priority: dictationPhase overrides transient state

    func testRecordingOverridesError() {
        appState.error.lastError = "stale error"
        appState.dictationPhase = .recording
        XCTAssertEqual(vm.displayPhase, .recording)
    }

    // MARK: - Status Text

    func testStatusTextIdle() {
        XCTAssertEqual(vm.statusText, "VoxNotch")
    }

    func testStatusTextWarmingUp() {
        appState.dictationPhase = .warmingUp
        XCTAssertEqual(vm.statusText, "Warming up...")
    }

    func testStatusTextError() {
        appState.error.lastError = "Mic not found"
        XCTAssertEqual(vm.statusText, "Mic not found")
    }

    func testStatusTextDownloading() {
        appState.modelDownload.isDownloadingModel = true
        appState.modelDownload.modelDownloadProgress = 0.42
        XCTAssertEqual(vm.statusText, "42%")
    }

    // MARK: - Duration Formatting

    func testDurationFormatting() {
        appState.dictationPhase = .recording
        appState.recordingDuration = 65
        XCTAssertEqual(vm.statusText, "1:05")
    }
}
