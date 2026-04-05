# User-Facing Error Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace developer-facing error messages with short, actionable, user-friendly messages that display properly in the notch and support retry for transcription failures.

**Architecture:** Three changes: (1) rewrite all error `errorDescription` strings to be ≤35 chars and plain language, add `recoverySuggestion` everywhere, (2) update the notch error display to show a subtitle line with the recovery hint and increase auto-hide from 1.5s to 4s, (3) add transcription retry by saving the last audio URL in AppState and adding a retry path in QuickDictationController.

**Tech Stack:** Swift, SwiftUI, XCTest

---

## File Structure

### Modified Files

| File | Changes |
|---|---|
| `VoxNotch/Services/TranscriptionService.swift` | Rewrite TranscriptionError messages |
| `VoxNotch/Managers/FluidAudioModelManager.swift` | Rewrite FluidAudioError messages, add recoverySuggestion |
| `VoxNotch/Managers/MLXAudioModelManager.swift` | Rewrite MLXAudioError messages, add recoverySuggestion |
| `VoxNotch/Services/TextOutputManager.swift` | Rewrite TextOutputError messages |
| `VoxNotch/Services/AudioCaptureManager.swift` | Rewrite AudioCaptureError messages |
| `VoxNotch/Services/LLM/LLMProvider.swift` | Rewrite LLMError messages |
| `VoxNotch/Notch/NotchExpandedFallbackView.swift` | Add subtitle line for recovery suggestion, remove `compact: true` |
| `VoxNotch/Notch/CompactTrailingView.swift` | Show shortened error in compact mode |
| `VoxNotch/Notch/NotchManager.swift` | Increase error auto-hide to 4s |
| `VoxNotch/App/AppState.swift` | Add `lastErrorRecovery: String?` and `lastAudioURL: URL?` |
| `VoxNotch/Controllers/QuickDictationController.swift` | Extract recovery suggestion from errors, save audio URL, add retry |
| `VoxNotchTests/TranscriptionServiceTests.swift` | Test error message content |

---

### Task 1: Rewrite Error Messages

**Files:**
- Modify: `VoxNotch/Services/TranscriptionService.swift` (lines 65-126)
- Modify: `VoxNotch/Managers/FluidAudioModelManager.swift` (lines 461-479)
- Modify: `VoxNotch/Managers/MLXAudioModelManager.swift` (lines 621-642)
- Modify: `VoxNotch/Services/TextOutputManager.swift` (lines 17-35)
- Modify: `VoxNotch/Services/AudioCaptureManager.swift` (lines 18-39)
- Modify: `VoxNotch/Services/LLM/LLMProvider.swift` (lines 25-54)
- Test: `VoxNotchTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write tests for user-friendly error messages**

Add to `VoxNotchTests/TranscriptionServiceTests.swift`:

```swift
  // MARK: - Error Messages

  func testErrorMessagesAreShort() {
    // All error descriptions should fit in the notch (~35 chars)
    let errors: [TranscriptionError] = [
      .providerNotReady, .fileNotFound, .invalidFormat,
      .fileTooSmall, .fileCorrupted, .audioTooShort,
      .noSpeechDetected, .modelNotLoaded, .timeout,
      .transcriptionFailed("some underlying error"),
    ]
    for error in errors {
      let desc = error.errorDescription ?? ""
      XCTAssertLessThanOrEqual(
        desc.count, 40,
        "Error '\(error)' description too long for notch: \"\(desc)\" (\(desc.count) chars)"
      )
    }
  }

  func testAllErrorsHaveRecoverySuggestion() {
    let errors: [TranscriptionError] = [
      .providerNotReady, .fileNotFound, .invalidFormat,
      .fileTooSmall, .fileCorrupted, .audioTooShort,
      .noSpeechDetected, .modelNotLoaded, .timeout,
      .transcriptionFailed("some error"),
    ]
    for error in errors {
      XCTAssertNotNil(
        error.recoverySuggestion,
        "Error '\(error)' is missing a recoverySuggestion"
      )
    }
  }

  func testErrorMessagesAreUserFriendly() {
    // Should NOT contain developer jargon
    let errors: [TranscriptionError] = [
      .providerNotReady, .invalidFormat, .fileCorrupted,
      .transcriptionFailed("engine error"), .modelNotLoaded,
    ]
    let jargon = ["FluidAudio", "MLX", "16kHz", "mono", "Float32", "provider", "engine"]
    for error in errors {
      let desc = (error.errorDescription ?? "") + (error.recoverySuggestion ?? "")
      for term in jargon {
        XCTAssertFalse(
          desc.contains(term),
          "Error '\(error)' contains developer jargon '\(term)': \"\(desc)\""
        )
      }
    }
  }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme VoxNotch -only-testing VoxNotchTests/TranscriptionServiceTests -destination 'platform=macOS' 2>&1 | grep -E "(FAIL|passed|failed)" | head -10
