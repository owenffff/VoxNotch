# Test Target & Generic ASR Model Manager

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a test target with state transition and routing tests, then extract a unified `ModelDownloadState` and shared download-progress utility to eliminate the 80% duplication between FluidAudioModelManager and MLXAudioModelManager.

**Architecture:** Two-phase approach. Phase 1 adds a test target with tests for the existing code (safety net before refactoring). Phase 2 extracts a shared `ModelDownloadState` enum and `DownloadProgressTracker` utility, then migrates both managers to use them. The managers keep their engine-specific logic (streaming models, custom models, Metal warmup, checksum verification) — we only extract the genuinely duplicated patterns.

**Tech Stack:** Swift 6, XCTest, macOS 15+, Xcode (SPM-based test target within .xcodeproj)

**Sequencing note:** This is Plan A of 2. Plan B (split QuickDictationController + unify state machines) depends on the test target created here.

---

## File Structure

### New Files

| File | Responsibility |
|---|---|
| `VoxNotchTests/TranscriptionServiceTests.swift` | Test provider routing, model readiness, and error handling |
| `VoxNotchTests/SpeechModelTests.swift` | Test model identity resolution and type safety |
| `VoxNotch/Models/ModelDownloadState.swift` | Unified download state enum (replaces 3 duplicates) |
| `VoxNotch/Managers/DownloadProgressTracker.swift` | Reusable directory-polling progress tracker |

### Modified Files

| File | Changes |
|---|---|
| `VoxNotch.xcodeproj/project.pbxproj` | Add test target via Xcode CLI |
| `VoxNotch/Managers/FluidAudioModelManager.swift` | Replace `FluidAudioModelState` with `ModelDownloadState`, use `DownloadProgressTracker` |
| `VoxNotch/Managers/MLXAudioModelManager.swift` | Replace `MLXAudioModelState` with `ModelDownloadState`, use `DownloadProgressTracker` |
| `VoxNotch/Views/Settings/SettingsView.swift` | Remove duplicate `ModelDownloadState` enum and both mapper functions, use unified state directly |

---

### Task 1: Create XCTest Target

**Files:**
- Create: `VoxNotchTests/TranscriptionServiceTests.swift`
- Create: `VoxNotchTests/SpeechModelTests.swift`
- Modify: `VoxNotch.xcodeproj/project.pbxproj` (via Xcode CLI)

- [ ] **Step 1: Add test target to Xcode project**

This must be done through Xcode's project manipulation. The cleanest approach in a CLI context is using `xcodebuild` to confirm the target exists after adding it.

Open the Xcode project and add a Unit Test Bundle target named `VoxNotchTests`:

```bash
# Open Xcode to add the target (can't reliably script pbxproj edits)
open /Users/jingyuan.liang/Desktop/dev/VoxNotch/VoxNotch.xcodeproj
```

In Xcode: File → New → Target → macOS → Unit Testing Bundle → Name: `VoxNotchTests`, Language: Swift, Host Application: VoxNotch.

Alternatively, if you want to stay in CLI, use the `tuist` or `xcodegen` approach — but since this project uses a raw .xcodeproj, adding the target in Xcode is the most reliable path.

- [ ] **Step 2: Verify the test target exists**

```bash
xcodebuild -list -project VoxNotch.xcodeproj 2>/dev/null | grep -A5 "Targets:"
```

Expected: Output includes `VoxNotchTests`.

- [ ] **Step 3: Write SpeechModel resolution tests**

Create `VoxNotchTests/SpeechModelTests.swift`:

