//
//  FluidAudioProvider.swift
//  VoxNotch
//
//  Transcription provider using FluidAudio's AsrManager for batch transcription
//

import Accelerate
import AVFoundation
import FluidAudio
import Foundation
import os.log

/// Speech-to-text provider using FluidAudio's AsrManager
/// Implements TranscriptionProvider protocol for seamless integration
final class FluidAudioProvider: TranscriptionProvider, @unchecked Sendable {

  // MARK: - Properties

  let name = "FluidAudio"

  private let logger = Logger(subsystem: "com.jingyuanliang.VoxNotch", category: "FluidAudioProvider")
  private let modelManager = FluidAudioModelManager.shared

  /// ASR manager instance
  private var asrManager: AsrManager?

  /// Lock for thread safety
  private let lock = NSLock()

  // MARK: - TranscriptionProvider

  var isReady: Bool {
    get async {
      modelManager.isReady
    }
  }

  func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
    let startTime = Date()

    // Ensure models are loaded (no auto-download)
    guard modelManager.getLoadedModels() != nil else {
      throw TranscriptionError.modelNotLoaded
    }

    // Initialize ASR manager if needed
    try await ensureAsrManagerInitialized()

    guard let asr = asrManager else {
      throw FluidAudioError.modelNotLoaded
    }

    // Check if audio contains actual speech energy (not just silence/noise)
    guard hasSignificantAudio(audioURL: audioURL) else {
      throw TranscriptionError.noSpeechDetected
    }

    // Ensure audio meets FluidAudio's 1-second minimum, pad with silence if needed
    let transcriptionURL = try ensureMinimumDuration(audioURL: audioURL)
    let didPad = transcriptionURL != audioURL

    // Transcribe audio file
    let result: ASRResult
    do {
      result = try await asr.transcribe(transcriptionURL)
    } catch {
      // Clean up padded temp file if we created one
      if didPad { try? FileManager.default.removeItem(at: transcriptionURL) }

      let desc = error.localizedDescription
      if desc.contains("at least 1 second") || desc.contains("Invalid audio data") {
        throw TranscriptionError.audioTooShort
      }
      logger.error("FluidAudio transcription failed: \(desc)")
      throw FluidAudioError.transcriptionFailed(desc)
    }

    // Clean up padded temp file if we created one
    if didPad { try? FileManager.default.removeItem(at: transcriptionURL) }

    let processingTime = Date().timeIntervalSince(startTime)

    // Convert ASRResult to TranscriptionResult
    let text = result.text

