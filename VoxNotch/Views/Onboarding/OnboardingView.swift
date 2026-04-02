//
//  OnboardingView.swift
//  VoxNotch
//
//  First-launch onboarding flow for new users
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
    case .welcome: return "Welcome to VoxNotch"
    case .permissions: return "Permissions"
    case .model: return "Speech Recognition"
    case .tutorial: return "How to Use"
    case .complete: return "Ready!"
    }
  }
}

// MARK: - Onboarding View

/// First-launch onboarding flow
@available(macOS 26.0, *)
struct OnboardingView: View {

  // MARK: - Properties

  @Environment(\.dismiss) private var dismiss
  @State private var currentStep: OnboardingStep = .welcome

  /// Permissions state
  @State private var hasMicPermission: Bool = false
  @State private var hasAccessibilityPermission: Bool = false
  @State private var permissionsChecked: Bool = false

  /// Model state
  @State private var isModelReady: Bool = false
  @State private var isDownloadingModel: Bool = false

  /// Callback when onboarding completes
  var onComplete: (() -> Void)?

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      /// Progress indicator
      progressIndicator
        .padding(.top, 20)

      Divider()
        .padding(.top, 16)

      /// Content
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
      .transition(.slide)
      .animation(.easeInOut(duration: 0.3), value: currentStep)

      Divider()

      /// Navigation buttons
      navigationButtons
        .padding()
    }
    .frame(width: 500, height: 450)
    .onAppear {
      checkPermissions()
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
        featureRow(icon: "sparkles", text: "Optional AI text enhancement")
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

      Text("VoxNotch needs a few permissions to work properly.")
        .font(.body)
        .foregroundStyle(.secondary)

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
      .padding(.top, 16)

      Button("Refresh Status") {
        checkPermissions()
      }
      .buttonStyle(.borderless)
      .font(.caption)
    }
    .padding()
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
    VStack(spacing: 24) {
      Image(systemName: "cpu")
        .font(.system(size: 60))
        .foregroundColor(.accentColor)

      Text("Speech Recognition")
        .font(.title)
        .fontWeight(.bold)

      Text("VoxNotch uses Apple's on-device speech recognition for fast, private transcription.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      VStack(spacing: 12) {
        HStack {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Built-in Apple Speech")
        }
        .font(.headline)

        Text("No download required. Speech recognition uses the system's built-in engine.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding()
      .background(.quaternary)
      .cornerRadius(8)

      Text("You can configure language and model options in Settings.")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding()
    .onAppear {
      isModelReady = true
    }
  }

  // MARK: - Tutorial Step

  private var tutorialStep: some View {
    VStack(spacing: 24) {
      Image(systemName: "hand.tap.fill")
        .font(.system(size: 60))
        .foregroundColor(.accentColor)

      Text("How to Use VoxNotch")
        .font(.title)
        .fontWeight(.bold)

      VStack(alignment: .leading, spacing: 20) {
        tutorialRow(
          step: 1,
          icon: "keyboard",
          title: "Hold the Hotkey",
          description: "Press and hold Control+Option to start recording"
        )

        tutorialRow(
          step: 2,
          icon: "waveform",
          title: "Speak",
          description: "Talk normally while holding the hotkey"
        )

        tutorialRow(
          step: 3,
          icon: "keyboard.badge.ellipsis",
          title: "Release",
          description: "Let go to transcribe and insert text at cursor"
        )
      }

      Text("You can customize the hotkey in Settings.")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding()
  }

  private func tutorialRow(step: Int, icon: String, title: String, description: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      ZStack {
        Circle()
          .fill(Color.accentColor)
          .frame(width: 30, height: 30)
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

      Text("You're Ready!")
        .font(.largeTitle)
        .fontWeight(.bold)

      Text("VoxNotch is set up and ready to use.\nHold Control+Option to start dictating.")
        .font(.title3)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      VStack(spacing: 8) {
        Text("Access VoxNotch from the menu bar")
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
      }

      Spacer()

      if currentStep == .welcome {
        Button("Skip Setup") {
          completeOnboarding()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
      }

      Button(currentStep == .complete ? "Get Started" : "Continue") {
        if currentStep == .complete {
          completeOnboarding()
        } else {
          withAnimation {
            currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .complete
          }
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(currentStep == .permissions && !canProceedFromPermissions)
    }
  }

  // MARK: - Helpers

  private var canProceedFromPermissions: Bool {
    /// Can always proceed - permissions are optional
    true
  }

  private func checkPermissions() {
    hasMicPermission = AudioCaptureManager.shared.hasMicrophonePermission
    hasAccessibilityPermission = HotkeyManager.shared.hasAccessibilityPermission
    permissionsChecked = true
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
    /// Check again after a delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      checkPermissions()
    }
  }

  private func completeOnboarding() {
    /// Mark onboarding as complete
    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    onComplete?()
    dismiss()
  }
}

// MARK: - Preview

@available(macOS 26.0, *)
#Preview {
  OnboardingView()
}