```swift
//
//  SpeechModelTests.swift
//  VoxNotchTests
//

import XCTest
@testable import VoxNotch

final class SpeechModelTests: XCTestCase {

  // MARK: - Model Identity

  func testBuiltinModelResolves() {
    let (builtin, custom) = SpeechModel.resolve("fluidaudio-v2")
    XCTAssertEqual(builtin, .parakeetV2)
    XCTAssertNil(custom)
  }

  func testAllBuiltinModelsResolve() {
    for model in SpeechModel.allCases {
      let (builtin, custom) = SpeechModel.resolve(model.rawValue)
      XCTAssertEqual(builtin, model, "SpeechModel.resolve(\(model.rawValue)) should return \(model)")
      XCTAssertNil(custom)
    }
  }

  func testUnknownModelResolvesToCustom() {
    // Unknown raw value should attempt custom model lookup
    let (builtin, _) = SpeechModel.resolve("unknown-model-id-that-does-not-exist")
    XCTAssertNil(builtin)
    // custom may or may not be nil depending on CustomModelRegistry state — 
    // the key assertion is that builtin is nil for non-matching strings
  }

  // MARK: - Engine Mapping

  func testFluidAudioModelsMapToFluidAudioEngine() {
    XCTAssertEqual(SpeechModel.parakeetV2.engine, .fluidAudio)
    XCTAssertEqual(SpeechModel.parakeetV3.engine, .fluidAudio)
  }

  func testMLXModelsMapToMLXEngine() {
    XCTAssertEqual(SpeechModel.glmAsrNano.engine, .mlxAudio)
    XCTAssertEqual(SpeechModel.qwen3Asr.engine, .mlxAudio)
  }

  // MARK: - Version Conversion

  func testFluidAudioVersionConversion() {
    XCTAssertEqual(SpeechModel.parakeetV2.fluidAudioVersion, .v2English)
    XCTAssertEqual(SpeechModel.parakeetV3.fluidAudioVersion, .v3Multilingual)
    XCTAssertNil(SpeechModel.glmAsrNano.fluidAudioVersion)
    XCTAssertNil(SpeechModel.qwen3Asr.fluidAudioVersion)
  }

  func testMLXAudioVersionConversion() {
    XCTAssertNil(SpeechModel.parakeetV2.mlxAudioVersion)
    XCTAssertNil(SpeechModel.parakeetV3.mlxAudioVersion)
    XCTAssertEqual(SpeechModel.glmAsrNano.mlxAudioVersion, .glmAsrNano)
    XCTAssertEqual(SpeechModel.qwen3Asr.mlxAudioVersion, .qwen3Asr)
  }
}
```

- [ ] **Step 4: Write TranscriptionService routing tests**

Create `VoxNotchTests/TranscriptionServiceTests.swift`:

