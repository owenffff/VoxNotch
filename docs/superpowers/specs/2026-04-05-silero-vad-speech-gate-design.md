# Silero VAD Speech Gate

## Problem

VoxNotch's phantom word prevention uses a 3-layer heuristic: minimum recording duration (0.5s), RMS energy threshold (-40dB), and ASR confidence filtering (<0.45). The RMS energy check cannot distinguish speech from non-speech noise (keyboard clicks, music, fans). This causes false positives in noisy environments where audio energy exceeds -40dB but contains no human speech.

## Solution

Add an opt-in Silero VAD (Voice Activity Detection) speech gate as an alternative to the RMS energy check. FluidAudio already ships Silero VAD v6 as a CoreML model (~2MB). When enabled, the VAD model runs on the recorded audio before transcription. If no speech is detected, the recording is rejected without calling the ASR model.

Both options coexist: users choose between the fast RMS check (default) and the more accurate VAD check.

## Architecture

### New Setting

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `useVADSpeechGate` | `Bool` | `false` | Use Silero VAD instead of RMS energy for pre-transcription speech detection |

### New Service: VadGate

**File:** `VoxNotch/Services/VadGate.swift`

Singleton wrapping FluidAudio's `VadManager`. Responsibilities:
- Lazy-load `VadManager` on first use (not at app launch)
- Expose `containsSpeech(audioURL:) async throws -> Bool` — runs batch VAD on the full recording, returns true if any speech segment is found
- Expose `isModelAvailable: Bool` — checks if the Silero VAD model exists on disk
- Expose `ensureModelReady() async throws` — downloads the model if not present (called when user enables the toggle)

The `containsSpeech` implementation:
1. Read audio file into `[Float]` samples (16kHz mono, same format AudioCaptureManager already produces)
2. Call `vadManager.process(samples)` to get per-chunk VAD results
3. Return `true` if any chunk has `probability >= threshold` (use VadConfig default of 0.85)

### Integration Point: FluidAudioProvider

**File:** `VoxNotch/Services/Transcription/FluidAudioProvider.swift`

In the `transcribe()` method, replace the unconditional `hasSignificantAudio()` call with a conditional branch:

```swift
if SettingsManager.shared.useVADSpeechGate {
    guard try await VadGate.shared.containsSpeech(audioURL: audioURL) else {
        throw TranscriptionError.noSpeechDetected
    }
} else {
    guard hasSignificantAudio(audioURL: audioURL) else {
        throw TranscriptionError.noSpeechDetected
    }
}
```

Both paths throw the same error. Downstream code is unchanged.

The existing `hasSignificantAudio()` function stays as-is (not deleted).

### Settings UI: RecordingTab

**File:** `VoxNotch/Views/Settings/Tabs/RecordingTab.swift` (or appropriate settings tab)

Add a new section or row for VAD:
- Toggle: "Use voice activity detection" with tooltip: "Uses a neural model to detect speech more accurately than volume-based detection. Requires a one-time ~2MB model download."
- When toggled on:
  - If model not on disk: show download progress (indeterminate or percentage if FluidAudio exposes it), then confirm ready
  - If download fails: revert toggle to off, show brief error
  - If model already on disk: toggle takes effect immediately
- No UI when toggled off (just the toggle itself)

### Model Download Flow

1. User toggles "Use voice activity detection" ON
2. Check `VadGate.shared.isModelAvailable`
3. If available: save setting, done
4. If not: call `VadGate.shared.ensureModelReady()` in a Task
   - Show progress indicator on the toggle row
   - On success: save setting
   - On failure: revert toggle, show error text below the toggle
5. Model is stored at `~/Library/Application Support/FluidAudio/Models/silero-vad-coreml/` (FluidAudio's default location)

### Existing Defenses Kept

| Layer | Mechanism | Status |
|-------|-----------|--------|
| 1 | Minimum recording duration (0.5s) | Unchanged |
| 2a | RMS energy check (-40dB) | Active when VAD is OFF (default) |
| 2b | Silero VAD speech gate | Active when VAD is ON |
| 3 | ASR confidence < 0.45 rejection | Unchanged |

## Files Changed

| File | Change |
|------|--------|
| `VoxNotch/Services/VadGate.swift` | **New.** VadManager wrapper with `containsSpeech()`, `isModelAvailable`, `ensureModelReady()` |
| `VoxNotch/Managers/SettingsManager.swift` | Add `useVADSpeechGate` key and property |
| `VoxNotch/Services/Transcription/FluidAudioProvider.swift` | Conditional branch: VAD or RMS check before transcription |
| `VoxNotch/Views/Settings/Tabs/RecordingTab.swift` | Add VAD toggle with download handling |

## Verification

1. **Build:** `xcodebuild -scheme VoxNotch -configuration Debug build` succeeds
2. **Toggle off (default):** Record and transcribe normally. Behavior identical to current — RMS energy check runs.
3. **Toggle on, model not downloaded:** Toggle triggers download, progress visible, toggle stays on after success.
4. **Toggle on, model ready:** Record silence or keyboard noise — should be rejected (no transcription). Record speech — should transcribe normally.
5. **Download failure:** Toggle reverts to off, error shown. App continues working with RMS check.
6. **Confidence check still active:** Record very faint speech that passes VAD but produces low-confidence ASR — still rejected by the 0.45 threshold.