```

Expected: `testErrorMessagesAreShort` and `testAllErrorsHaveRecoverySuggestion` fail (current messages are too long / missing suggestions).

- [ ] **Step 3: Rewrite TranscriptionError**

In `VoxNotch/Services/TranscriptionService.swift`, replace the `errorDescription` and `recoverySuggestion` computed properties (lines 77-125):

```swift
    var errorDescription: String? {
        switch self {
        case .providerNotReady:
            return "Speech model not ready"
        case .fileNotFound:
            return "Recording not found"
        case .invalidFormat:
            return "Recording format not supported"
        case .fileTooSmall:
            return "Recording too short"
        case .fileCorrupted:
            return "Recording is corrupted"
        case .audioTooShort:
            return "Recording too short"
        case .noSpeechDetected:
            return "No speech detected"
        case .transcriptionFailed:
            return "Transcription failed"
        case .modelNotLoaded:
            return "Speech model not downloaded"
        case .timeout:
            return "Timed out"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .audioTooShort, .noSpeechDetected:
            return "Try speaking longer or louder"
        case .modelNotLoaded, .providerNotReady:
            return "Open Settings → Speech Model to download"
        case .fileCorrupted, .invalidFormat, .fileTooSmall, .fileNotFound:
            return "Try recording again"
        case .timeout:
            return "Check your connection and try again"
        case .transcriptionFailed:
            return "Try again — or switch models in Settings"
        }
    }
```

Key changes:
- Removed `transcriptionFailed(String)` message passthrough — always show "Transcription failed" (the raw message was developer-facing)
- Removed "Speech engine error (beta)" special case
- Removed the >30 char truncation logic — all messages are now short
- Removed "Open Settings to download." from `errorDescription` (moved to `recoverySuggestion`)
- Every case now has a recovery suggestion

- [ ] **Step 4: Rewrite FluidAudioError**

In `VoxNotch/Managers/FluidAudioModelManager.swift`, replace the `FluidAudioError` enum's `errorDescription`:

```swift
enum FluidAudioError: LocalizedError {
  case modelNotLoaded
  case modelDownloadFailed(String)
  case transcriptionFailed(String)
  case invalidAudioFormat

  var errorDescription: String? {
    switch self {
    case .modelNotLoaded:
      return "Speech model not loaded"
    case .modelDownloadFailed:
      return "Model download failed"
    case .transcriptionFailed:
      return "Transcription failed"
    case .invalidAudioFormat:
      return "Audio format not supported"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .modelNotLoaded:
      return "Open Settings → Speech Model to download"
    case .modelDownloadFailed:
      return "Check your connection and try again"
    case .transcriptionFailed:
      return "Try again — or switch models in Settings"
    case .invalidAudioFormat:
      return "Try recording again"
    }
  }
}
```

- [ ] **Step 5: Rewrite MLXAudioError**

In `VoxNotch/Managers/MLXAudioModelManager.swift`, replace the `MLXAudioError` enum:

```swift
enum MLXAudioError: LocalizedError {
  case modelNotLoaded
  case modelDownloadFailed(String)
  case transcriptionFailed(String)
  case invalidAudioFormat
  case audioLoadFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotLoaded:
      return "Speech model not loaded"
    case .modelDownloadFailed:
      return "Model download failed"
    case .transcriptionFailed:
      return "Transcription failed"
    case .invalidAudioFormat:
      return "Audio format not supported"
    case .audioLoadFailed:
      return "Could not read audio file"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .modelNotLoaded:
      return "Open Settings → Speech Model to download"
    case .modelDownloadFailed:
      return "Check your connection and try again"
    case .transcriptionFailed:
      return "Try again — or switch models in Settings"
    case .invalidAudioFormat, .audioLoadFailed:
      return "Try recording again"
    }
  }
}
```

- [ ] **Step 6: Rewrite AudioCaptureError**

In `VoxNotch/Services/AudioCaptureManager.swift`, replace the `AudioCaptureError` enum's `errorDescription` and add `recoverySuggestion`:

```swift
    var errorDescription: String? {
        switch self {
        case .noInputAvailable:
            return "No microphone found"
        case .engineStartFailed:
            return "Microphone failed to start"
        case .permissionDenied:
            return "Microphone access denied"
        case .noAudioRecorded:
            return "No audio was recorded"
        case .fileWriteFailed:
            return "Could not save recording"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noInputAvailable:
            return "Connect a microphone and try again"
        case .engineStartFailed:
            return "Try again — restart the app if it persists"
        case .permissionDenied:
            return "Grant access in System Settings → Privacy"
        case .noAudioRecorded:
            return "Try speaking louder or longer"
        case .fileWriteFailed:
            return "Try again — check disk space if it persists"
        }
    }