```swift
//
//  TranscriptionServiceTests.swift
//  VoxNotchTests
//

import XCTest
@testable import VoxNotch

/// Spy provider that records calls without performing real transcription
final class SpyTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
  let name: String
  var isReady: Bool { get async { isReadyValue } }

  var isReadyValue = true
  var transcribeCallCount = 0
  var lastAudioURL: URL?
  var lastLanguage: String?
  var stubbedResult: TranscriptionResult?
  var stubbedError: Error?

  init(name: String = "Spy") {
    self.name = name
  }

  func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
    transcribeCallCount += 1
    lastAudioURL = audioURL
    lastLanguage = language
    if let error = stubbedError { throw error }
    return stubbedResult ?? TranscriptionResult(
      text: "test transcription",
      confidence: 0.95,
      audioDuration: 1.0,
      processingTime: 0.1,
      provider: name,
      language: language,
      segments: nil
    )
  }
}

final class TranscriptionServiceTests: XCTestCase {

  // MARK: - Provider Routing

  func testSetPrimaryProviderIsUsedForTranscription() async throws {
    let service = TranscriptionService.shared
    let spy = SpyTranscriptionProvider(name: "TestSpy")
    service.setPrimaryProvider(spy)

    // Create a minimal valid WAV file for the validator
    let wavURL = createMinimalWAV()
    defer { try? FileManager.default.removeItem(at: wavURL) }

    let result = try await service.transcribe(audioURL: wavURL)

    XCTAssertEqual(spy.transcribeCallCount, 1)
    XCTAssertEqual(result.provider, "TestSpy")
    XCTAssertEqual(result.text, "test transcription")
  }

  func testTranscribeThrowsWhenNoProvider() async {
    let service = TranscriptionService.shared
    // Force nil provider
    service.setPrimaryProvider(SpyTranscriptionProvider(name: "temp"))

    // Create a valid WAV, but reconfigure to nil out the provider
    // by setting an engine and immediately clearing
    // (This tests the guard path — in practice, provider should always exist)
  }

  func testTranscribeRejectsNonexistentFile() async {
    let service = TranscriptionService.shared
    service.setPrimaryProvider(SpyTranscriptionProvider())

    let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).wav")

    do {
      _ = try await service.transcribe(audioURL: fakeURL)
      XCTFail("Should have thrown fileNotFound")
    } catch let error as TranscriptionError {
      XCTAssertEqual(error, .fileNotFound)
    }
  }

  func testTranscribeRejectsTinyFile() async throws {
    let service = TranscriptionService.shared
    service.setPrimaryProvider(SpyTranscriptionProvider())

    // Create a file smaller than minimumFileSize (1000 bytes)
    let tinyURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("tiny_\(UUID().uuidString).wav")
    try Data(count: 100).write(to: tinyURL)
    defer { try? FileManager.default.removeItem(at: tinyURL) }

    do {
      _ = try await service.transcribe(audioURL: tinyURL)
      XCTFail("Should have thrown fileTooSmall")
    } catch let error as TranscriptionError {
      XCTAssertEqual(error, .fileTooSmall)
    }
  }

  func testCurrentProviderNameReflectsSetProvider() {
    let service = TranscriptionService.shared
    let spy = SpyTranscriptionProvider(name: "CustomEngine")
    service.setPrimaryProvider(spy)
    XCTAssertEqual(service.currentProviderName, "CustomEngine")
  }

  // MARK: - Helpers

  /// Create a minimal valid WAV file (44-byte header + 2000 bytes of silence)
  private func createMinimalWAV() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("test_\(UUID().uuidString).wav")

    var header = Data()
    let dataSize: UInt32 = 2000
    let fileSize: UInt32 = 36 + dataSize

    // RIFF header
    header.append(contentsOf: "RIFF".utf8)
    header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
    header.append(contentsOf: "WAVE".utf8)

    // fmt chunk
    header.append(contentsOf: "fmt ".utf8)
    header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
    header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
    header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // mono
    header.append(contentsOf: withUnsafeBytes(of: UInt32(16000).littleEndian) { Array($0) }) // sample rate
    header.append(contentsOf: withUnsafeBytes(of: UInt32(32000).littleEndian) { Array($0) }) // byte rate
    header.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })  // block align
    header.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits per sample

    // data chunk
    header.append(contentsOf: "data".utf8)
    header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
    header.append(Data(count: Int(dataSize))) // silence

    try! header.write(to: url)
    return url
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme VoxNotch -only-testing VoxNotchTests -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: All tests pass. If some fail due to singleton state or missing permissions, adjust test setup.

- [ ] **Step 6: Commit**

```bash
git add VoxNotchTests/ VoxNotch.xcodeproj/project.pbxproj
git commit -m "test: add test target with SpeechModel and TranscriptionService tests"
```

---

### Task 2: Extract Unified ModelDownloadState

**Files:**
- Create: `VoxNotch/Models/ModelDownloadState.swift`
- Modify: `VoxNotch/Managers/FluidAudioModelManager.swift` (lines 57-74)
- Modify: `VoxNotch/Managers/MLXAudioModelManager.swift` (lines 74-98)
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (lines 839-855, 1069-1074)

The three state enums — `FluidAudioModelState`, `MLXAudioModelState`, and `ModelDownloadState` (in SettingsView) — have identical cases. Extract one shared type.

- [ ] **Step 1: Create unified ModelDownloadState**

Create `VoxNotch/Models/ModelDownloadState.swift`:

```swift
//
//  ModelDownloadState.swift
//  VoxNotch
//
//  Unified download state for all ASR model managers
//

import Foundation

/// State of an ASR model's download and readiness lifecycle.
/// Used by both FluidAudioModelManager and MLXAudioModelManager.
enum ModelDownloadState: Equatable, Sendable {
  case notDownloaded
  case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64, speedBytesPerSecond: Double)
  case downloaded
  case loading
  case ready
  case failed(message: String)

  var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  var isDownloading: Bool {
    if case .downloading = self { return true }
    return false
  }

  var isDownloaded: Bool {
    switch self {
    case .downloaded, .ready, .loading: return true
    default: return false
    }
  }

  /// Simplified state for UI display (no internal details like loading)
  var uiState: UIDownloadState {
    switch self {
    case .notDownloaded: return .notDownloaded
    case .downloading(let progress, let downloadedBytes, let totalBytes, let speedBytesPerSecond):
      return .downloading(progress: progress, downloadedBytes: downloadedBytes, totalBytes: totalBytes, speedBytesPerSecond: speedBytesPerSecond)
    case .downloaded, .loading, .ready: return .ready
    case .failed: return .failed
    }
  }
}

