# First-Run Setup Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken, macOS-26-only onboarding with a universal first-run wizard that downloads a model, grants permissions, and teaches users the hidden power features (model/tone quick-switching).

**Architecture:** Rewrite `OnboardingView.swift` without `@available(macOS 26.0, *)`, add `OnboardingWindowController` (following the existing `SettingsWindowController` singleton pattern), wire first-run detection into `AppDelegate.applicationDidFinishLaunching`, integrate real FluidAudio model downloading, and surface keyboard shortcut discoverability in the tutorial step.

**Tech Stack:** SwiftUI (hosted in NSHostingView via NSWindowController), UserDefaults for first-run flag, FluidAudioModelManager for model download, HotkeyManager for accessibility checks.

---

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `VoxNotch/Views/Onboarding/OnboardingWindowController.swift` | NSWindowController singleton — shows/hides the onboarding window |
| Rewrite | `VoxNotch/Views/Onboarding/OnboardingView.swift` | Full wizard UI — 5 steps with real model download and feature hints |
| Modify | `VoxNotch/App/AppDelegate.swift` | First-run detection + show wizard before normal startup |
| Modify | `VoxNotch/Managers/SettingsManager.swift` | Add `hasCompletedOnboarding` key to centralized settings |

---

### Task 1: Add `hasCompletedOnboarding` to SettingsManager

**Files:**
- Modify: `VoxNotch/Managers/SettingsManager.swift`

Currently `hasCompletedOnboarding` is a raw UserDefaults string in OnboardingView. Move it into SettingsManager so all first-run logic goes through one place.

- [ ] **Step 1: Add the key and property to SettingsManager**

In `VoxNotch/Managers/SettingsManager.swift`, add to the `Keys` enum:

```swift
/// Onboarding
static let hasCompletedOnboarding = "hasCompletedOnboarding"
```

And add a property in the class body (near the other general settings):

```swift
/// Whether the first-run wizard has been completed
var hasCompletedOnboarding: Bool {
  get { UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding) }
  set { UserDefaults.standard.set(newValue, forKey: Keys.hasCompletedOnboarding) }
}
```

- [ ] **Step 2: Build and verify no compile errors**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/Managers/SettingsManager.swift
git commit -m "feat: add hasCompletedOnboarding to SettingsManager"
```

---

### Task 2: Create OnboardingWindowController

**Files:**
- Create: `VoxNotch/Views/Onboarding/OnboardingWindowController.swift`

Follow the exact same pattern as `SettingsWindowController` — singleton NSWindowController hosting a SwiftUI view.

- [ ] **Step 1: Create the window controller file**

Create `VoxNotch/Views/Onboarding/OnboardingWindowController.swift`:

```swift
//
//  OnboardingWindowController.swift
//  VoxNotch
//
//  Window controller for the first-run setup wizard
//

import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController {

  // MARK: - Singleton

  static let shared = OnboardingWindowController()

  // MARK: - Properties

  /// Called when onboarding completes (used by AppDelegate to continue startup)
  var onComplete: (() -> Void)?

  // MARK: - Initialization

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )

    window.title = "Welcome to VoxNotch"
    window.center()
    window.isReleasedWhenClosed = false

    super.init(window: window)

    let onboardingView = OnboardingView {
      SettingsManager.shared.hasCompletedOnboarding = true
      self.onComplete?()
      self.close()
    }
    window.contentView = NSHostingView(rootView: onboardingView)
    window.sharingType = SettingsManager.shared.hideFromScreenRecording ? .none : .readOnly
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Public

  func show() {
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (OnboardingView exists but will be rewritten in Task 3 — this compiles against the current signature since OnboardingView already has an `onComplete` callback)

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/Views/Onboarding/OnboardingWindowController.swift
git commit -m "feat: add OnboardingWindowController singleton"
```

---

### Task 3: Rewrite OnboardingView — universal, with real model download

**Files:**
- Rewrite: `VoxNotch/Views/Onboarding/OnboardingView.swift`

This is the core change. The new view:
- Removes `@available(macOS 26.0, *)` — works on all supported macOS versions
- Replaces the fake "Apple Speech" model step with actual FluidAudio model selection + download
- Adds keyboard shortcut discovery to the tutorial step
- Shows clear accessibility permission status with "open System Settings" guidance

- [ ] **Step 1: Replace the entire OnboardingView.swift file**

Replace the contents of `VoxNotch/Views/Onboarding/OnboardingView.swift` with:

```swift
//
//  OnboardingView.swift
//  VoxNotch
//
//  First-run setup wizard — permissions, model download, feature discovery
//

import SwiftUI

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
  case welcome
  case permissions
  case model
  case tutorial
  case complete

  var title: String {
    switch self {
    case .welcome: "Welcome to VoxNotch"
    case .permissions: "Permissions"
    case .model: "Speech Model"
    case .tutorial: "How to Use"
    case .complete: "Ready!"
    }
  }
}