```

- [ ] **Step 7: Rewrite TextOutputError**

In `VoxNotch/Services/TextOutputManager.swift`, replace the `TextOutputError` enum:

```swift
    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility access needed"
        case .noActiveApplication:
            return "No app to receive text"
        case .keystrokeFailed:
            return "Could not type text"
        case .clipboardFailed:
            return "Could not paste text"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Grant access in System Settings → Privacy"
        case .noActiveApplication:
            return "Click into an app first, then try again"
        case .keystrokeFailed, .clipboardFailed:
            return "Text was copied to clipboard instead"
        }
    }
```

- [ ] **Step 8: Rewrite LLMError**

In `VoxNotch/Services/LLM/LLMProvider.swift`, replace the `LLMError` enum:

```swift
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key missing"
        case .invalidURL:
            return "Invalid API endpoint"
        case .networkError:
            return "Network error"
        case .invalidResponse:
            return "Bad response from API"
        case .apiError:
            return "API returned an error"
        case .timeout:
            return "Request timed out"
        case .rateLimited:
            return "Too many requests"
        case .decodingError:
            return "Unexpected API response"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noAPIKey:
            return "Add your API key in Settings → Tones"
        case .invalidURL:
            return "Check the endpoint URL in Settings"
        case .networkError, .timeout:
            return "Check your connection and try again"
        case .invalidResponse, .decodingError:
            return "Try again — or switch to a different model"
        case .apiError:
            return "Check your API key and model settings"
        case .rateLimited:
            return "Wait a moment and try again"
        }
    }
```

- [ ] **Step 9: Run tests to verify they pass**

```bash
xcodebuild test -scheme VoxNotch -only-testing VoxNotchTests -destination 'platform=macOS' 2>&1 | grep -E "(Executed|TEST)" | tail -3
```

Expected: All tests pass, including the new error message tests.

- [ ] **Step 10: Commit**

```bash
git add VoxNotch/Services/TranscriptionService.swift VoxNotch/Managers/FluidAudioModelManager.swift VoxNotch/Managers/MLXAudioModelManager.swift VoxNotch/Services/TextOutputManager.swift VoxNotch/Services/AudioCaptureManager.swift VoxNotch/Services/LLM/LLMProvider.swift VoxNotchTests/TranscriptionServiceTests.swift
git commit -m "fix: rewrite all error messages to be user-friendly and ≤35 chars"
```

---

### Task 2: Show Recovery Suggestion in Notch

**Files:**
- Modify: `VoxNotch/App/AppState.swift` (line 41)
- Modify: `VoxNotch/Controllers/QuickDictationController.swift` (lines 874-894)
- Modify: `VoxNotch/Notch/NotchExpandedFallbackView.swift` (lines 65-71, 221-233)
- Modify: `VoxNotch/Notch/NotchManager.swift` (line 122)
- Modify: `VoxNotch/Notch/CompactTrailingView.swift` (lines 55-56)

- [ ] **Step 1: Add recovery suggestion to AppState**

In `VoxNotch/App/AppState.swift`, after `lastError` (line 41), add:

```swift
  var lastError: String?
  var lastErrorRecovery: String?
