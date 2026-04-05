# Progressive Disclosure Settings & Tone Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the settings and tone pages to follow progressive disclosure — hide power-user features behind an "Advanced" toggle, and add built-in tone presets that "just work" without requiring prompt engineering.

**Architecture:** Split the Tones tab into two tiers: (1) a preset grid where users pick a tone by name and description (no prompt visible), and (2) a "Custom Tones" section for power users with the full prompt editor. On other settings tabs, group power-user options behind expandable "Advanced" disclosure groups. The ToneTemplate model gains a `description` field so presets can explain themselves without showing the prompt.

**Tech Stack:** SwiftUI, UserDefaults (existing persistence), ToneTemplate/ToneRegistry (existing model layer)

---

### Task 1: Add `description` field to ToneTemplate

**Files:**
- Modify: `VoxNotch/Models/ToneTemplate.swift`

This adds a short user-facing description to each tone so the preset grid can show what a tone does without exposing the prompt.

- [ ] **Step 1: Add `description` property to ToneTemplate**

In `VoxNotch/Models/ToneTemplate.swift`, add a `description` field to the struct:

```swift
struct ToneTemplate: Codable, Identifiable, Hashable, Sendable {
  let id: String
  var displayName: String
  var description: String   // NEW — short user-facing description
  var prompt: String
  let isBuiltIn: Bool
  let originalPrompt: String?

  // Codable migration: default to "" for old data missing this field
  init(id: String, displayName: String, description: String = "", prompt: String, isBuiltIn: Bool, originalPrompt: String?) {
    self.id = id
    self.displayName = displayName
    self.description = description
    self.prompt = prompt
    self.isBuiltIn = isBuiltIn
    self.originalPrompt = originalPrompt
  }

  enum CodingKeys: String, CodingKey {
    case id, displayName, description, prompt, isBuiltIn, originalPrompt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    prompt = try container.decode(String.self, forKey: .prompt)
    isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
    originalPrompt = try container.decodeIfPresent(String.self, forKey: .originalPrompt)
  }

  func hash(into hasher: inout Hasher) { hasher.combine(id) }
  static func == (lhs: ToneTemplate, rhs: ToneTemplate) -> Bool { lhs.id == rhs.id }
}
```

