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
          _ = try await MLXAudioModelManager.shared.downloadAndLoad(version: version)
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