```

In the `reset()` method, also clear it:

```swift
  lastErrorRecovery = nil
```

In `clearError()`, also clear it:

```swift
  func clearError() {
    lastError = nil
    lastErrorRecovery = nil
  }
```

- [ ] **Step 2: Extract recovery suggestion in QuickDictationController**

In `VoxNotch/Controllers/QuickDictationController.swift`, modify the `.error(let error)` case (line 874-882) to also extract `recoverySuggestion`:

```swift
            case .error(let error):
                appState.isRecording = false
                appState.isWarmingUp = false
                appState.isTranscribing = false
                appState.isProcessingLLM = false
                appState.lastError = error.localizedDescription
                appState.lastErrorRecovery = (error as? LocalizedError)?.recoverySuggestion
                appState.silenceWarningActive = false
                appState.isModelSelecting = false
                appState.isToneSelecting = false
```

- [ ] **Step 3: Add subtitle support to notch transientRow**

In `VoxNotch/Notch/NotchExpandedFallbackView.swift`, modify the `transientRow` function (lines 221-233) to support an optional subtitle:

```swift
  private func transientRow(icon: String, color: Color, title: String, subtitle: String? = nil, compact: Bool = false) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: compact ? 10 : 12))
        .foregroundStyle(color)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: compact ? 10 : 12, weight: .medium))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.tail)

        if let subtitle {
          Text(subtitle)
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
    }
  }
```

- [ ] **Step 4: Pass recovery suggestion to error display**

In `NotchExpandedFallbackView.swift`, update the error display (lines 65-71) to pass the recovery suggestion as subtitle:

```swift
    } else if let error = appState.lastError {
      transientRow(
        icon: "xmark.circle.fill",
        color: .red,
        title: shortenError(error),
        subtitle: appState.lastErrorRecovery
      )
```

Note: removed `compact: true` — error messages are now short enough, and the subtitle needs normal sizing.

- [ ] **Step 5: Increase error auto-hide timer**

In `VoxNotch/Notch/NotchManager.swift`, change the error auto-hide from 1.5s to 4s (line 122):

```swift
  func showError(_ message: String) {
    cancelAutoHide()
    showExpanded()
    scheduleAutoHide(after: 4.0)
  }
```

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme VoxNotch -configuration Debug build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Run tests**

```bash
xcodebuild test -scheme VoxNotch -only-testing VoxNotchTests -destination 'platform=macOS' 2>&1 | grep -E "(Executed|TEST)" | tail -3
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add VoxNotch/App/AppState.swift VoxNotch/Controllers/QuickDictationController.swift VoxNotch/Notch/NotchExpandedFallbackView.swift VoxNotch/Notch/NotchManager.swift
git commit -m "feat: show recovery suggestions in notch, increase error display to 4s"
```

---

### Task 3: Add Transcription Retry

**Files:**
- Modify: `VoxNotch/App/AppState.swift`
- Modify: `VoxNotch/Controllers/QuickDictationController.swift`
- Modify: `VoxNotch/Notch/NotchExpandedFallbackView.swift`

- [ ] **Step 1: Add retry state to AppState**

In `VoxNotch/App/AppState.swift`, add after `lastErrorRecovery`:

```swift
  /// URL of the last recorded audio file (for retry)
  var lastAudioURL: URL?

  /// Whether transcription retry is available
  var canRetryTranscription: Bool {
    lastError != nil && lastAudioURL != nil
  }
```

In `reset()`, clear it:

```swift
  lastAudioURL = nil
```

- [ ] **Step 2: Save audio URL on transcription failure**

In `VoxNotch/Controllers/QuickDictationController.swift`, inside the `stopRecordingAndTranscribe()` method, find where the audio file URL is available (after `audioManager.stopRecording()`). The audio file URL is in `captureResult.fileURL`.

In the catch block (around line 531-540), save the audio URL to AppState:

```swift
} catch {
    guard capturedSessionID == self.currentSessionID else {
        print("QuickDictationController: Session cancelled during error handling, discarding")
        return
    }
    print("QuickDictationController: Transcription failed: \(error)")
    await MainActor.run {
        self.appState.lastAudioURL = captureResult.fileURL
        updateState(.error(error))
    }
}
```

Also clear `lastAudioURL` on successful transcription (after text output succeeds, before `updateState(.idle)`):

```swift
self.appState.lastAudioURL = nil
```

- [ ] **Step 3: Add retryTranscription() method**

In `VoxNotch/Controllers/QuickDictationController.swift`, add a new public method:

```swift
    /// Retry transcription using the last recorded audio file
    func retryTranscription() {
        guard let audioURL = appState.lastAudioURL else { return }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            appState.lastAudioURL = nil
            return
        }

        let capturedSessionID = currentSessionID
        appState.lastError = nil
        appState.lastErrorRecovery = nil

        Task {
            do {
                updateState(.warmingUp)
                try await TranscriptionService.shared.ensureModelReady()

                guard capturedSessionID == self.currentSessionID else { return }

                updateState(.transcribing)
                let result = try await TranscriptionService.shared.transcribe(audioURL: audioURL)

                guard capturedSessionID == self.currentSessionID else { return }

                var text = result.text

                // Apply post-processing
                if SettingsManager.shared.removeFillerWords {
                    text = text.replacingOccurrences(of: "\\b(um|uh|hmm|like|you know)\\b", with: "", options: [.regularExpression, .caseInsensitive])
                        .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }

                guard !text.isEmpty else {
                    await MainActor.run { updateState(.error(TranscriptionError.noSpeechDetected)) }
                    return
                }

                // Skip LLM processing for retry — output directly
                await MainActor.run {
                    self.appState.lastAudioURL = nil
                }
                await outputText(text)

            } catch {
                guard capturedSessionID == self.currentSessionID else { return }
                await MainActor.run {
                    updateState(.error(error))
                }
            }
        }
    }
