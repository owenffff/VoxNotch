//
//  SettingsView.swift
//  VoxNotch
//
//  SwiftUI Settings window with mode-based sidebar navigation
//

import SwiftUI
import ServiceManagement
import AVFoundation
import CoreAudio
import UniformTypeIdentifiers
import GRDB
import os.log

private let settingsLogger = Logger(subsystem: "com.voxnotch", category: "SettingsView")

// MARK: - Settings Panel

/// Settings panel identifiers organized by mode
enum SettingsPanel: String, CaseIterable, Identifiable {
  case general
  case recording
  case speechModel
  case output
  case ai
  case history

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: "General"
    case .recording: "Recording"
    case .speechModel: "Speech Model"
    case .output: "Output"
    case .ai: "Tones"
    case .history: "History"
    }
  }

  var icon: String {
    switch self {
    case .general: "gear"
    case .recording: "waveform.circle"
    case .speechModel: "waveform"
    case .output: "text.cursor"
    case .ai: "sparkles"
    case .history: "clock.arrow.circlepath"
    }
  }
}

// MARK: - Main Settings View

/// Main settings view with mode-based sidebar navigation
struct SettingsView: View {

  @State private var selectedPanel: SettingsPanel = .general

  var body: some View {
    HStack(spacing: 0) {
      List(selection: $selectedPanel) {
        Label("General", systemImage: "gear")
          .tag(SettingsPanel.general)
        Label("Recording", systemImage: "waveform.circle")
          .tag(SettingsPanel.recording)
        Label("Speech Model", systemImage: "waveform")
          .tag(SettingsPanel.speechModel)
        Label("Output", systemImage: "text.cursor")
          .tag(SettingsPanel.output)
        Label("Tones", systemImage: "sparkles")
          .tag(SettingsPanel.ai)
        Label("History", systemImage: "clock.arrow.circlepath")
          .tag(SettingsPanel.history)
      }
      .listStyle(.sidebar)
      .frame(width: 200)

      Divider()

      VStack(alignment: .leading, spacing: 0) {
        Text(selectedPanel.title)
          .font(.title2)
          .fontWeight(.semibold)
          .padding(.horizontal, 24)
          .padding(.top, 20)
          .padding(.bottom, 4)

        detailView
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 860, height: 580)
    .onReceive(NotificationCenter.default.publisher(for: .settingsNavigateTo)) { notification in
      if let rawValue = notification.userInfo?["panel"] as? String,
         let panel = SettingsPanel(rawValue: rawValue)
      {
        selectedPanel = panel
      }
    }
  }

  @ViewBuilder
  private var detailView: some View {
    switch selectedPanel {
    case .general:
      GeneralSettingsTab()

    case .recording:
      RecordingTab()

    case .speechModel:
      DictationSpeechModelTab()

    case .output:
      DictationOutputTab()

    case .ai:
      DictationAITab()

    case .history:
      HistoryTab()
    }
  }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {

  @Bindable private var settings = SettingsManager.shared
  private var updateManager = UpdateManager.shared
  @State private var loginItemError: String?
  @State private var modelManager = FluidAudioModelManager.shared
  @State private var mlxModelManager = MLXAudioModelManager.shared
  @State private var showDeleteAllConfirmation = false

  /// Check current login item status from system
  private var isLoginItemEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  var body: some View {
    Form {
      Section {
        Toggle("Hide from Screen Recording", isOn: $settings.hideFromScreenRecording)
          .help("When enabled, VoxNotch's windows will be invisible during screen recordings and screen sharing.")
      } header: {
        Text("Privacy")
      }

      Section {
        Toggle("Launch VoxNotch at login", isOn: Binding(
          get: { isLoginItemEnabled },
          set: { newValue in
            updateLoginItem(enabled: newValue)
          }
        ))
        .onChange(of: settings.launchAtLogin) { _, newValue in
          /// Keep setting in sync with actual system state
          if newValue != isLoginItemEnabled {
            updateLoginItem(enabled: newValue)
          }
        }

        if let error = loginItemError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      } header: {
        Text("Startup")
      }

      Section {
        LabeledContent("Version") {
          Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            .foregroundStyle(.secondary)
        }

        LabeledContent("Build") {
          Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("About")
      }

      Section {
        let totalBytes = modelManager.totalStorageUsedBytes() + mlxModelManager.totalStorageUsedBytes()
        LabeledContent("Total Model Storage") {
          Text(formatBytes(totalBytes))
            .foregroundStyle(.secondary)
        }

        Button("Delete All Models", role: .destructive) {
          showDeleteAllConfirmation = true
        }
        .disabled(totalBytes == 0)
        .confirmationDialog("Delete all downloaded models?", isPresented: $showDeleteAllConfirmation) {
          Button("Delete All", role: .destructive) {
            do {
              try modelManager.deleteAllModels()
            } catch {
              settingsLogger.error("Failed to delete FluidAudio models: \(error.localizedDescription)")
            }
            do {
              try mlxModelManager.deleteAllModels()
            } catch {
              settingsLogger.error("Failed to delete MLX Audio models: \(error.localizedDescription)")
            }
            modelManager.refreshAllModelStates()
            mlxModelManager.refreshAllModelStates()
          }
        } message: {
          Text("This will remove all downloaded speech models. You can re-download them at any time.")
        }
      } header: {
        Text("Storage")
      } footer: {
        Text("Includes all speech models for Quick Dictation.")
          .font(.caption)
      }
    }
    .formStyle(.grouped)
    .scrollIndicators(.never)
    .padding()
    .onAppear {
      /// Sync setting with actual system state on appear
      settings.launchAtLogin = isLoginItemEnabled
      modelManager.refreshAllModelStates()
      mlxModelManager.refreshAllModelStates()
    }
  }

  /// Update login item registration with SMAppService
  private func updateLoginItem(enabled: Bool) {
    loginItemError = nil

    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      /// Update persisted setting
      settings.launchAtLogin = enabled
    } catch {
      loginItemError = "Failed to update login item: \(error.localizedDescription)"
      /// Revert setting on failure
      settings.launchAtLogin = isLoginItemEnabled
    }
  }
}

// MARK: - History

struct HistoryTab: View {

  @Bindable private var settings = SettingsManager.shared
  @State private var showClearAllConfirmation = false
  @State private var transcriptionCount: Int = 0

  private let retentionOptions: [(label: String, days: Int)] = [
    ("Forever", 0),
    ("7 days", 7),
    ("30 days", 30),
    ("90 days", 90),
    ("1 year", 365),
  ]

  var body: some View {
    Form {
      Section {
        Toggle("Save dictation history", isOn: $settings.historyEnabled)
          .help("When enabled, VoxNotch saves transcriptions so you can review them later.")
      } header: {
        Text("History")
      }

      if settings.historyEnabled {
        Section {
          Picker("Auto-delete after", selection: $settings.historyRetentionDays) {
            ForEach(retentionOptions, id: \.days) { option in
              Text(option.label).tag(option.days)
            }
          }
          .help("Automatically remove transcriptions older than this. \"Forever\" keeps everything.")

          Toggle("Save audio recordings", isOn: $settings.saveAudioRecordings)
            .help("Keep the original audio alongside each transcription for playback. Uses more disk space.")
        } header: {
          Text("Retention")
        }
      }

      Section {
        if transcriptionCount > 0 {
          LabeledContent("Saved transcriptions") {
            Text("\(transcriptionCount)")
              .foregroundStyle(.secondary)
          }
        }

        Button("Clear All History", role: .destructive) {
          showClearAllConfirmation = true
        }
        .disabled(transcriptionCount == 0)
        .confirmationDialog("Clear all dictation history?", isPresented: $showClearAllConfirmation) {
          Button("Clear All", role: .destructive) {
            clearAllHistory()
          }
        } message: {
          Text("This will permanently delete all saved transcriptions and audio recordings. This cannot be undone.")
        }
      } header: {
        Text("Storage")
      } footer: {
        Text("Open History from the menu bar to browse past dictations.")
          .font(.caption)
      }
    }
    .formStyle(.grouped)
    .scrollIndicators(.never)
    .padding()
    .onAppear {
      loadTranscriptionCount()
    }
  }

  private func loadTranscriptionCount() {
    Task {
      do {
        let count = try await DatabaseManager.shared.read { db in
          try TranscriptionRecord.fetchCount(db)
        }
        await MainActor.run {
          transcriptionCount = count
        }
      } catch {
        transcriptionCount = 0
      }
    }
  }

  private func clearAllHistory() {
    Task {
      do {
        _ = try await DatabaseManager.shared.write { db in
          try TranscriptionRecord.deleteAll(db)
        }
        await MainActor.run {
          transcriptionCount = 0
        }
      } catch {
        // Silently fail — user can retry
      }
    }
  }
}

// MARK: - Recording

struct RecordingTab: View {

  @Bindable private var settings = SettingsManager.shared
  @State private var hotkeyError: String?

  // Microphone test state
  @State private var isTesting = false
  @State private var isPlaying = false
  @State private var testAudioURL: URL?
  @State private var testTranscription: String?
  @State private var testError: String?
  @State private var audioPlayer: AVAudioPlayer?
  @State private var availableMicrophones: [(id: AudioDeviceID, name: String)] = []

  var body: some View {
    Form {
      // MARK: Hotkey
      Section {
        LabeledContent("Recording Hotkey") {
          HotkeyRecorderView(
            displayString: $settings.hotkeyModifiers,
            modifierFlags: $settings.hotkeyModifierFlags
          )
        }

        if let error = hotkeyError {
          Text(error)
            .foregroundStyle(.red)
            .font(.caption)
        }

        Button("Reset to Default (\u{2303}\u{2325})") {
          settings.updateHotkey(modifierFlags: 0xC0000, displayString: "\u{2303}\u{2325}")
        }
        .buttonStyle(.borderless)
      } header: {
        Text("Hotkey")
      }

      // MARK: Recording Behavior
      Section {
        Toggle("Hold to record", isOn: $settings.holdToRecord)
          .help("When enabled, hold the hotkey to record and release to transcribe")

        if settings.holdToRecord {
          LabeledContent("Minimum duration") {
            Slider(value: $settings.minimumRecordingDuration, in: 0.1...1.0, step: 0.1) {
              Text("Duration")
            }
            Text("\(settings.minimumRecordingDuration, specifier: "%.1f")s")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          .help("Minimum recording duration to prevent accidental triggers")
        }

        Toggle("Use Escape to cancel recording", isOn: $settings.useEscToCancel)
          .help("Press Escape to cancel an active recording")
      } header: {
        Text("Recording Behavior")
      } footer: {
        Text("Press the hotkey to start recording. Release to transcribe and insert text at the cursor.")
          .font(.caption)
      }

      // MARK: Auto-Stop
      Section {
        Toggle("Auto-stop on silence", isOn: $settings.enableAutoStopOnSilence)
          .help("Automatically stop recording after extended silence")

        if settings.enableAutoStopOnSilence {
          LabeledContent("Silence threshold") {
            Slider(value: $settings.silenceThresholdDB, in: -60.0...(-30.0), step: 5.0) {
              Text("Threshold")
            }
            Text("\(Int(settings.silenceThresholdDB)) dB")
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .frame(width: 50)
          }
          .help("Audio level below which is considered silence. Lower values are more sensitive.")

          LabeledContent("Silence duration") {
            Slider(value: $settings.silenceDurationSeconds, in: 1.0...10.0, step: 0.5) {
              Text("Duration")
            }
            Text("\(settings.silenceDurationSeconds, specifier: "%.1f")s")
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .frame(width: 40)
          }
          .help("How long silence must last before auto-stopping")

          Text("Recording will show a visual warning before auto-stopping.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Auto-Stop")
      }

      // MARK: Microphone
      Section {
        Picker("Device", selection: Binding(
          get: { settings.selectedMicrophoneDeviceID },
          set: { newValue in
            settings.selectedMicrophoneDeviceID = newValue
            AudioCaptureManager.shared.selectInputDevice(newValue == 0 ? nil : newValue)
          }
        )) {
          Text("System Default").tag(UInt32(0))
          Divider()
          ForEach(availableMicrophones, id: \.id) { mic in
            Text(mic.name).tag(mic.id)
          }
        }

        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Button(isTesting ? "Stop Test" : "Start Test") {
              if isTesting {
                stopTest()
              } else {
                startTest()
              }
            }
            .buttonStyle(.borderedProminent)
            .tint(isTesting ? .red : .accentColor)

            if isTesting {
              HStack(spacing: 4) {
                Circle()
                  .fill(Color.red)
                  .frame(width: 8, height: 8)
                  .opacity(0.8)
                Text("Recording...")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }

            Spacer()

            if testAudioURL != nil && !isTesting {
              Button(isPlaying ? "Stop Playback" : "Play Audio") {
                if isPlaying {
                  stopPlayback()
                } else {
                  startPlayback()
                }
              }
              .buttonStyle(.bordered)
            }
          }

          if let error = testError {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }

          if let transcription = testTranscription {
            VStack(alignment: .leading, spacing: 4) {
              Text("Dictation Result:")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(transcription.isEmpty ? "(No speech detected)" : transcription)
                .font(.body)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
          }
        }
        .padding(.top, 4)
      } header: {
        Text("Microphone")
      }
    }
    .formStyle(.grouped)
    .scrollIndicators(.never)
    .padding()
    .onAppear {
      availableMicrophones = AudioCaptureManager.shared.availableInputDevices()
    }
    .onReceive(NotificationCenter.default.publisher(for: AudioCaptureManager.inputDevicesChangedNotification)) { _ in
      availableMicrophones = AudioCaptureManager.shared.availableInputDevices()
    }
    .onDisappear {
      cleanupTest()
    }
  }

  // MARK: - Test Microphone Logic

  private func startTest() {
    testError = nil
    testTranscription = nil
    testAudioURL = nil
    stopPlayback()

    do {
      try AudioCaptureManager.shared.startRecording()
      isTesting = true
    } catch {
      testError = "Failed to start recording: \(error.localizedDescription)"
    }
  }

  private func stopTest() {
    do {
      let result = try AudioCaptureManager.shared.stopRecording()
      testAudioURL = result.fileURL
      isTesting = false
      transcribeTestAudio(url: result.fileURL)
    } catch {
      testError = "Failed to stop recording: \(error.localizedDescription)"
      isTesting = false
    }
  }

  private func transcribeTestAudio(url: URL) {
    testTranscription = "Transcribing..."

    Task {
      do {
        try await TranscriptionService.shared.ensureModelReady()
        let result = try await TranscriptionService.shared.transcribe(audioURL: url)
        await MainActor.run {
          testTranscription = result.text
        }
      } catch {
        await MainActor.run {
          testTranscription = nil
          testError = "Transcription failed: \(error.localizedDescription)"
        }
      }
    }
  }

  private func startPlayback() {
    guard let url = testAudioURL else { return }

    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.play()
      isPlaying = true

      Task {
        while let player = audioPlayer, player.isPlaying {
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await MainActor.run {
          isPlaying = false
        }
      }
    } catch {
      testError = "Failed to play audio: \(error.localizedDescription)"
    }
  }

  private func stopPlayback() {
    audioPlayer?.stop()
    isPlaying = false
  }

  private func cleanupTest() {
    if isTesting {
      AudioCaptureManager.shared.cancelRecording()
      isTesting = false
    }
    stopPlayback()
    if let url = testAudioURL {
      AudioCaptureManager.shared.cleanupFile(at: url)
    }
  }
}

// MARK: - Formatting Helpers

private func formatBytes(_ bytes: Int64) -> String {
  if bytes == 0 { return "None" }
  let formatter = ByteCountFormatter()
  formatter.countStyle = .file
  return formatter.string(fromByteCount: bytes)
}

private func formatSpeed(_ bytesPerSecond: Double) -> String {
  if bytesPerSecond == 0 { return "0 KB/s" }
  let formatter = ByteCountFormatter()
  formatter.countStyle = .file
  return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
}

// MARK: - Speech Model

struct DictationSpeechModelTab: View {

  @Bindable private var settings = SettingsManager.shared
  @State private var fluidModelManager = FluidAudioModelManager.shared
  @State private var mlxModelManager = MLXAudioModelManager.shared
  @State private var customRegistry = CustomModelRegistry.shared
  @State private var showAddCustomModel = false
  @State private var showBrowseModels = false

  private var selectedBuiltinModel: SpeechModel? {
    SpeechModel(rawValue: settings.speechModel)
  }

  private var selectedCustomModel: CustomSpeechModel? {
    CustomModelRegistry.shared.model(withID: settings.speechModel)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {

        // Privacy badge
        Label("On-device, private, no network required", systemImage: "checkmark.shield")
          .foregroundStyle(.green)
          .font(.callout)
          .padding(.horizontal, 4)

        // Built-in model cards
        VStack(alignment: .leading, spacing: 6) {
          Text("Built-in Models")
            .font(.headline)
            .padding(.horizontal, 4)

          VStack(spacing: 10) {
            ForEach(SpeechModel.allCases) { model in
              ModelCard(
                model: model,
                isSelected: selectedBuiltinModel == model,
                downloadState: downloadState(for: model),
                onSelect: { selectModel(model) },
                onDownload: { downloadModel(model) }
              )
            }
          }

          Text("Select and download a speech model for transcription.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }

        // Custom Models
        VStack(alignment: .leading, spacing: 6) {
          Text("Custom Models")
            .font(.headline)
            .padding(.horizontal, 4)

          if customRegistry.models.isEmpty {
            Text("No custom models added yet.")
              .foregroundStyle(.secondary)
              .font(.callout)
              .padding(.horizontal, 4)
          } else {
            VStack(spacing: 10) {
              ForEach(customRegistry.models) { model in
                CustomModelCard(
                  model: model,
                  isSelected: selectedCustomModel?.id == model.id,
                  downloadState: customDownloadState(for: model),
                  onSelect: { settings.speechModel = model.id },
                  onDownload: { downloadCustomModel(model) },
                  onDelete: { deleteCustomModel(model) }
                )
              }
            }
          }

          HStack(spacing: 0) {
            Button {
              showAddCustomModel = true
            } label: {
              Label("Add Custom Model", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderless)

            Divider().frame(height: 28)

            Button {
              showBrowseModels = true
            } label: {
              Label("Browse HuggingFace Models", systemImage: "safari")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderless)
          }
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .strokeBorder(
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
              )
              .foregroundStyle(Color(nsColor: .separatorColor))
          )

          Text("Add any MLX-format ASR model from Hugging Face Hub.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }

        // Quick-Switch
        VStack(alignment: .leading, spacing: 6) {
          Text("Quick-Switch (\u{2190} \u{2192})")
            .font(.headline)
            .padding(.horizontal, 4)

          QuickSwitchOrderedList(
            pinnedIDs: $settings.pinnedModelIDs,
            availableItems: allModelOptions,
            maxItems: 3
          )

          Text("Hold your dictation hotkey + \u{2190} \u{2192} to cycle through these models.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
      }
      .padding()
    }
    .scrollIndicators(.never)
    .onAppear {
      fluidModelManager.refreshAllModelStates()
      mlxModelManager.refreshAllModelStates()
    }
    .onChange(of: settings.speechModel) { _, _ in
      TranscriptionService.shared.reconfigure()
      refreshModelsNeeded()
    }
    .sheet(isPresented: $showAddCustomModel) {
      CustomModelSheet { newModel in
        // Auto-select newly added model
        settings.speechModel = newModel.id
        refreshModelsNeeded()
      }
    }
    .sheet(isPresented: $showBrowseModels) {
      HFModelBrowserSheet()
    }
  }

  // MARK: - Quick-Switch Helpers

  private var allModelOptions: [(id: String, name: String)] {
    var options: [(id: String, name: String)] = SpeechModel.allCases.map { ($0.rawValue, $0.displayName) }
    options += customRegistry.models.map { ($0.id, $0.displayName) }
    return options
  }

  // MARK: - Built-in Model Helpers

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

  private func selectModel(_ model: SpeechModel) {
    settings.speechModel = model.rawValue
  }

  private func downloadModel(_ model: SpeechModel) {
    Task {
      do {
        switch model.engine {
        case .fluidAudio:
          guard let version = model.fluidAudioVersion else { return }
          try await fluidModelManager.downloadBatchModel(version: version)
          await MainActor.run {
            fluidModelManager.refreshAllModelStates()
            refreshModelsNeeded()
          }
        case .mlxAudio:
          guard let version = model.mlxAudioVersion else { return }
          try await mlxModelManager.downloadAndLoad(version: version)
          await MainActor.run {
            mlxModelManager.refreshAllModelStates()
            refreshModelsNeeded()
          }
        }
      } catch {
        settingsLogger.error("Model download failed: \(error.localizedDescription)")
        // Model managers already update their state to .failed internally
      }
    }
  }

  // MARK: - Custom Model Helpers

  private func customDownloadState(for model: CustomSpeechModel) -> UIDownloadState {
    if let state = mlxModelManager.customModelStates[model.id] {
      return state.uiState
    }
    return model.isDownloaded ? .ready : .notDownloaded
  }

  private func downloadCustomModel(_ model: CustomSpeechModel) {
    Task {
      do {
        try await mlxModelManager.downloadAndLoadCustom(model: model)
      } catch {
        settingsLogger.error("Custom model download failed (\(model.hfRepoID)): \(error.localizedDescription)")
      }
      await MainActor.run { refreshModelsNeeded() }
    }
  }

  private func deleteCustomModel(_ model: CustomSpeechModel) {
    mlxModelManager.deleteCustomModel(model)
    // If this was the selected model, fall back to default
    if settings.speechModel == model.id {
      settings.speechModel = SpeechModel.defaultModel.rawValue
    }
    // Remove from pinned slots
    settings.pinnedModelIDs = settings.pinnedModelIDs.filter { $0 != model.id }
    refreshModelsNeeded()
  }

  private func refreshModelsNeeded() {
    let appState = AppState.shared
    let isReady: Bool
    let displayName: String

    if let builtin = selectedBuiltinModel {
      let state = downloadState(for: builtin)
      isReady = state == .ready
      displayName = builtin.displayName
    } else if let custom = selectedCustomModel {
      isReady = custom.isDownloaded
      displayName = custom.displayName
    } else {
      isReady = false
      displayName = "Unknown"
    }

    appState.isModelReady = isReady
    appState.modelsNeeded = !isReady
    appState.modelsNeededMessage = isReady ? "" : "Not downloaded: \(displayName)"
  }
}

// MARK: - Custom Model Card

struct CustomModelCard: View {
  let model: CustomSpeechModel
  let isSelected: Bool
  let downloadState: UIDownloadState
  let onSelect: () -> Void
  let onDownload: () -> Void
  let onDelete: () -> Void

  @State private var isHovered = false
  @State private var showDeleteConfirmation = false

  var body: some View {
    HStack(spacing: 12) {
      // Selection indicator
      Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

      VStack(alignment: .leading, spacing: 2) {
        Text(model.displayName)
          .fontWeight(isSelected ? .semibold : .medium)
        Text(model.hfRepoID)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      actionView

      // Delete button
      Button(role: .destructive) {
        showDeleteConfirmation = true
      } label: {
        Image(systemName: "trash")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .confirmationDialog("Remove \(model.displayName)?", isPresented: $showDeleteConfirmation) {
        Button("Remove", role: .destructive) { onDelete() }
      } message: {
        Text("This will remove the model from your list and delete downloaded files.")
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isSelected ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(
          isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
          lineWidth: isSelected ? 2 : 1
        )
    )
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .onTapGesture {
      if downloadState == .ready { onSelect() }
    }
    .onHover { hovering in isHovered = hovering }
  }

  @ViewBuilder
  private var actionView: some View {
    switch downloadState {
    case .notDownloaded:
      Button("Download") { onDownload() }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)

    case .downloading(let progress, let downloadedBytes, let totalBytes, let speedBytesPerSecond):
      VStack(alignment: .trailing, spacing: 2) {
        HStack(spacing: 6) {
          if progress > 0 {
            ProgressView(value: progress)
              .frame(width: 60)
            Text("\(Int(progress * 100))%")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          } else {
            ProgressView().scaleEffect(0.7)
            Text("Downloading...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if totalBytes > 0 {
          Text("\(formatBytes(downloadedBytes)) / \(formatBytes(totalBytes)) \u{2022} \(formatSpeed(speedBytesPerSecond))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
      }

    case .ready:
      if isSelected {
        Label("Now Using", systemImage: "checkmark")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.green)
      } else {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Ready")
            .font(.caption)
            .foregroundStyle(.green)
        }
      }

    case .failed:
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .font(.caption)
        Button("Retry") { onDownload() }
          .controlSize(.small)
      }
    }
  }
}

// MARK: - Model Card

/// Full-width card for a built-in SpeechModel with rich metadata display
struct ModelCard: View {
  let model: SpeechModel
  let isSelected: Bool
  let downloadState: UIDownloadState
  let onSelect: () -> Void
  let onDownload: () -> Void

  @State private var isHovered = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      // Top row: icon + name + badge
      HStack(alignment: .center, spacing: 10) {
        // Provider icon
        ZStack {
          RoundedRectangle(cornerRadius: 7)
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 34, height: 34)
          Image(systemName: model.providerIconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        }

        // Model name
        Text(model.displayName)
          .font(.system(.body, design: .default, weight: .semibold))

        // Tagline badge
        ModelBadge(text: model.tagline, model: model)

        Spacer()
      }

      // Description
      Text(model.modelDescription)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      // Feature row
      HStack(spacing: 8) {
        // Accuracy dots
        HStack(spacing: 3) {
          RatingDots(rating: model.accuracyRating, icon: "target")
          Text("Accuracy")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text("\u{00B7}").foregroundStyle(.tertiary).font(.caption)

        // Speed dots
        HStack(spacing: 3) {
          RatingDots(rating: model.speedRating, icon: "bolt.fill")
          Text("Speed")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text("\u{00B7}").foregroundStyle(.tertiary).font(.caption)

        // Size pill
        FeaturePill(icon: "internaldrive", text: formatSize(model.estimatedSizeMB))

        // Language pill
        FeaturePill(
          icon: "globe",
          text: model.languageDescription
        )

        Spacer()

        // Action area
        actionView
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isSelected ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(
          isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
          lineWidth: isSelected ? 2 : 1
        )
    )
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .onTapGesture {
      if downloadState == .ready { onSelect() }
    }
    .onHover { hovering in isHovered = hovering }
  }

  @ViewBuilder
  private var actionView: some View {
    switch downloadState {
    case .notDownloaded:
      Button("Download") { onDownload() }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)

    case .downloading(let progress, let downloadedBytes, let totalBytes, let speedBytesPerSecond):
      VStack(alignment: .trailing, spacing: 2) {
        HStack(spacing: 6) {
          if progress > 0 {
            ProgressView(value: progress)
              .frame(width: 60)
            Text("\(Int(progress * 100))%")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          } else {
            ProgressView().scaleEffect(0.7)
            Text("Downloading\u{2026}")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if totalBytes > 0 {
          Text("\(formatBytes(downloadedBytes)) / \(formatBytes(totalBytes)) \u{2022} \(formatSpeed(speedBytesPerSecond))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
      }

    case .ready:
      if isSelected {
        Label("Now Using", systemImage: "checkmark")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.green)
      }

    case .failed:
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .font(.caption)
        Button("Retry") { onDownload() }
          .controlSize(.small)
      }
    }
  }

  private func formatSize(_ mb: Int) -> String {
    mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000.0) : "\(mb) MB"
  }
}

// MARK: - Rating Dots

struct RatingDots: View {
  let rating: Int
  let icon: String
  private let total = 5

  var body: some View {
    HStack(spacing: 2) {
      ForEach(0..<total, id: \.self) { i in
        Circle()
          .fill(i < rating ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
          .frame(width: 6, height: 6)
      }
    }
  }
}

// MARK: - Feature Pill

struct FeaturePill: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: icon)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
      Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Model Badge

struct ModelBadge: View {
  let text: String
  let model: SpeechModel

  private var badgeColor: Color {
    switch model {
    case .glmAsrNano: .orange
    case .qwen3Asr: .purple
    default: .accentColor
    }
  }

  var body: some View {
    Text(text)
      .font(.caption2)
      .fontWeight(.semibold)
      .foregroundStyle(badgeColor)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(
        Capsule().fill(badgeColor.opacity(0.12))
      )
  }
}

// MARK: - Output

struct DictationOutputTab: View {

  @Bindable private var settings = SettingsManager.shared
  var body: some View {
    Form {
      Section {
        Toggle("Instant output (paste via clipboard)", isOn: $settings.useClipboardForOutput)
          .help("Paste the full transcription at once using the clipboard (Cmd+V). Disable to type character by character instead.")

        Toggle("Restore clipboard after paste", isOn: $settings.restoreClipboard)
          .help("When pasting as fallback, VoxNotch saves and restores whatever was on your clipboard.")

        Toggle("Add space after transcription", isOn: $settings.addSpaceAfterTranscription)
      } header: {
        Text("Delivery")
      }

      // MARK: Sound Feedback
      Section {
        Toggle("Play sound on success", isOn: $settings.successSoundEnabled)
          .help("Play an audio cue when transcription is delivered or copied to clipboard")

        if settings.successSoundEnabled {
          HStack {
            Text("Sound")
            Spacer()
            Text(successSoundDisplayName)
              .foregroundStyle(.secondary)

            Button("Change\u{2026}") {
              pickCustomSound()
            }
            .buttonStyle(.borderless)

            if !settings.customSuccessSoundPath.isEmpty {
              Button {
                settings.customSuccessSoundPath = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .help("Reset to default system sound")
            }
          }

          HStack {
            Button {
              SoundManager.shared.previewSound()
            } label: {
              Label("Preview", systemImage: "speaker.wave.2")
                .font(.caption)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
              NSWorkspace.shared.open(SoundManager.shared.soundsDirectory)
            } label: {
              Label("Open Sounds Folder", systemImage: "folder")
                .font(.caption)
            }
            .buttonStyle(.borderless)
          }
        }
      } header: {
        Text("Sound Feedback")
      }

      Section {
        Toggle("Remove filler words", isOn: $settings.removeFillerWords)
          .help("Automatically strip um, uh, er, ah, hmm from transcriptions (no AI required)")
        Toggle("Normalize numbers & currency", isOn: $settings.applyITN)
          .help("Convert spoken numbers to written form: \"two hundred\" \u{2192} \"200\", \"five dollars\" \u{2192} \"$5\" (no AI required)")
      } header: {
        Text("Text Cleanup")
      }

    }
    .formStyle(.grouped)
    .scrollIndicators(.never)
    .padding()
  }

  private var successSoundDisplayName: String {
    let path = settings.customSuccessSoundPath
    if path.isEmpty {
      return "Default"
    }
    return URL(fileURLWithPath: path).lastPathComponent
  }

  private func pickCustomSound() {
    let panel = NSOpenPanel()
    panel.title = "Choose a Success Sound"
    panel.allowedContentTypes = [.wav, .aiff, .mp3, .mpeg4Audio]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url {
      settings.customSuccessSoundPath = url.path
    }
  }
}

// MARK: - AI Enhancement

struct DictationAITab: View {

  @Bindable private var settings = SettingsManager.shared
  @State private var isTestingConnection = false
  @State private var connectionTestResult: String?
  @State private var llmModelManager = LLMModelManager.shared
  @State private var customOllamaTag: String = ""
  @State private var registry = ToneRegistry.shared
  @State private var selectedCustomToneID: String? = nil
  @State private var promptText: String = ""
  @State private var nameText: String = ""
  @State private var showDeleteConfirm = false
  @State private var showNewToneSheet = false
  @State private var showAdvancedTones = false

  private var availableModels: [String] {
    switch settings.llmProvider {
    case "apple": return ["on-device"]
    default: return []
    }
  }

  private var builtInTones: [ToneTemplate] {
    registry.tones.filter { $0.isBuiltIn }
  }

  private var customTones: [ToneTemplate] {
    registry.tones.filter { !$0.isBuiltIn }
  }

  private var selectedCustomTone: ToneTemplate? {
    guard let id = selectedCustomToneID else { return nil }
    return registry.tone(forID: id)
  }

  var body: some View {
    Form {
      // MARK: — Tier 1: Preset Tones (simple cards, no prompt visible)
      Section {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
          ForEach(builtInTones) { tone in
            TonePresetCard(
              tone: tone,
              isActive: settings.activeToneID == tone.id,
              onActivate: { settings.activeToneID = tone.id }
            )
          }
        }
      } header: {
        Text("Tones")
      } footer: {
        Text("Select a tone to apply AI processing to your transcriptions.")
          .font(.caption)
      }

      // MARK: — Tier 2: Custom Tones (power users)
      DisclosureGroup(isExpanded: $showAdvancedTones) {
        // Custom tone list
        if customTones.isEmpty {
          Text("No custom tones yet. Create one to write your own prompt.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        } else {
          ForEach(customTones) { tone in
            ToneRowView(
              tone: tone,
              isActive: settings.activeToneID == tone.id,
              isSelected: selectedCustomToneID == tone.id,
              onSelect: {
                selectedCustomToneID = tone.id
                promptText = tone.prompt
                nameText = tone.displayName
              },
              onActivate: { settings.activeToneID = tone.id },
              onDelete: {
                registry.remove(id: tone.id)
                if settings.activeToneID == tone.id { settings.activeToneID = "none" }
                settings.pinnedToneIDs.removeAll { $0 == tone.id }
                if selectedCustomToneID == tone.id { selectedCustomToneID = nil }
              }
            )
          }
        }

        // New tone button
        Button {
          showNewToneSheet = true
        } label: {
          Label("Create Custom Tone", systemImage: "plus")
            .font(.callout)
        }
        .buttonStyle(.borderless)
        .padding(.top, 4)

        // Selected custom tone editor
        if let tone = selectedCustomTone {
          VStack(alignment: .leading, spacing: 10) {
            Divider()

            // Name + action row
            HStack {
              TextField("Tone Name", text: $nameText)
                .textFieldStyle(.plain)
                .font(.headline)
                .onChange(of: nameText) { _, newVal in
                  var updated = tone
                  updated.displayName = newVal
                  registry.update(updated)
                }

              Spacer()

              if settings.activeToneID != tone.id {
                Button("Use This Tone") {
                  settings.activeToneID = tone.id
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
              } else {
                Label("Active", systemImage: "checkmark.circle.fill")
                  .font(.caption)
                  .foregroundStyle(.green)
              }
            }

            // Prompt editor
            PromptEditorView(text: $promptText)
              .onChange(of: promptText) { _, newVal in
                var updated = tone
                updated.prompt = newVal
                registry.update(updated)
              }
              .onChange(of: selectedCustomToneID) { _, _ in
                if let t = selectedCustomTone {
                  promptText = t.prompt
                  nameText = t.displayName
                }
              }

            // Action buttons
            HStack(spacing: 12) {
              // Duplicate
              Button {
                let copy = ToneTemplate(
                  id: UUID().uuidString,
                  displayName: "\(tone.displayName) Copy",
                  prompt: tone.prompt,
                  isBuiltIn: false,
                  originalPrompt: nil
                )
                registry.add(copy)
                selectedCustomToneID = copy.id
                promptText = copy.prompt
                nameText = copy.displayName
              } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
                  .font(.caption)
              }
              .buttonStyle(.borderless)

              Spacer()

              // Delete
              Button(role: .destructive) {
                showDeleteConfirm = true
              } label: {
                Label("Delete", systemImage: "trash")
                  .font(.caption)
              }
              .buttonStyle(.borderless)
              .confirmationDialog("Delete \"\(tone.displayName)\"?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                  let id = tone.id
                  registry.remove(id: id)
                  if settings.activeToneID == id { settings.activeToneID = "none" }
                  settings.pinnedToneIDs.removeAll { $0 == id }
                  selectedCustomToneID = nil
                }
              }
            }
          }
        }
      } label: {
        HStack {
          Label("Custom Tones", systemImage: "slider.horizontal.3")
            .font(.body)
          if !customTones.isEmpty {
            Text("\(customTones.count)")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.secondary.opacity(0.1))
              .clipShape(Capsule())
          }
        }
      }

      // MARK: Provider Selection -- only when a processing tone is active
      if settings.activeToneID != "none" {
        Section {
          Picker("Provider", selection: $settings.llmProvider) {
            if AnyLanguageModelProvider.isAppleIntelligenceSupported {
              if AnyLanguageModelProvider.isAppleIntelligenceAvailable {
                Text("Apple Intelligence (On-device)").tag("apple")
              } else {
                Text("Apple Intelligence (Unavailable)").tag("apple")
              }
            }
            Text("Ollama (Local)").tag("local")
          }

          if settings.llmProvider == "apple" {
            if AnyLanguageModelProvider.isAppleIntelligenceAvailable {
              Label("On-device, private, no API costs", systemImage: "checkmark.shield")
                .foregroundStyle(.green)
                .font(.caption)
            } else {
              Label(
                "Enable Apple Intelligence in System Settings → Apple Intelligence & Siri",
                systemImage: "exclamationmark.triangle"
              )
              .foregroundStyle(.orange)
              .font(.caption)
            }
          }

          if settings.llmProvider == "local" {
            TextField("Endpoint URL", text: $settings.llmEndpointURL)
              .textFieldStyle(.roundedBorder)
            Text("Default: http://localhost:11434")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if !availableModels.isEmpty && settings.llmProvider != "apple" {
            Picker("Model", selection: $settings.llmModel) {
              ForEach(availableModels, id: \.self) { model in
                Text(model).tag(model)
              }
            }
          }

          if settings.llmProvider == "local" {
            TextField("Model Name", text: $settings.llmModel)
              .textFieldStyle(.roundedBorder)
              .help("Ollama model name (e.g., llama3.2:3b)")
          }

          HStack {
            Button("Test Connection") {
              testConnection()
            }
            .disabled(isTestingConnection)

            if isTestingConnection {
              ProgressView()
                .scaleEffect(0.7)
            }

            if let result = connectionTestResult {
              Text(result)
                .font(.caption)
                .foregroundStyle(result.contains("Success") ? .green : .red)
            }
          }
        } header: {
          Text("Provider")
        }

        // MARK: Ollama Model Management
        if settings.llmProvider == "local" {
          Section {
            if !llmModelManager.isOllamaReachable && !llmModelManager.isLoadingModels {
              HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                  .foregroundStyle(.orange)
                Text("Cannot connect to Ollama server")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              if let error = llmModelManager.lastError {
                Text(error)
                  .font(.caption)
                  .foregroundStyle(.red)
              }

              Button("Retry Connection") {
                Task { await llmModelManager.refreshOllamaModels() }
              }
              .font(.caption)
            }

            if llmModelManager.isLoadingModels {
              HStack {
                ProgressView()
                  .scaleEffect(0.7)
                Text("Checking Ollama server...")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }

            if llmModelManager.isOllamaReachable {
              Label("Connected to Ollama", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            }

            ForEach(LLMModelManager.curatedModels) { model in
              OllamaModelRow(
                model: model,
                state: llmModelManager.pullStates[model.id] ?? .idle,
                onPull: {
                  Task { await llmModelManager.pullModel(model) }
                },
                onDelete: {
                  Task { await llmModelManager.deleteModel(model) }
                },
                onSelect: {
                  settings.llmModel = model.ollamaTag
                }
              )
            }

            HStack {
              TextField("Custom model tag", text: $customOllamaTag)
                .textFieldStyle(.roundedBorder)

              Button("Pull") {
                guard !customOllamaTag.isEmpty else { return }
                let tag = customOllamaTag
                Task { await llmModelManager.pullCustomModel(tag: tag) }
              }
              .disabled(customOllamaTag.isEmpty)
            }
          } header: {
            HStack {
              Text("Ollama Models")
              Spacer()
              Button {
                Task { await llmModelManager.refreshOllamaModels() }
              } label: {
                Image(systemName: "arrow.clockwise")
                  .font(.caption)
              }
              .buttonStyle(.borderless)
            }
          }
        }
      }

      // MARK: Quick-Switch -- always visible
      Section {
        QuickSwitchOrderedList(
          pinnedIDs: $settings.pinnedToneIDs,
          availableItems: registry.tones.map { ($0.id, $0.displayName) },
          maxItems: 3,
          fixedFirstItem: (id: "none", name: "Original")
        )
      } header: {
        Text("Quick-Switch (\u{2191}\u{2193})")
      } footer: {
        Text("Hold your dictation hotkey + \u{2191}\u{2193} to cycle through these tones.")
      }
    }
    .formStyle(.grouped)
    .scrollIndicators(.never)
    .padding()
    .sheet(isPresented: $showNewToneSheet) {
      NewToneSheet(registry: registry) { name, prompt in
        let tone = ToneTemplate(
          id: UUID().uuidString,
          displayName: name,
          prompt: prompt,
          isBuiltIn: false,
          originalPrompt: nil
        )
        registry.add(tone)
        selectedCustomToneID = tone.id
        promptText = tone.prompt
        nameText = tone.displayName
      }
    }
    .onAppear {
      if settings.llmProvider == "local" {
        Task { await llmModelManager.refreshOllamaModels() }
      }
    }
    .onChange(of: settings.llmProvider) { _, newValue in
      connectionTestResult = nil
      if newValue == "local" {
        Task { await llmModelManager.refreshOllamaModels() }
      }
    }
  }

  private func testConnection() {
    isTestingConnection = true
    connectionTestResult = nil

    Task {
      do {
        let provider = try AnyLanguageModelProvider.create(
          provider: settings.llmProvider,
          modelName: settings.llmModel,
          endpointURL: settings.llmEndpointURL
        )
        let result = try await provider.process(text: "Hello", prompt: "Reply with 'OK' only.")
        await MainActor.run {
          isTestingConnection = false
          connectionTestResult = "Success - \(result.prefix(20))"
        }
      } catch {
        await MainActor.run {
          isTestingConnection = false
          connectionTestResult = "Error - \(error.localizedDescription)"
        }
      }
    }
  }
}

// MARK: - Tone Preset Card

private struct TonePresetCard: View {

  let tone: ToneTemplate
  let isActive: Bool
  let onActivate: () -> Void

  var body: some View {
    Button(action: onActivate) {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(tone.displayName)
            .font(.headline)
            .foregroundStyle(isActive ? .white : .primary)

          Spacer()

          if isActive {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.white)
          }
        }

        if !tone.description.isEmpty {
          Text(tone.description)
            .font(.caption)
            .foregroundStyle(isActive ? .white.opacity(0.85) : .secondary)
            .lineLimit(2)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(isActive ? Color.clear : Color.secondary.opacity(0.15), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Quick-Switch Ordered List

/// Reusable ordered drag list for pinned quick-switch items (models or tones).
/// Shows up to `maxItems` pinned entries with drag-to-reorder and remove buttons,
/// plus a popover "+ Add" picker when there's room for more.
private struct QuickSwitchOrderedList: View {

  @Binding var pinnedIDs: [String]
  let availableItems: [(id: String, name: String)]
  let maxItems: Int
  var fixedFirstItem: (id: String, name: String)? = nil

  @State private var showAddPopover = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if fixedFirstItem != nil || !pinnedIDs.isEmpty {
        List {
          if let fixed = fixedFirstItem {
            HStack(spacing: 10) {
              // Number badge
              Text("1")
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.secondary.opacity(0.12))
                .clipShape(Circle())

              Text(fixed.name)
                .font(.body)

              Spacer()

              Image(systemName: "lock.fill")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            }
            .padding(.vertical, 2)
            .moveDisabled(true)
          }

          ForEach(Array(zip(pinnedIDs.indices, pinnedIDs)), id: \.1) { index, id in
            HStack(spacing: 10) {
              // Number badge
              Text("\(index + (fixedFirstItem != nil ? 2 : 1))")
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.secondary.opacity(0.12))
                .clipShape(Circle())

              Text(name(for: id))
                .font(.body)

              Spacer()

              Button {
                pinnedIDs.removeAll { $0 == id }
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
                  .imageScale(.medium)
              }
              .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
          }
          .onMove { from, to in pinnedIDs.move(fromOffsets: from, toOffset: to) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: CGFloat(pinnedIDs.count + (fixedFirstItem != nil ? 1 : 0)) * 40)
      }

      if pinnedIDs.count < maxItems {
        Button {
          showAddPopover = true
        } label: {
          Label("Add", systemImage: "plus.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, 2)
        .popover(isPresented: $showAddPopover, arrowEdge: .bottom) {
          addPicker
        }
      }
    }
  }

  private var addPicker: some View {
    let unpinned = availableItems.filter { item in
      !pinnedIDs.contains(item.id) && item.id != fixedFirstItem?.id
    }
    return VStack(alignment: .leading, spacing: 0) {
      if unpinned.isEmpty {
        Text("All items are pinned")
          .foregroundStyle(.secondary)
          .font(.callout)
          .padding()
      } else {
        ForEach(unpinned, id: \.id) { item in
          Button {
            if pinnedIDs.count < maxItems {
              pinnedIDs.append(item.id)
            }
            showAddPopover = false
          } label: {
            Text(item.name)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          if item.id != unpinned.last?.id {
            Divider()
          }
        }
      }
    }
    .frame(minWidth: 200)
    .padding(.vertical, 4)
  }

  private func name(for id: String) -> String {
    availableItems.first(where: { $0.id == id })?.name ?? id
  }
}

// MARK: - Tone Row View

private struct ToneRowView: View {

  let tone: ToneTemplate
  let isActive: Bool
  let isSelected: Bool
  let onSelect: () -> Void
  let onActivate: () -> Void
  let onDelete: () -> Void

  @State private var showDeleteConfirm = false

  var body: some View {
    HStack(spacing: 8) {
      // Active indicator
      Button(action: onActivate) {
        Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(isActive ? Color.accentColor : .secondary)
      }
      .buttonStyle(.plain)
      .help(isActive ? "Active tone" : "Set as active tone")

      // Name
      Text(tone.displayName)
        .font(.body)
        .fontWeight(isSelected ? .semibold : .regular)

      Spacer()

      // Badge
      if tone.isBuiltIn && tone.id != "none" {
        Text("built-in")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.secondary.opacity(0.1))
          .clipShape(Capsule())
      }

      // Delete (custom only)
      if !tone.isBuiltIn {
        Button(role: .destructive) {
          showDeleteConfirm = true
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 11))
            .foregroundStyle(.red.opacity(0.7))
        }
        .buttonStyle(.plain)
        .confirmationDialog("Delete \"\(tone.displayName)\"?", isPresented: $showDeleteConfirm) {
          Button("Delete", role: .destructive) { onDelete() }
        }
      }
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .padding(.horizontal, -4)
    )
    .onTapGesture { onSelect() }
  }
}

// MARK: - New Tone Sheet

private struct NewToneSheet: View {

  let registry: ToneRegistry
  let onCreate: (String, String) -> Void

  @State private var name = ""
  @State private var prompt = ""
  @State private var templateBase = "blank"
  @Environment(\.dismiss) private var dismiss

  private var templateOptions: [(id: String, name: String)] {
    var options: [(id: String, name: String)] = [("blank", "Blank")]
    for tone in registry.tones where tone.isBuiltIn && tone.id != "none" {
      options.append((tone.id, "Based on \(tone.displayName)"))
    }
    return options
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("New Tone")
        .font(.title2)
        .fontWeight(.semibold)

      HStack(spacing: 12) {
        TextField("Name", text: $name)
          .textFieldStyle(.roundedBorder)

        Picker("Start from", selection: $templateBase) {
          ForEach(templateOptions, id: \.id) { option in
            Text(option.name).tag(option.id)
          }
        }
        .frame(width: 200)
        .onChange(of: templateBase) { _, newVal in
          if newVal == "blank" {
            prompt = ""
          } else if let tone = registry.tone(forID: newVal) {
            prompt = tone.prompt
          }
        }
      }

      PromptEditorView(text: $prompt)

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.escape)

        Spacer()

        Button("Create") {
          guard !name.isEmpty else { return }
          onCreate(name, prompt)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.isEmpty)
        .keyboardShortcut(.return)
      }
    }
    .padding(24)
    .frame(width: 520, height: 520)
  }
}

// MARK: - Model Download Row

struct ModelDownloadRow: View {
  let title: String
  let description: String
  let state: ModelDownloadState
  let onDownload: () -> Void
  let onDelete: () -> Void
  let onRetry: () -> Void

  @State private var showDeleteConfirmation = false

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      statusView
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var statusView: some View {
    switch state {
    case .ready, .downloaded:
      HStack(spacing: 8) {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Ready")
            .font(.caption)
            .foregroundStyle(.green)
        }

        Button(role: .destructive) {
          showDeleteConfirmation = true
        } label: {
          Image(systemName: "trash")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .confirmationDialog("Delete \(title)?", isPresented: $showDeleteConfirmation) {
          Button("Delete", role: .destructive) {
            onDelete()
          }
        } message: {
          Text("You can re-download this model at any time.")
        }
      }

    case .downloading(let progress, let downloadedBytes, let totalBytes, let speedBytesPerSecond):
      VStack(alignment: .trailing, spacing: 2) {
        if progress > 0 {
          HStack(spacing: 8) {
            ProgressView(value: progress)
              .frame(width: 60)
            Text("\(Int(progress * 100))%")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        } else {
          HStack(spacing: 4) {
            ProgressView().scaleEffect(0.7)
            Text("Downloading...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if totalBytes > 0 {
          Text("\(formatBytes(downloadedBytes)) / \(formatBytes(totalBytes)) \u{2022} \(formatSpeed(speedBytesPerSecond))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
      }

    case .loading:
      HStack(spacing: 4) {
        ProgressView()
          .scaleEffect(0.7)
        Text("Loading...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .notDownloaded:
      Button("Download") {
        onDownload()
      }
      .font(.caption)
      .buttonStyle(.borderedProminent)
      .controlSize(.small)

    case .failed(let message):
      HStack(spacing: 8) {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text("Failed")
            .font(.caption)
            .foregroundStyle(.red)
        }
        .help(message)

        Button("Retry") {
          onRetry()
        }
        .font(.caption)
        .controlSize(.small)
      }
    }
  }
}

// MARK: - Ollama Model Row

struct OllamaModelRow: View {
  let model: CuratedOllamaModel
  let state: OllamaPullState
  let onPull: () -> Void
  let onDelete: () -> Void
  let onSelect: () -> Void

  @State private var showDeleteConfirmation = false

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(model.displayName)
          .font(.body)
        HStack(spacing: 4) {
          Text(model.estimatedSizeDescription)
          Text("\u{00B7}")
          Text(model.description)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      statusView
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private var statusView: some View {
    switch state {
    case .completed:
      HStack(spacing: 8) {
        Button("Use") {
          onSelect()
        }
        .font(.caption)
        .controlSize(.small)

        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Ready")
            .font(.caption)
            .foregroundStyle(.green)
        }

        Button(role: .destructive) {
          showDeleteConfirmation = true
        } label: {
          Image(systemName: "trash")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .confirmationDialog("Delete \(model.displayName)?", isPresented: $showDeleteConfirmation) {
          Button("Delete", role: .destructive) {
            onDelete()
          }
        }
      }

    case .pulling(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress)
          .frame(width: 60)
        Text("\(Int(progress * 100))%")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }

    case .idle:
      Button("Pull") {
        onPull()
      }
      .font(.caption)
      .buttonStyle(.borderedProminent)
      .controlSize(.small)

    case .failed(let message):
      HStack(spacing: 8) {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text("Failed")
            .font(.caption)
            .foregroundStyle(.red)
        }
        .help(message)

        Button("Retry") {
          onPull()
        }
        .font(.caption)
        .controlSize(.small)
      }
    }
  }
}

// MARK: - Preview

#Preview {
  SettingsView()
}