    // Handle empty transcription
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw TranscriptionError.noSpeechDetected
    }

    // Build segments from token timings if available
    var segments: [TranscriptSegment]?
    if let timings = result.tokenTimings, !timings.isEmpty {
      segments = buildSegments(from: timings)
    }

    return TranscriptionResult(
      text: text,
      confidence: result.confidence,
      audioDuration: result.duration,
      processingTime: processingTime,
      provider: name,
      language: language,
      segments: segments
    )
  }

  // MARK: - Model Management

  /// Load a specific model version
  func loadModel(version: FluidAudioModelVersion) async throws {
    _ = try await modelManager.downloadAndLoad(version: version)
    try await ensureAsrManagerInitialized()
  }

  /// Ensure ASR manager is initialized with current models
  private func ensureAsrManagerInitialized() async throws {
    lock.lock()
    let needsInit = asrManager == nil
    lock.unlock()

    guard needsInit else { return }

    guard let models = modelManager.getLoadedModels() else {
      throw FluidAudioError.modelNotLoaded
    }

    let manager = AsrManager()
    try await manager.initialize(models: models)

    lock.lock()
    asrManager = manager
    lock.unlock()

    logger.info("ASR manager initialized")
  }

  /// Reinitialize after model change
  func reinitialize() async throws {
    lock.lock()
    asrManager = nil
    lock.unlock()

    try await ensureAsrManagerInitialized()
  }

  // MARK: - Private Helpers

  /// Minimum audio duration required by FluidAudio (16kHz samples)
  private let minimumSampleCount = 16000 // 1 second at 16kHz

  /// Ensure audio file has at least 1 second of 16kHz audio.
  /// If too short, returns a new URL to a silence-padded copy; otherwise returns the original URL.
  private func ensureMinimumDuration(audioURL: URL) throws -> URL {
    let audioFile = try AVAudioFile(forReading: audioURL)
    let sampleRate = audioFile.processingFormat.sampleRate
    let frameCount = AVAudioFrameCount(audioFile.length)
    let durationSamples = Int(Double(frameCount) * (16000.0 / sampleRate))

    guard durationSamples < minimumSampleCount else {
      return audioURL // Already long enough
    }

    logger.info("Audio too short (\(frameCount) frames at \(sampleRate)Hz), padding with silence")

    // Read existing audio
    guard let readBuffer = AVAudioPCMBuffer(
      pcmFormat: audioFile.processingFormat,
      frameCapacity: frameCount
    ) else {
      throw TranscriptionError.audioTooShort
    }
    try audioFile.read(into: readBuffer)

    // Convert to 16kHz mono if needed
    let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16000,
      channels: 1,
      interleaved: false
    )!

    let convertedBuffer: AVAudioPCMBuffer
    if audioFile.processingFormat.sampleRate != 16000 || audioFile.processingFormat.channelCount != 1 {
      guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: outputFormat) else {
        throw TranscriptionError.audioTooShort
      }
      let ratio = 16000.0 / sampleRate
      let outputCapacity = AVAudioFrameCount(Double(frameCount) * ratio)
      guard let buf = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
        throw TranscriptionError.audioTooShort
      }
      var error: NSError?
      converter.convert(to: buf, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        return readBuffer
      }
      if let error { throw error }
      convertedBuffer = buf
    } else {
      convertedBuffer = readBuffer
    }

    // Create padded buffer (at least 1 second)
    let existingFrames = Int(convertedBuffer.frameLength)
    let totalFrames = max(minimumSampleCount, existingFrames)
    guard let paddedBuffer = AVAudioPCMBuffer(
      pcmFormat: outputFormat,
      frameCapacity: AVAudioFrameCount(totalFrames)
    ) else {
      throw TranscriptionError.audioTooShort
    }

    // Copy existing samples
    if let src = convertedBuffer.floatChannelData, let dst = paddedBuffer.floatChannelData {
      dst[0].update(from: src[0], count: existingFrames)
      // Remaining frames are already zeroed (silence)
    }
    paddedBuffer.frameLength = AVAudioFrameCount(totalFrames)

    // Write to temp file
    let paddedURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("voxnotch_padded_\(UUID().uuidString).wav")
    let outputFile = try AVAudioFile(
      forWriting: paddedURL,
      settings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
      ]
    )
    try outputFile.write(from: paddedBuffer)

    return paddedURL
  }

  /// Build transcript segments from token timings
  private func buildSegments(from timings: [TokenTiming]) -> [TranscriptSegment] {
    var segments: [TranscriptSegment] = []
    var currentText = ""
    var segmentStart: TimeInterval = 0
    var segmentEnd: TimeInterval = 0
    var segmentId = 0

    for timing in timings {
      // Start new segment on sentence boundaries
      let isPunctuation = timing.token.last?.isPunctuation ?? false

      currentText += timing.token
      segmentEnd = timing.endTime

      if segmentStart == 0 {
        segmentStart = timing.startTime
      }

      // Split on sentence-ending punctuation
      if isPunctuation && (timing.token.contains(".") || timing.token.contains("?") || timing.token.contains("!")) {
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
          segments.append(TranscriptSegment(
            id: segmentId,
            start: segmentStart,
            end: segmentEnd,
            text: trimmedText
          ))
          segmentId += 1
        }
        currentText = ""
        segmentStart = 0
      }
    }

    // Add remaining text as final segment
    let remainingText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !remainingText.isEmpty {
      segments.append(TranscriptSegment(
        id: segmentId,
        start: segmentStart,
        end: segmentEnd,
        text: remainingText
      ))
    }

    return segments
  }

  /// Check if audio contains significant energy above noise floor.
  /// Returns false for near-silent recordings that would produce phantom words.
  private func hasSignificantAudio(audioURL: URL, thresholdDB: Float = -40.0) -> Bool {
    guard let audioFile = try? AVAudioFile(forReading: audioURL) else { return true }
    let frameCount = AVAudioFrameCount(audioFile.length)
    guard frameCount > 0 else { return false }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else { return true }
    guard let _ = try? audioFile.read(into: buffer) else { return true }
    guard let channelData = buffer.floatChannelData else { return true }

    var rms: Float = 0
    vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(buffer.frameLength))

    let db = 20.0 * log10(max(rms, 1e-10))
    logger.info("Pre-transcription audio energy: \(db, privacy: .public) dB (threshold: \(thresholdDB, privacy: .public) dB)")
    return db >= thresholdDB
  }
}