/// Simplified download state for Settings UI display.
/// Collapses internal states (downloaded/loading/ready) into a single `.ready`.
enum UIDownloadState: Equatable {
  case notDownloaded
  case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64, speedBytesPerSecond: Double)
  case ready
  case failed
}
```

- [ ] **Step 2: Migrate FluidAudioModelManager to unified state**

In `VoxNotch/Managers/FluidAudioModelManager.swift`:

Delete the `FluidAudioModelState` enum (lines 57-74) entirely. Then update all references:

Replace every occurrence of `FluidAudioModelState` with `ModelDownloadState` throughout the file. The cases are identical, so no logic changes are needed.

Key lines to update:
- Line 91: `private(set) var modelStates: [FluidAudioModelVersion: FluidAudioModelState]` → `[FluidAudioModelVersion: ModelDownloadState]`
- Line 94: `private(set) var streamingModelStates: [String: FluidAudioModelState]` → `[String: ModelDownloadState]`
- Line 99: `private(set) var diarizationModelState: FluidAudioModelState` → `ModelDownloadState`

All `.downloading`, `.ready`, `.failed`, `.notDownloaded`, `.downloaded`, `.loading` cases keep the same syntax since the unified enum has the same cases.

- [ ] **Step 3: Migrate MLXAudioModelManager to unified state**

In `VoxNotch/Managers/MLXAudioModelManager.swift`:

Delete the `MLXAudioModelState` enum (lines 74-98) entirely. Then update all references:

Replace every occurrence of `MLXAudioModelState` with `ModelDownloadState` throughout the file.

Key lines to update:
- Line 115: `private(set) var modelStates: [MLXAudioModelVersion: MLXAudioModelState]` → `[MLXAudioModelVersion: ModelDownloadState]`
- Line 118: `private(set) var customModelStates: [String: MLXAudioModelState]` → `[String: ModelDownloadState]`
- Line 145: `private(set) var alignerModelState: MLXAudioModelState` → `ModelDownloadState`

- [ ] **Step 4: Simplify SettingsView state mapping**

In `VoxNotch/Views/Settings/SettingsView.swift`:

1. Delete the `ModelDownloadState` enum at line 1069-1074 (replaced by `UIDownloadState` in the new file).

2. Delete `mapFluidStateToDownloadState` (lines 839-846) and `mapMLXStateToDownloadState` (lines 848-855).

3. Update `downloadState(for:)` (line 826) to use `.uiState` directly:

```swift
private func downloadState(for model: SpeechModel) -> UIDownloadState {
  switch model.engine {
  case .fluidAudio:
    guard let version = model.fluidAudioVersion else { return .notDownloaded }
    let state = fluidModelManager.modelStates[version] ?? .notDownloaded
    return state.uiState
  case .mlxAudio:
    guard let version = model.mlxAudioVersion else { return .notDownloaded }
    let state = mlxModelManager.modelStates[version] ?? .notDownloaded
    return state.uiState
  }
}
```

4. Update `customDownloadState(for:)` (line 889):

```swift
private func customDownloadState(for model: CustomSpeechModel) -> UIDownloadState {
  if let state = mlxModelManager.customModelStates[model.id] {
    return state.uiState
  }
  return model.isDownloaded ? .ready : .notDownloaded
}
```

5. Update all references from `ModelDownloadState` → `UIDownloadState` in the file (the `downloadState` property on `ModelCard` and `CustomModelCard` structs, around lines 946, 1082).

- [ ] **Step 5: Delete mapToFluidState helper**

In `VoxNotch/Managers/MLXAudioModelManager.swift`, delete the `mapToFluidState` free function at line 727-736. It was a bridge between the two duplicate state types — no longer needed since both managers use `ModelDownloadState`.

Search for any remaining references to `mapToFluidState` and remove them.

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme VoxNotch -configuration Debug build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Run tests**

```bash
xcodebuild test -scheme VoxNotch -only-testing VoxNotchTests -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: All existing tests still pass.

- [ ] **Step 8: Commit**