// MARK: - Onboarding View

/// First-run setup wizard
struct OnboardingView: View {

  // MARK: - Properties

  /// Callback when onboarding completes
  var onComplete: (() -> Void)?

  @State private var currentStep: OnboardingStep = .welcome

  /// Permissions state
  @State private var hasMicPermission = false
  @State private var hasAccessibilityPermission = false
  @State private var permissionPollTimer: Timer?

  /// Model state
  @State private var selectedModel: SpeechModel = .parakeetV2
  @State private var isDownloading = false
  @State private var downloadProgress: Double = 0
  @State private var downloadError: String?
  @State private var isModelDownloaded = false

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      // Progress dots
      progressIndicator
        .padding(.top, 20)

      Divider()
        .padding(.top, 16)

      // Step content
      Group {
        switch currentStep {
        case .welcome:
          welcomeStep
        case .permissions:
          permissionsStep
        case .model:
          modelStep
        case .tutorial:
          tutorialStep
        case .complete:
          completeStep
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .animation(.easeInOut(duration: 0.3), value: currentStep)

      Divider()

      // Navigation
      navigationButtons
        .padding()
    }
    .frame(width: 540, height: 500)
    .onDisappear {
      permissionPollTimer?.invalidate()
    }
  }

  // MARK: - Progress Indicator

  private var progressIndicator: some View {
    HStack(spacing: 8) {
      ForEach(OnboardingStep.allCases, id: \.self) { step in
        Circle()
          .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
          .frame(width: 10, height: 10)
      }
    }
  }

  // MARK: - Welcome Step

  private var welcomeStep: some View {
    VStack(spacing: 24) {
      Image(systemName: "waveform.and.mic")
        .font(.system(size: 80))
        .foregroundColor(.accentColor)

      Text("Welcome to VoxNotch")
        .font(.largeTitle)
        .fontWeight(.bold)

      Text("Voice dictation powered by on-device AI.\nTranscribe speech to text anywhere.")
        .font(.title3)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      VStack(alignment: .leading, spacing: 12) {
        featureRow(icon: "keyboard", text: "Hold hotkey to record, release to transcribe")
        featureRow(icon: "sparkles", text: "Optional AI text enhancement with tones")
        featureRow(icon: "lock.shield", text: "Private, on-device processing")
        featureRow(icon: "bolt.fill", text: "Fast and lightweight")
      }
      .padding(.top, 16)
    }
    .padding()
  }