- [ ] **Step 2: Build and verify no compile errors**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (existing callers use `description: ""` default)

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/Models/ToneTemplate.swift
git commit -m "feat: add description field to ToneTemplate for preset display"
```

---

### Task 2: Add descriptions to existing PromptTemplate presets

**Files:**
- Modify: `VoxNotch/Models/PromptTemplate.swift`
- Modify: `VoxNotch/Models/ToneTemplate.swift` (seedBuiltIns)

Add a `toneDescription` computed property to `PromptTemplate` so preset cards can show what each tone does. No new cases — just descriptions for the existing ones.

- [ ] **Step 1: Add `toneDescription` to PromptTemplate**

In `VoxNotch/Models/PromptTemplate.swift`, add a new computed property after `description`:

```swift
/// Short user-facing description (shown in preset picker, no prompt visible)
var toneDescription: String {
  switch self {
  case .formal: return "Convert to professional business writing"
  case .casual: return "Clean up errors while keeping it conversational"
  case .technical: return "Format for technical docs with precise terminology"
  case .translation: return "Translate to another language"
  case .custom: return ""
  }
}
```

- [ ] **Step 2: Update seedBuiltIns to include descriptions**

In `ToneTemplate.swift`, update `seedBuiltIns()`:

```swift
private func seedBuiltIns() {
  let noneTone = ToneTemplate(
    id: "none",
    displayName: "Original",
    description: "No AI processing — transcribed text is used as-is",
    prompt: "",
    isBuiltIn: true,
    originalPrompt: ""
  )
  let builtIns = PromptTemplate.allCases
    .filter { $0 != .custom }
    .map { template in
      ToneTemplate(
        id: template.rawValue,
        displayName: template.displayName,
        description: template.toneDescription,
        prompt: template.prompt,
        isBuiltIn: true,
        originalPrompt: template.prompt
      )
    }
  tones = [noneTone] + builtIns
}
```

- [ ] **Step 3: Add migration for existing users — backfill descriptions**

In `ToneTemplate.swift`, add a migration step in `loadOrSeed()` after `ensureNoneTone()`:

```swift
// Backfill descriptions for built-in tones (added in progressive disclosure update)
var backfilled = false
for i in tones.indices where tones[i].isBuiltIn && tones[i].description.isEmpty {
  if tones[i].id == "none" {
    tones[i] = ToneTemplate(
      id: tones[i].id,
      displayName: tones[i].displayName,
      description: "No AI processing — transcribed text is used as-is",
      prompt: tones[i].prompt,
      isBuiltIn: true,
      originalPrompt: tones[i].originalPrompt
    )
    backfilled = true
  } else if let template = PromptTemplate(rawValue: tones[i].id) {
    tones[i] = ToneTemplate(
      id: tones[i].id,
      displayName: tones[i].displayName,
      description: template.toneDescription,
      prompt: tones[i].prompt,
      isBuiltIn: true,
      originalPrompt: tones[i].originalPrompt
    )
    backfilled = true
  }
}
if backfilled { save() }
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/Models/PromptTemplate.swift VoxNotch/Models/ToneTemplate.swift
git commit -m "feat: add descriptions to existing tone presets for card display"
```

---

### Task 3: Redesign the Tones tab with preset grid and progressive disclosure

**Files:**
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (replace `DictationAITab`)

This is the core UI change. Replace the flat tone list + prompt editor with:
1. **Preset grid** — cards showing name + description, one-click to activate. No prompt visible.
2. **"Custom Tones"** disclosure group — the power-user section with + New Tone, prompt editor.
3. Provider section and Quick-Switch stay as-is (already use conditional sections).

- [ ] **Step 1: Replace DictationAITab with two-tier layout**

Replace the entire `DictationAITab` struct in `SettingsView.swift` (starting at line 1377) with:

```swift
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
        Text("Quick-Switch (↑↓)")
      } footer: {
        Text("Hold your dictation hotkey + ↑↓ to cycle through these tones.")
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
```

- [ ] **Step 2: Add the TonePresetCard view**

Add this new view right before the `QuickSwitchOrderedList` struct (around line 1787 in the original file):

```swift
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
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run the app, verify the Tones tab looks correct**

Launch VoxNotch, open Settings → Tones. Verify:
- Built-in presets appear as a 2-column grid of cards with name + description
- "Original" card has no description or shows "No AI processing..."
- Clicking a card activates it (checkmark + blue fill)
- "Custom Tones" section is collapsed by default
- Expanding it shows the custom tone list + "Create Custom Tone" button
- Creating/editing custom tones still works with the prompt editor
- Provider section still appears when a non-"none" tone is active
- Quick-Switch still works

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/Views/Settings/SettingsView.swift
git commit -m "feat: redesign Tones tab — preset grid + custom tones disclosure group"
```

---

### Task 4: Add Advanced disclosure group to Recording tab

**Files:**
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (RecordingTab, around line 366)

Group "Auto-Stop on Silence" and "Microphone" sections under an "Advanced" disclosure group. The Hotkey and Recording Behavior sections stay top-level — they're essential for all users.

- [ ] **Step 1: Wrap Auto-Stop and Microphone in a DisclosureGroup**

In the `RecordingTab` struct, add a `@State private var showAdvancedRecording = false` state variable. Then wrap the Auto-Stop and Microphone sections:

```swift
// After the Recording Behavior section's closing brace, replace the Auto-Stop and Microphone sections with:

DisclosureGroup("Advanced", isExpanded: $showAdvancedRecording) {
  // MARK: Auto-Stop
  VStack(alignment: .leading, spacing: 0) {
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
      .padding(.top, 8)

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
  }
  .padding(.vertical, 4)

  Divider()

  // MARK: Microphone
  VStack(alignment: .leading, spacing: 8) {
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
          if isTesting { stopTest() } else { startTest() }
        }
        .buttonStyle(.borderedProminent)
        .tint(isTesting ? .red : .accentColor)

        if isTesting {
          HStack(spacing: 4) {
            Circle().fill(Color.red).frame(width: 8, height: 8).opacity(0.8)
            Text("Recording...").font(.caption).foregroundStyle(.secondary)
          }
        }

        Spacer()

        if testAudioURL != nil && !isTesting {
          Button(isPlaying ? "Stop Playback" : "Play Audio") {
            if isPlaying { stopPlayback() } else { startPlayback() }
          }
          .buttonStyle(.bordered)
        }
      }

      if let error = testError {
        Text(error).font(.caption).foregroundStyle(.red)
      }

      if let transcription = testTranscription {
        VStack(alignment: .leading, spacing: 4) {
          Text("Dictation Result:").font(.caption).foregroundStyle(.secondary)
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
  }
  .padding(.vertical, 4)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/Views/Settings/SettingsView.swift
git commit -m "feat: hide Auto-Stop and Microphone behind Advanced disclosure in Recording tab"
```

---

### Task 5: Add Advanced disclosure group to Output tab

**Files:**
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (DictationOutputTab, around line 1270)

The Delivery section is essential. Sound Feedback and Text Cleanup are power-user options — wrap them in an "Advanced" disclosure group.

- [ ] **Step 1: Wrap Sound Feedback and Text Cleanup in a DisclosureGroup**

In `DictationOutputTab`, add `@State private var showAdvancedOutput = false`. Replace the Sound Feedback and Text Cleanup sections with:

```swift
DisclosureGroup("Advanced", isExpanded: $showAdvancedOutput) {
  // Sound Feedback
  VStack(alignment: .leading, spacing: 8) {
    Toggle("Play sound on success", isOn: $settings.successSoundEnabled)
      .help("Play an audio cue when transcription is delivered or copied to clipboard")

    if settings.successSoundEnabled {
      HStack {
        Text("Sound")
        Spacer()
        Text(successSoundDisplayName)
          .foregroundStyle(.secondary)

        Button("Change…") {
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
  .padding(.vertical, 4)

  Divider()

  // Text Cleanup
  VStack(alignment: .leading, spacing: 8) {
    Toggle("Remove filler words", isOn: $settings.removeFillerWords)
      .help("Automatically strip um, uh, er, ah, hmm from transcriptions (no AI required)")
    Toggle("Normalize numbers & currency", isOn: $settings.applyITN)
      .help("Convert spoken numbers to written form: \"two hundred\" → \"200\", \"five dollars\" → \"$5\" (no AI required)")
  }
  .padding(.vertical, 4)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/Views/Settings/SettingsView.swift
git commit -m "feat: hide Sound Feedback and Text Cleanup behind Advanced disclosure in Output tab"
```

---

### Task 6: Final integration test

**Files:** None (testing only)

- [ ] **Step 1: Build the full project**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Manual verification checklist**

Launch VoxNotch and walk through every settings tab:

1. **General** — unchanged, all settings visible
2. **Recording** — Hotkey and Recording Behavior visible at top. "Advanced" collapsed, expanding shows Auto-Stop and Microphone test
3. **Speech Model** — unchanged
4. **Output** — Delivery section visible at top. "Advanced" collapsed, expanding shows Sound Feedback and Text Cleanup
5. **Tones** — Preset grid shows 5 cards (Original, Formal Style, Casual Style, Technical Writing, Translation). "Custom Tones" collapsed. Provider section appears when non-Original tone is active. Quick-Switch works
6. **History** — unchanged

- [ ] **Step 3: Test tone activation flow**

1. Click "Fix Grammar" card → card turns blue with checkmark, Provider section appears
2. Click "Original" card → Provider section disappears
3. Expand "Custom Tones" → click "Create Custom Tone" → create a tone → it appears in the list and can be activated
4. Quick-Switch (↑↓) cycling still works with new presets

- [ ] **Step 4: Test migration (existing users)**

Delete and re-run to verify the migration path:
1. Existing users who had custom tones should keep them (in the Custom Tones section)
2. All built-in tones get descriptions backfilled (visible on cards)

- [ ] **Step 5: Final commit (if any tweaks needed)**

```bash
git add -A
git commit -m "fix: polish progressive disclosure settings after integration testing"
```