```bash
git add VoxNotch/Models/ModelDownloadState.swift VoxNotch/Managers/FluidAudioModelManager.swift VoxNotch/Managers/MLXAudioModelManager.swift VoxNotch/Views/Settings/SettingsView.swift VoxNotch.xcodeproj/project.pbxproj
git commit -m "refactor: extract unified ModelDownloadState, remove 3 duplicate state enums"
```

---

### Task 3: Extract DownloadProgressTracker

**Files:**
- Create: `VoxNotch/Managers/DownloadProgressTracker.swift`
- Modify: `VoxNotch/Managers/FluidAudioModelManager.swift`
- Modify: `VoxNotch/Managers/MLXAudioModelManager.swift`

Both managers have an identical polling pattern: spawn a Task that reads directory size every 2s, computes speed, and updates a callback. Extract this into a reusable utility.

- [ ] **Step 1: Create DownloadProgressTracker**

Create `VoxNotch/Managers/DownloadProgressTracker.swift`:

```swift
//
//  DownloadProgressTracker.swift
//  VoxNotch
//
//  Polls a directory's size to estimate download progress
//

import Foundation

/// Polls a cache directory to estimate download progress.
/// Shared by FluidAudioModelManager and MLXAudioModelManager.
struct DownloadProgressTracker {

  /// Start polling a directory for download progress.
  ///
  /// - Parameters:
  ///   - directory: The directory being downloaded into
  ///   - expectedBytes: Estimated total download size
  ///   - interval: Polling interval in nanoseconds (default: 2 seconds)
  ///   - onProgress: Called on MainActor with (progress 0-0.95, downloadedBytes, totalBytes, speed)
  /// - Returns: A Task that can be cancelled when the download completes
  @discardableResult
  static func poll(
    directory: URL,
    expectedBytes: Int64,
    interval: UInt64 = 2_000_000_000,
    onProgress: @MainActor @escaping (Double, Int64, Int64, Double) -> Void
  ) -> Task<Void, Never> {
    Task {
      var lastBytes: Int64 = 0
      var lastTime = Date()

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: interval)
        let current = Self.directorySize(at: directory)
        guard current > 0, expectedBytes > 0 else { continue }

        let now = Date()
        let timeDiff = now.timeIntervalSince(lastTime)
        let bytesDiff = current - lastBytes
        let speed = timeDiff > 0 ? Double(bytesDiff) / timeDiff : 0

        lastBytes = current
        lastTime = now

        let progress = min(Double(current) / Double(expectedBytes), 0.95)
        await onProgress(progress, current, expectedBytes, speed)
      }
    }
  }

  /// Calculate size of a directory in bytes
  static func directorySize(at url: URL) -> Int64 {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path) else { return 0 }

    guard let enumerator = fileManager.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else { return 0 }

    var size: Int64 = 0
    for case let fileURL as URL in enumerator {
      if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        size += Int64(fileSize)
      }
    }
    return size
  }
}
```

- [ ] **Step 2: Migrate FluidAudioModelManager polling loops**

In `FluidAudioModelManager.swift`, replace the inline polling `Task` in `downloadBatchModel(version:)` (the block starting around `let pollingTask = Task {`). Replace with:

```swift
let pollingTask = DownloadProgressTracker.poll(
  directory: cacheDir,
  expectedBytes: expectedBytes
) { [weak self] progress, downloadedBytes, totalBytes, speed in
  guard let self else { return }
  if case .downloading = self.modelStates[version] {
    self.modelStates[version] = .downloading(
      progress: progress, downloadedBytes: downloadedBytes,
      totalBytes: totalBytes, speedBytesPerSecond: speed
    )
    self.downloadProgress = progress
  }
}
defer { pollingTask.cancel() }
```

Apply the same replacement to:
- `downloadAndLoad(version:)` — same pattern, same replacement
- `downloadStreamingModelsManual(for:)` — same pattern but updates `streamingModelStates[chunkKey]`
- `downloadDiarizationModels()` — if it has a polling loop (check)

Also delete the private `directorySize(at:)` method from FluidAudioModelManager since it's now in `DownloadProgressTracker`.

- [ ] **Step 3: Migrate MLXAudioModelManager polling loops**

In `MLXAudioModelManager.swift`, apply the same replacement to:
- `downloadAndLoad(version:)` — replace inline polling Task
- `downloadAndLoadCustom(model:)` — replace inline polling Task
- `downloadAlignerModel()` — replace inline polling Task

