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
import os.log
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
    case .output: "Transcription"
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

  @State private var selectedPanel: SettingsPanel = .recording

  var body: some View {
    HStack(spacing: 0) {
      List(selection: $selectedPanel) {
        Section("Input") {
          Label("Recording", systemImage: "waveform.circle")
            .tag(SettingsPanel.recording)
          Label("Speech Model", systemImage: "waveform")
            .tag(SettingsPanel.speechModel)
        }

        Section("Output") {
          Label("Transcription", systemImage: "text.cursor")
            .tag(SettingsPanel.output)
          Label("Tones", systemImage: "sparkles")
            .tag(SettingsPanel.ai)
        }

        Section("App") {
          Label("General", systemImage: "gear")
            .tag(SettingsPanel.general)
          Label("History", systemImage: "clock.arrow.circlepath")
            .tag(SettingsPanel.history)
        }
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
      GeneralTab()

    case .recording:
      RecordingTab()

    case .speechModel:
      SpeechModelTab()

    case .output:
      DictationOutputTab()

    case .ai:
      DictationAITab()

    case .history:
      HistoryTab()
    }
  }
}

// MARK: - Output

struct DictationOutputTab: View {

  @Bindable private var settings = SettingsManager.shared
  @State private var showAdvancedOutput = false
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

      // MARK: Advanced
      DisclosureGroup("Advanced", isExpanded: $showAdvancedOutput) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Sound Feedback")
            .font(.headline)
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
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          Text("Text Cleanup")
            .font(.headline)
          Toggle("Remove filler words", isOn: $settings.removeFillerWords)
            .help("Automatically strip um, uh, er, ah, hmm from transcriptions (no AI required)")
          Toggle("Normalize numbers & currency", isOn: $settings.applyITN)
            .help("Convert spoken numbers to written form: \"two hundred\" \u{2192} \"200\", \"five dollars\" \u{2192} \"$5\" (no AI required)")
        }
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