  private func featureRow(icon: String, text: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.accentColor)
        .frame(width: 30)
      Text(text)
        .font(.body)
    }
  }

  // MARK: - Permissions Step

  private var permissionsStep: some View {
    VStack(spacing: 24) {
      Image(systemName: "shield.checkered")
        .font(.system(size: 60))
        .foregroundColor(.accentColor)

      Text("Permissions Required")
        .font(.title)
        .fontWeight(.bold)

      Text("VoxNotch needs these permissions to work.\nGrant them now — it only takes a moment.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      VStack(spacing: 16) {
        permissionRow(
          icon: "mic.fill",
          title: "Microphone",
          description: "To capture your voice for transcription",
          isGranted: hasMicPermission,
          action: requestMicPermission
        )

        permissionRow(
          icon: "accessibility",
          title: "Accessibility",
          description: "To type transcribed text at your cursor",
          isGranted: hasAccessibilityPermission,
          action: requestAccessibilityPermission
        )
      }
      .padding(.top, 8)

      if !hasAccessibilityPermission {
        Text("After granting Accessibility, this page updates automatically.")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .padding()
    .onAppear {
      checkPermissions()
      startPermissionPolling()
    }
    .onDisappear {
      permissionPollTimer?.invalidate()
    }
  }

  private func permissionRow(
    icon: String,
    title: String,
    description: String,
    isGranted: Bool,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.accentColor)
        .frame(width: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isGranted {
        Image(systemName: "checkmark.circle.fill")
          .font(.title2)
          .foregroundStyle(.green)
      } else {
        Button("Grant") {
          action()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
    .background(.quaternary)
    .cornerRadius(8)
  }

  // MARK: - Model Step

  private var modelStep: some View {
    VStack(spacing: 20) {
      Image(systemName: "cpu")
        .font(.system(size: 50))
        .foregroundColor(.accentColor)

      Text("Download a Speech Model")
        .font(.title)
        .fontWeight(.bold)

      Text("VoxNotch needs a speech model to transcribe your voice.\nChoose one to download now.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      // Model picker
      VStack(spacing: 10) {
        ForEach([SpeechModel.parakeetV2, .parakeetV3], id: \.self) { model in
          modelCard(model)
        }
      }
      .padding(.top, 4)

      // Download progress / status
      if isDownloading {
        VStack(spacing: 8) {
          ProgressView(value: downloadProgress)
            .frame(maxWidth: .infinity)
          Text("Downloading \(selectedModel.displayName)… \(Int(downloadProgress * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
      }

      if let error = downloadError {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }

        Button("Retry Download") {
          startModelDownload()
        }
        .buttonStyle(.bordered)
      }

      if isModelDownloaded {
        Label("\(selectedModel.displayName) is ready", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .font(.callout)
      }

      Text("You can download additional models later in Settings → Speech Model.")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding()
    .onAppear {
      // Check if the default model is already downloaded
      isModelDownloaded = selectedModel.isDownloaded
    }
  }

  private func modelCard(_ model: SpeechModel) -> some View {
    Button {
      selectedModel = model
      isModelDownloaded = model.isDownloaded
      downloadError = nil
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(model.displayName)
              .font(.headline)
              .foregroundStyle(selectedModel == model ? .white : .primary)
            Text("~\(model.estimatedSizeMB) MB")
              .font(.caption)
              .foregroundStyle(selectedModel == model ? .white.opacity(0.7) : .secondary)
          }
          Text(model.tagline)
            .font(.caption)
            .foregroundStyle(selectedModel == model ? .white.opacity(0.85) : .secondary)
        }

        Spacer()

        if model.isDownloaded {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(selectedModel == model ? .white : .green)
        } else if selectedModel == model {
          Image(systemName: "circle")
            .foregroundStyle(.white.opacity(0.5))
        }
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(selectedModel == model ? Color.accentColor : Color.secondary.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(selectedModel == model ? Color.clear : Color.secondary.opacity(0.15), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .disabled(isDownloading)
  }

  // MARK: - Tutorial Step

  private var tutorialStep: some View {
    VStack(spacing: 20) {
      Image(systemName: "hand.tap.fill")
        .font(.system(size: 50))
        .foregroundColor(.accentColor)

      Text("How to Use VoxNotch")
        .font(.title)
        .fontWeight(.bold)

      VStack(alignment: .leading, spacing: 16) {
        tutorialRow(
          step: 1,
          icon: "keyboard",
          title: "Hold \(SettingsManager.shared.hotkeyModifiers) to record",
          description: "Press and hold your hotkey to start recording"
        )

        tutorialRow(
          step: 2,
          icon: "waveform",
          title: "Speak naturally",
          description: "Talk while holding the hotkey — the notch shows a waveform"
        )

        tutorialRow(
          step: 3,
          icon: "keyboard.badge.ellipsis",
          title: "Release to transcribe",
          description: "Let go and text is inserted at your cursor"
        )
      }

      Divider()
        .padding(.vertical, 4)

      // Power features hint
      VStack(alignment: .leading, spacing: 10) {
        Text("Power Features")
          .font(.headline)
          .foregroundStyle(.secondary)

        HStack(spacing: 10) {
          Image(systemName: "arrow.left.arrow.right")
            .font(.title3)
            .foregroundColor(.accentColor)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text("Hold hotkey + ←→ arrows")
              .font(.callout.bold())
            Text("Quick-switch between speech models")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        HStack(spacing: 10) {
          Image(systemName: "arrow.up.arrow.down")
            .font(.title3)
            .foregroundColor(.accentColor)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text("Hold hotkey + ↑↓ arrows")
              .font(.callout.bold())
            Text("Quick-switch between tone presets")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding()
      .background(.quaternary)
      .cornerRadius(8)
    }
    .padding()
  }

  private func tutorialRow(step: Int, icon: String, title: String, description: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      ZStack {
        Circle()
          .fill(Color.accentColor)
          .frame(width: 28, height: 28)
        Text("\(step)")
          .font(.headline)
          .foregroundStyle(.white)
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Image(systemName: icon)
            .foregroundColor(.accentColor)
          Text(title)
            .font(.headline)
        }
        Text(description)
          .font(.body)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Complete Step

  private var completeStep: some View {
    VStack(spacing: 24) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 80))
        .foregroundStyle(.green)

      Text("You're All Set!")
        .font(.largeTitle)
        .fontWeight(.bold)

      Text("VoxNotch is ready.\nHold \(SettingsManager.shared.hotkeyModifiers) to start dictating.")
        .font(.title3)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      VStack(spacing: 8) {
        Text("Find VoxNotch in your menu bar")
          .font(.caption)
          .foregroundStyle(.tertiary)

        Image(systemName: "menubar.arrow.down.rectangle")
          .font(.title)
          .foregroundStyle(.secondary)
      }
      .padding(.top, 16)
    }
    .padding()
  }

  // MARK: - Navigation Buttons

  private var navigationButtons: some View {
    HStack {
      if currentStep != .welcome {
        Button("Back") {
          withAnimation {
            currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
          }
        }
        .buttonStyle(.borderless)
        .disabled(isDownloading)
      }

      Spacer()

      if currentStep == .welcome {
        Button("Skip Setup") {
          completeOnboarding()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
      }

      if currentStep == .model && !isModelDownloaded && !isDownloading {
        Button("Download \(selectedModel.displayName)") {
          startModelDownload()
        }
        .buttonStyle(.borderedProminent)
      } else {
        Button(currentStep == .complete ? "Get Started" : "Continue") {
          if currentStep == .complete {
            completeOnboarding()
          } else {
            advanceStep()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDownloading)
        .disabled(currentStep == .model && !isModelDownloaded)
      }
    }
  }

  // MARK: - Logic

  private func advanceStep() {
    withAnimation {
      currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .complete
    }
  }

  private func checkPermissions() {
    hasMicPermission = AudioCaptureManager.shared.hasMicrophonePermission
    hasAccessibilityPermission = HotkeyManager.shared.hasAccessibilityPermission
  }

  private func startPermissionPolling() {
    permissionPollTimer?.invalidate()
    permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
      DispatchQueue.main.async {
        checkPermissions()
      }
    }
  }

  private func requestMicPermission() {
    AudioCaptureManager.shared.requestMicrophonePermission { granted in
      DispatchQueue.main.async {
        hasMicPermission = granted
      }
    }
  }

  private func requestAccessibilityPermission() {
    HotkeyManager.shared.requestAccessibilityPermission()
  }

  private func startModelDownload() {
    guard !isDownloading else { return }
    isDownloading = true
    downloadProgress = 0
    downloadError = nil

    // Persist the selected model as the active speech model
    SettingsManager.shared.speechModel = selectedModel.rawValue

    Task {
      do {
        switch selectedModel.engine {
        case .fluidAudio:
          guard let version = selectedModel.fluidAudioVersion else { return }
          let manager = FluidAudioModelManager.shared

          // Poll download progress from the model manager
          let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            DispatchQueue.main.async {
              downloadProgress = manager.downloadProgress
            }
          }

          try await manager.downloadBatchModel(version: version)
          progressTimer.invalidate()

        case .mlxAudio:
          guard let version = selectedModel.mlxAudioVersion else { return }
          try await MLXAudioModelManager.shared.downloadModel(version: version)
        }

        await MainActor.run {
          isDownloading = false
          downloadProgress = 1.0
          isModelDownloaded = true
        }
      } catch {
        await MainActor.run {
          isDownloading = false
          downloadError = error.localizedDescription
        }
      }
    }
  }

  private func completeOnboarding() {
    SettingsManager.shared.hasCompletedOnboarding = true
    onComplete?()
  }
}

// MARK: - Preview

#Preview {
  OnboardingView()
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/Views/Onboarding/OnboardingView.swift
git commit -m "feat: rewrite OnboardingView — universal, real model download, feature hints"
```

---

### Task 4: Wire first-run detection into AppDelegate

**Files:**
- Modify: `VoxNotch/App/AppDelegate.swift`

Add first-run detection at the top of `applicationDidFinishLaunching`. If `hasCompletedOnboarding` is false, show the wizard window and defer the rest of setup until the wizard completes.

- [ ] **Step 1: Add wizard trigger to AppDelegate**

In `VoxNotch/App/AppDelegate.swift`, replace `applicationDidFinishLaunching` with:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    setupMenuBar()
    setupNotch()
    initializeDatabase()
    setupSleepWakeHandling()
    configureAppBehavior()

    if SettingsManager.shared.hasCompletedOnboarding {
        startNormalOperation()
    } else {
        showOnboardingWizard()
    }
}
```

- [ ] **Step 2: Add `showOnboardingWizard()` and `startNormalOperation()` methods**

Add these two new methods to AppDelegate (after `configureAppBehavior`):

```swift
// MARK: - First-Run Wizard

private func showOnboardingWizard() {
    let wizard = OnboardingWindowController.shared
    wizard.onComplete = { [weak self] in
        self?.startNormalOperation()
    }
    wizard.show()
}

private func startNormalOperation() {
    setupQuickDictation()
    setupAudioDeviceMonitoring()
}
```

- [ ] **Step 3: Remove `setupAudioDeviceMonitoring()` and `setupQuickDictation()` from the old launch position**

The original `applicationDidFinishLaunching` called these directly. They now live in `startNormalOperation()` which is called either immediately (returning user) or after the wizard completes (new user). Verify the old calls were removed in Step 1 — the replacement body no longer calls them directly.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/App/AppDelegate.swift
git commit -m "feat: wire first-run wizard into AppDelegate launch flow"
```

---

### Task 5: Update AppState to reflect model readiness after wizard download

**Files:**
- Modify: `VoxNotch/App/AppDelegate.swift` (refine `startNormalOperation`)

After the wizard downloads a model, `setupQuickDictation` needs to detect it. The current code in `setupQuickDictation` already checks model readiness — but it only checks FluidAudio models. After the wizard, the user may have downloaded a model already, so AppState should reflect that correctly.

- [ ] **Step 1: Refresh model state in `startNormalOperation` before setting up quick dictation**

Update `startNormalOperation()` to refresh model states before checking readiness:

```swift
private func startNormalOperation() {
    setupQuickDictation()
    setupAudioDeviceMonitoring()

    // Refresh model states in case onboarding just downloaded a model
    FluidAudioModelManager.shared.refreshAllModelStates()
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/App/AppDelegate.swift
git commit -m "fix: refresh model states after onboarding completes"
```

---

### Task 6: Add "Re-run Setup Wizard" to menu bar

**Files:**
- Modify: `VoxNotch/App/AppDelegate.swift`

Users should be able to re-run the wizard from the menu if they skipped it or want a refresher.

- [ ] **Step 1: Add menu item in `setupMenu()`**

In `AppDelegate.setupMenu()`, add a new menu item before the Settings item:

```swift
// Setup Wizard (re-run)
menu.addItem(NSMenuItem(
    title: "Setup Wizard...",
    action: #selector(openSetupWizard),
    keyEquivalent: ""
))
```

- [ ] **Step 2: Add the action method**

Add below `openSettings()`:

```swift
@objc private func openSetupWizard() {
    // Reset flag so the wizard runs its full flow
    SettingsManager.shared.hasCompletedOnboarding = false
    let wizard = OnboardingWindowController.shared
    wizard.onComplete = {
        SettingsManager.shared.hasCompletedOnboarding = true
    }
    wizard.show()
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add VoxNotch/App/AppDelegate.swift
git commit -m "feat: add 'Setup Wizard' menu item for re-running onboarding"
```

---

### Task 7: Final integration test

**Files:** None (testing only)

- [ ] **Step 1: Build the full project**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Test first-launch flow (reset state)**

Reset onboarding state and launch:
1. In Terminal: `defaults delete com.voxnotch hasCompletedOnboarding` (or the app's bundle ID)
2. Launch VoxNotch
3. Verify the setup wizard appears automatically

- [ ] **Step 3: Walk through the wizard**

1. **Welcome** — shows app intro with feature list. "Skip Setup" button visible. Click "Continue".
2. **Permissions** — mic and accessibility rows with grant buttons. Status auto-updates when permissions are toggled in System Settings. Click "Continue" (permissions are optional to proceed).
3. **Model** — Parakeet v2 pre-selected. Click "Download Parakeet v2". Progress bar appears and fills. Model downloads successfully. "Continue" button enables.
4. **Tutorial** — shows 3-step usage guide + "Power Features" box with ←→ model switching and ↑↓ tone switching hints. Click "Continue".
5. **Complete** — "You're All Set!" with hotkey reminder. Click "Get Started".
6. Wizard closes. VoxNotch enters normal operation. Status bar icon shows ready state.

- [ ] **Step 4: Test normal launch (wizard already completed)**

1. Quit and relaunch VoxNotch
2. Verify wizard does NOT appear — app starts normally
3. Status icon works, hotkey works, model is ready

- [ ] **Step 5: Test re-run from menu**

1. Click menu bar → "Setup Wizard..."
2. Wizard reappears
3. Walk through again or close it
4. Normal operation continues

- [ ] **Step 6: Test skip flow**

1. Reset: `defaults delete com.voxnotch hasCompletedOnboarding`
2. Launch, click "Skip Setup" on welcome page
3. Verify wizard closes, app starts normally (model may show "not downloaded" in notch since user skipped)

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "fix: polish first-run wizard after integration testing"
```