```

- [ ] **Step 4: Add retry button to notch error display**

In `VoxNotch/Notch/NotchExpandedFallbackView.swift`, update the error display to include a retry indicator when available:

```swift
    } else if let error = appState.lastError {
      HStack(spacing: 8) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 12))
          .foregroundStyle(.red)

        VStack(alignment: .leading, spacing: 1) {
          Text(shortenError(error))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)

          if let recovery = appState.lastErrorRecovery {
            Text(appState.canRetryTranscription ? "Press hotkey to retry" : recovery)
              .font(.system(size: 9, weight: .regular))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
      }
```

This replaces the `transientRow` call for errors with an inline view so we can customize the subtitle based on retry availability.

- [ ] **Step 5: Wire retry into hotkey handler**

In `VoxNotch/Controllers/QuickDictationController.swift`, in the `startRecording()` method, check if retry is available before starting a new recording. Near the beginning of `startRecording()` (around line 245), add before the model download check:

```swift
        // If we have a failed transcription with saved audio, retry instead of recording again
        if appState.canRetryTranscription {
            retryTranscription()
            return
        }
```

This means pressing the hotkey while an error is displayed will retry the last transcription instead of starting a new recording. Once the retry succeeds or the user starts a new recording (which clears the error), normal flow resumes.

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme VoxNotch -configuration Debug build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Run tests**

```bash
xcodebuild test -scheme VoxNotch -only-testing VoxNotchTests -destination 'platform=macOS' 2>&1 | grep -E "(Executed|TEST)" | tail -3
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add VoxNotch/App/AppState.swift VoxNotch/Controllers/QuickDictationController.swift VoxNotch/Notch/NotchExpandedFallbackView.swift
git commit -m "feat: add transcription retry on hotkey press after failure"
```

---

## Summary

After completing all 3 tasks:

- **Every error message** is ≤35 chars, plain language, no developer jargon
- **Every error has a recovery suggestion** displayed as a subtitle in the notch
- **Error display stays visible for 4 seconds** (up from 1.5s)
- **Transcription retry:** pressing the hotkey while an error is shown retries with the last audio file
- **Subtitle shows "Press hotkey to retry"** when retry is available, otherwise shows the recovery suggestion
- **Tests verify** message length, jargon-free content, and recovery suggestion presence
