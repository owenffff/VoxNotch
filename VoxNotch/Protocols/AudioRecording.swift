//
//  AudioRecording.swift
//  VoxNotch
//
//  Protocol abstracting AudioCaptureManager for testability.
//

import Foundation

/// Abstraction over audio capture so QuickDictationController can be tested with mocks.
protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    var accumulateBuffers: Bool { get set }
    var hasMicrophonePermission: Bool { get }
    var onSilenceWarning: (() -> Void)? { get set }
    var onSilenceThresholdReached: (() -> Void)? { get set }
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void)
    func startRecording() throws
    func stopRecording() throws -> AudioCaptureManager.CaptureResult
    func cancelRecording()
    func cleanupFile(at url: URL)
}

extension AudioCaptureManager: AudioRecording {}