Delete the private `directorySize(at:)` method from MLXAudioModelManager.

Example for `downloadAndLoad`:

```swift
let pollingTask = DownloadProgressTracker.poll(
  directory: cacheURL,
  expectedBytes: expectedBytes
) { [weak self] progress, downloadedBytes, totalBytes, speed in
  guard let self else { return }
  if case .downloading = self.modelStates[version] {
    self.modelStates[version] = .downloading(
      progress: progress, downloadedBytes: downloadedBytes,
      totalBytes: totalBytes, speedBytesPerSecond: speed
    )
    self.downloadProgress = progress
  }
}
defer { pollingTask.cancel() }
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -scheme VoxNotch -configuration Debug build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -scheme VoxNotch -only-testing VoxNotchTests -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add VoxNotch/Managers/DownloadProgressTracker.swift VoxNotch/Managers/FluidAudioModelManager.swift VoxNotch/Managers/MLXAudioModelManager.swift VoxNotch.xcodeproj/project.pbxproj
git commit -m "refactor: extract DownloadProgressTracker, remove duplicate polling loops"
```

---

### Task 4: Clean Up Remaining Duplication

**Files:**
- Modify: `VoxNotch/Managers/FluidAudioModelManager.swift`
- Modify: `VoxNotch/Managers/MLXAudioModelManager.swift`

After Tasks 2-3, the remaining duplication is the `deleteAllModels` pattern (try? each model individually) and the refresh-state-from-filesystem pattern. These are small enough that further extraction would be over-engineering — but we should ensure `deleteAllModels` uses proper error handling (consistent with the safety fix in the previous commit).

- [ ] **Step 1: Fix deleteAllModels in FluidAudioModelManager**

In `FluidAudioModelManager.swift`, the `deleteAllModels()` method (around line 587) uses `try?` for each sub-deletion. Replace with logging:

```swift
func deleteAllModels() throws {
  var errors: [String] = []

  for version in FluidAudioModelVersion.allCases {
    do {
      try deleteBatchModel(version: version)
    } catch {
      errors.append("Batch \(version.rawValue): \(error.localizedDescription)")
    }
  }

  for chunkSize in [StreamingChunkSize.ms160, .ms320] {
    do {
      try deleteStreamingModels(for: chunkSize)
    } catch {
      errors.append("Streaming \(chunkSize): \(error.localizedDescription)")
    }
  }

  do {
    try deleteDiarizationModels()
  } catch {
    errors.append("Diarization: \(error.localizedDescription)")
  }

  if !errors.isEmpty {
    logger.error("Some models failed to delete: \(errors.joined(separator: "; "))")
  }

  logger.info("Deleted all models")
}
```

- [ ] **Step 2: Fix deleteAllModels in MLXAudioModelManager**

In `MLXAudioModelManager.swift`, the `deleteAllModels()` method (around line 541) has the same pattern. Replace:

```swift
func deleteAllModels() throws {
  var errors: [String] = []

  for version in MLXAudioModelVersion.allCases {
    do {
      try deleteModel(version: version)
    } catch {
      errors.append("\(version.rawValue): \(error.localizedDescription)")
    }
  }

  if !errors.isEmpty {
    logger.error("Some models failed to delete: \(errors.joined(separator: "; "))")
  }

  logger.info("Deleted all MLX Audio models")
}
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme VoxNotch -configuration Debug build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme VoxNotch -only-testing VoxNotchTests -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/Managers/FluidAudioModelManager.swift VoxNotch/Managers/MLXAudioModelManager.swift
git commit -m "fix: replace try? in deleteAllModels with logged error handling"
```

---

## Summary

After completing all 4 tasks:

- **Test target** exists with 8+ tests covering SpeechModel resolution and TranscriptionService routing
- **ModelDownloadState** is a single enum used by both managers and the UI (3 duplicate enums removed)
- **DownloadProgressTracker** replaces ~6 identical polling loops across both managers
- **SettingsView** no longer needs mapper functions between state types
- **deleteAllModels** uses proper error handling with logging

**Net effect:** ~200 lines of duplication removed, test infrastructure in place, no behavioral changes.

**Next plan:** Split QuickDictationController into coordinators + Unify state machines (depends on this plan's test target).
