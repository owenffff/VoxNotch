# Settings Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the VoxNotch settings UI to follow Apple System Settings patterns — grouped sidebar, consistent Form/Section styling, tooltips for discoverability — and split the 2,368-line monolith into per-tab files.

**Architecture:** Extract each tab into its own file under `Views/Settings/Tabs/`, shared components into `Views/Settings/Components/SettingsComponents.swift`. Rebuild the sidebar with grouped section headers. Convert Speech Model tab from ScrollView to Form. Add `.help()` tooltips and section footers throughout.

**Tech Stack:** SwiftUI, macOS 15+, Form/.formStyle(.grouped)

**Spec:** `docs/superpowers/specs/2026-04-05-settings-redesign-design.md`

---

### Task 1: Create directory structure and extract shared components

**Files:**
- Create: `VoxNotch/Views/Settings/Tabs/` (directory)
- Create: `VoxNotch/Views/Settings/Components/` (directory)
- Create: `VoxNotch/Views/Settings/Components/SettingsComponents.swift`
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (remove extracted components)

This task moves all reusable view components out of SettingsView.swift into a shared file. Components that are currently `private` become `internal` so they're accessible from per-tab files.

- [ ] **Step 1: Create directories**

```bash
mkdir -p VoxNotch/Views/Settings/Tabs
mkdir -p VoxNotch/Views/Settings/Components
```

- [ ] **Step 2: Create SettingsComponents.swift with all shared components**

Create `VoxNotch/Views/Settings/Components/SettingsComponents.swift` containing the following types extracted verbatim from SettingsView.swift, with `private` access removed:

1. `formatBytes(_:)` (line 650–655) — remove `private`
2. `formatSpeed(_:)` (line 657–662) — remove `private`
3. `UIDownloadState` enum — find its definition (likely in a model file, check first)
4. `ModelCard` struct (lines 1032–1183) — already `internal`
5. `CustomModelCard` struct (lines 905–1027) — already `internal`
6. `RatingDots` struct (lines 1187–1201) — already `internal`
7. `FeaturePill` struct (lines 1205–1219) — already `internal`
8. `ModelBadge` struct (lines 1258–1281) — already `internal`
9. `QuickSwitchOrderedList` struct (lines 1873–2000) — remove `private`
10. `TonePresetCard` struct (lines 1824–1866) — remove `private`
11. `ToneRowView` struct (lines 2004–2067) — remove `private`
12. `NewToneSheet` struct (lines 2071–2135) — remove `private`
13. `OllamaModelRow` struct (lines 2262–2362) — already `internal`
14. `ModelDownloadRow` struct (lines 2139–2258) — already `internal`

The file should start with:
```swift
//
//  SettingsComponents.swift
//  VoxNotch
//
//  Shared components used across settings tabs
//

import SwiftUI

// MARK: - Formatting Helpers

func formatBytes(_ bytes: Int64) -> String {
  if bytes == 0 { return "None" }
  let formatter = ByteCountFormatter()
  formatter.countStyle = .file
  return formatter.string(fromByteCount: bytes)
}

func formatSpeed(_ bytesPerSecond: Double) -> String {
  if bytesPerSecond == 0 { return "0 KB/s" }
  let formatter = ByteCountFormatter()
  formatter.countStyle = .file
  return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
}

// ... then all the component structs listed above, each with its MARK comment preserved
```

- [ ] **Step 3: Remove extracted code from SettingsView.swift**

Delete from SettingsView.swift:
- Lines 650–662 (formatBytes, formatSpeed)
- Lines 905–1281 (CustomModelCard, ModelCard, RatingDots, FeaturePill, SettingsSection, ModelBadge)
- Lines 1822–2368 (TonePresetCard, QuickSwitchOrderedList, ToneRowView, NewToneSheet, ModelDownloadRow, OllamaModelRow, Preview)

Keep in SettingsView.swift for now: SettingsPanel enum, SettingsView struct, and all tab structs (GeneralSettingsTab, HistoryTab, RecordingTab, DictationSpeechModelTab, DictationOutputTab, DictationAITab).

- [ ] **Step 4: Build to verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. Fix any missing imports or access issues if needed.

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/Views/Settings/Components/SettingsComponents.swift VoxNotch/Views/Settings/SettingsView.swift
git commit -m "refactor: extract shared settings components into SettingsComponents.swift"
```

---

### Task 2: Restructure sidebar with grouped sections

**Files:**
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (SettingsPanel enum + sidebar)

- [ ] **Step 1: Update SettingsPanel.title for the "Output" → "Transcription" rename**

In the `title` computed property, change:
```swift
case .output: "Output"
```
to:
```swift
case .output: "Transcription"
```

Keep the enum case as `.output` to preserve deep-linking rawValues.

- [ ] **Step 2: Rebuild sidebar with grouped sections**

Replace the current flat `List` body (lines 64–77):
```swift
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
```

With grouped sidebar:
```swift
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
```

- [ ] **Step 3: Update default selected panel**

Change the default from `.general` to `.recording` (first item in the new order):
```swift
@State private var selectedPanel: SettingsPanel = .recording
```

- [ ] **Step 4: Build to verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/Views/Settings/SettingsView.swift
git commit -m "refactor: group settings sidebar into Input/Output/App sections"
```

---

### Task 3: Extract and update GeneralTab

**Files:**
- Create: `VoxNotch/Views/Settings/Tabs/GeneralTab.swift`
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (remove GeneralSettingsTab)

- [ ] **Step 1: Create GeneralTab.swift**

Create `VoxNotch/Views/Settings/Tabs/GeneralTab.swift`. Copy `GeneralSettingsTab` from SettingsView.swift (lines 132–257), rename to `GeneralTab`, and apply these changes:

1. **Reorder sections:** Startup → Privacy → About → Storage
2. **Add tooltips** via `.help()`:
   - "Launch VoxNotch at login": `.help("Automatically start VoxNotch when you log into your Mac.")`
   - "Hide from Screen Recording": `.help("When enabled, VoxNotch windows won't appear in screen recordings, screenshots by other apps, or screen sharing.")`
3. **Add section footers:**
   - Startup footer: `"VoxNotch runs in the menu bar and is always ready when you need it."`
   - Privacy footer: `"Prevents VoxNotch from appearing in screen shares and recordings."`
   - Storage header tooltip: Add `.help("Disk space used by downloaded speech models. Deleting models frees space but you'll need to re-download them.")` to the Storage section's LabeledContent

```swift
//
//  GeneralTab.swift
//  VoxNotch
//
//  General settings: startup, privacy, about, storage
//

import SwiftUI
import ServiceManagement
import os.log

private let settingsLogger = Logger(subsystem: "com.voxnotch", category: "GeneralTab")

struct GeneralTab: View {

  @Bindable private var settings = SettingsManager.shared
  private var updateManager = UpdateManager.shared
  @State private var loginItemError: String?
  @State private var modelManager = FluidAudioModelManager.shared
  @State private var mlxModelManager = MLXAudioModelManager.shared
  @State private var showDeleteAllConfirmation = false

  private var isLoginItemEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  var body: some View {
    Form {
      // MARK: Startup
      Section {
        Toggle("Launch VoxNotch at login", isOn: Binding(
          get: { isLoginItemEnabled },
          set: { newValue in
            updateLoginItem(enabled: newValue)
          }
        ))
        .help("Automatically start VoxNotch when you log into your Mac.")
        .onChange(of: settings.launchAtLogin) { _, newValue in
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
      } footer: {
        Text("VoxNotch runs in the menu bar and is always ready when you need it.")
      }

      // MARK: Privacy
      Section {
        Toggle("Hide from screen recording", isOn: $settings.hideFromScreenRecording)
          .help("When enabled, VoxNotch windows won't appear in screen recordings, screenshots by other apps, or screen sharing.")
      } header: {
        Text("Privacy")
      } footer: {
        Text("Prevents VoxNotch from appearing in screen shares and recordings.")
      }

      // MARK: About
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

      // MARK: Storage
      Section {
        let totalBytes = modelManager.totalStorageUsedBytes() + mlxModelManager.totalStorageUsedBytes()
        LabeledContent("Total Model Storage") {
          Text(formatBytes(totalBytes))
            .foregroundStyle(.secondary)
        }
        .help("Disk space used by downloaded speech models. Deleting models frees space but you'll need to re-download them.")

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
      }
    }
    .formStyle(.grouped)
    .scrollIndicators(.never)
    .padding()
    .onAppear {
      settings.launchAtLogin = isLoginItemEnabled
      modelManager.refreshAllModelStates()
      mlxModelManager.refreshAllModelStates()
    }
  }

  private func updateLoginItem(enabled: Bool) {
    loginItemError = nil
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      settings.launchAtLogin = enabled
    } catch {
      loginItemError = "Failed to update login item: \(error.localizedDescription)"
      settings.launchAtLogin = isLoginItemEnabled
    }
  }
}
```

- [ ] **Step 2: Update SettingsView.swift routing**

In `detailView`, change:
```swift
case .general:
  GeneralSettingsTab()
```
to:
```swift
case .general:
  GeneralTab()
```

- [ ] **Step 3: Remove GeneralSettingsTab from SettingsView.swift**

Delete the `GeneralSettingsTab` struct and its `updateLoginItem` method (lines 130–257).

- [ ] **Step 4: Build to verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/Views/Settings/Tabs/GeneralTab.swift VoxNotch/Views/Settings/SettingsView.swift
git commit -m "refactor: extract GeneralTab with reordered sections and tooltips"
```

---

### Task 4: Extract and update HistoryTab

**Files:**
- Create: `VoxNotch/Views/Settings/Tabs/HistoryTab.swift`
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (remove HistoryTab)

- [ ] **Step 1: Create HistoryTab.swift**

Create `VoxNotch/Views/Settings/Tabs/HistoryTab.swift`. Copy `HistoryTab` from SettingsView.swift (lines 261–363) and update tooltips:

Key changes from current:
- `.help("Save dictation history")` → `.help("Saves all your transcriptions locally so you can search and review them later.")`
- `.help("Auto-delete after")` → `.help("Automatically removes transcriptions older than this. Set to 'Forever' to keep everything.")`
- `.help("Save audio recordings")` → `.help("Also saves the original audio alongside each transcription. Uses more disk space.")`
- Add footer to Retention section: `"Audio recordings let you re-transcribe with a different model later."`

```swift
//
//  HistoryTab.swift
//  VoxNotch
//
//  History settings: toggle, retention, storage
//

import SwiftUI
import GRDB
import os.log

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
          .help("Saves all your transcriptions locally so you can search and review them later.")
      } header: {
        Text("History")
      } footer: {
        Text("View your history from the menu bar icon → History.")
      }

      if settings.historyEnabled {
        Section {
          Picker("Auto-delete after", selection: $settings.historyRetentionDays) {
            ForEach(retentionOptions, id: \.days) { option in
              Text(option.label).tag(option.days)
            }
          }
          .help("Automatically removes transcriptions older than this. Set to \"Forever\" to keep everything.")

          Toggle("Save audio recordings", isOn: $settings.saveAudioRecordings)
            .help("Also saves the original audio alongside each transcription. Uses more disk space.")
        } header: {
          Text("Retention")
        } footer: {
          Text("Audio recordings let you re-transcribe with a different model later.")
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
        Logger(subsystem: "com.voxnotch", category: "HistoryTab").error("Failed to clear history: \(error.localizedDescription)")
      }
    }
  }
}
```

- [ ] **Step 2: Remove HistoryTab from SettingsView.swift**

Delete the `HistoryTab` struct (lines 259–363 in original, adjusted for prior removals). The routing in `detailView` already references `HistoryTab()` — it will now resolve to the new file.

- [ ] **Step 3: Build to verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add VoxNotch/Views/Settings/Tabs/HistoryTab.swift VoxNotch/Views/Settings/SettingsView.swift
git commit -m "refactor: extract HistoryTab with updated tooltips"
```

---

### Task 5: Extract and update RecordingTab

**Files:**
- Create: `VoxNotch/Views/Settings/Tabs/RecordingTab.swift`
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (remove RecordingTab)

- [ ] **Step 1: Create RecordingTab.swift**

Create `VoxNotch/Views/Settings/Tabs/RecordingTab.swift`. Copy `RecordingTab` from SettingsView.swift (lines 367–646) and update tooltip text to match spec:

Key tooltip updates:
- Hold to record: `.help("When enabled, recording stops when you release the hotkey. When disabled, press once to start and once to stop.")`
- Minimum duration: `.help("Recordings shorter than this are discarded. Prevents accidental triggers.")`
- Use Escape: `.help("Press Escape while recording to cancel without transcribing.")`
- Auto-stop on silence: `.help("Automatically stop recording when no speech is detected for a set duration.")`
- Silence threshold: `.help("Audio level below which is considered silence. Lower values are more sensitive.")`
- Silence duration: `.help("How long silence must last before auto-stopping.")`
- Section footer for Behavior: `"Press and hold this shortcut to start recording."`  (moved from Recording Behavior to Hotkey section footer)

Add required imports:
```swift
import SwiftUI
import AVFoundation
import CoreAudio
```

- [ ] **Step 2: Remove RecordingTab from SettingsView.swift**

Delete the `RecordingTab` struct and all its private methods (startTest, stopTest, transcribeTestAudio, startPlayback, stopPlayback, cleanupTest).

- [ ] **Step 3: Build to verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add VoxNotch/Views/Settings/Tabs/RecordingTab.swift VoxNotch/Views/Settings/SettingsView.swift
git commit -m "refactor: extract RecordingTab with updated tooltips"
```

---

### Task 6: Extract and convert SpeechModelTab to Form

**Files:**
- Create: `VoxNotch/Views/Settings/Tabs/SpeechModelTab.swift`
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (remove DictationSpeechModelTab)

This is the most significant structural change — converting from `ScrollView` + custom `SettingsSection` to `Form { Section { ... } }` with `.formStyle(.grouped)`.

- [ ] **Step 1: Create SpeechModelTab.swift**

Create `VoxNotch/Views/Settings/Tabs/SpeechModelTab.swift`. The key structural change is replacing:

```swift
// OLD: ScrollView + SettingsSection
ScrollView {
  VStack(alignment: .leading, spacing: 24) {
    SettingsSection(title: "Built-in Models", footer: "...") { ... }
    SettingsSection(title: "Custom Models", footer: "...") { ... }
    SettingsSection(title: "Quick-Switch (...)", footer: "...") { ... }
  }
  .padding()
}
```

With:

```swift
// NEW: Form + Section
Form {
  Section {
    Label("On-device, private, no network required", systemImage: "checkmark.shield")
      .foregroundStyle(.green)
      .font(.callout)

    ForEach(SpeechModel.allCases) { model in
      ModelCard(
        model: model,
        isSelected: selectedBuiltinModel == model,
        downloadState: downloadState(for: model),
        onSelect: { selectModel(model) },
        onDownload: { downloadModel(model) }
      )
    }
  } header: {
    Text("Built-in Models")
  } footer: {
    Text("Speech-to-text models that run locally on your Mac. Larger models are more accurate but use more memory.")
  }

  Section { /* custom models content */ } header: {
    Text("Custom Models")
  } footer: {
    Text("Import Whisper-compatible models from Hugging Face to use models not included by default.")
  }

  Section { /* quick switch content */ } header: {
    Text("Quick Switch (← →)")
  } footer: {
    Text("Pin up to 3 models to quickly switch between them using hotkey + arrow keys.")
  }
}
.formStyle(.grouped)
.scrollIndicators(.never)
.padding()
```

The full struct is renamed from `DictationSpeechModelTab` to `SpeechModelTab`. All private helper methods (downloadState, selectModel, downloadModel, customDownloadState, downloadCustomModel, deleteCustomModel, refreshModelsNeeded, allModelOptions) are copied verbatim.

Add required imports:
```swift
import SwiftUI
import os.log
```

- [ ] **Step 2: Update SettingsView.swift routing**

In `detailView`, change:
```swift
case .speechModel:
  DictationSpeechModelTab()
```
to:
```swift
case .speechModel:
  SpeechModelTab()
```

- [ ] **Step 3: Remove DictationSpeechModelTab from SettingsView.swift**

Delete the entire `DictationSpeechModelTab` struct and its helper methods (lines 666–901 in original).

- [ ] **Step 4: Build to verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 5: Run the app and visually verify**

Open Settings → Speech Model. Verify:
- Model cards render properly inside Form sections
- Selection highlighting works
- Download/progress UI works
- Quick-switch list is functional

- [ ] **Step 6: Commit**

```bash
git add VoxNotch/Views/Settings/Tabs/SpeechModelTab.swift VoxNotch/Views/Settings/SettingsView.swift
git commit -m "refactor: extract SpeechModelTab, convert from ScrollView to Form"
```

---

### Task 7: Extract and restructure TranscriptionTab

**Files:**
- Create: `VoxNotch/Views/Settings/Tabs/TranscriptionTab.swift`
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (remove DictationOutputTab)

This tab gets renamed and restructured: Sound Feedback and Text Cleanup promoted from DisclosureGroup to top-level sections.

- [ ] **Step 1: Create TranscriptionTab.swift**

Create `VoxNotch/Views/Settings/Tabs/TranscriptionTab.swift`. Rename `DictationOutputTab` to `TranscriptionTab`. Restructure the body from:

```swift
// OLD: Delivery section + DisclosureGroup("Advanced") containing Sound Feedback + Text Cleanup
```

To three top-level sections:

```swift
//
//  TranscriptionTab.swift
//  VoxNotch
//
//  Transcription settings: delivery, text cleanup, sound feedback
//

import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionTab: View {

  @Bindable private var settings = SettingsManager.shared

  var body: some View {
    Form {
      // MARK: Delivery
      Section {
        Toggle("Instant output (paste via clipboard)", isOn: $settings.useClipboardForOutput)
          .help("Pastes transcription directly into the active app using the clipboard. Temporarily replaces your clipboard contents.")

        Toggle("Restore clipboard after paste", isOn: $settings.restoreClipboard)
          .help("After pasting, restores whatever was on your clipboard before the transcription.")

        Toggle("Add space after transcription", isOn: $settings.addSpaceAfterTranscription)
      } header: {
        Text("Delivery")
      } footer: {
        Text("Transcribed text is pasted into whichever app was active when you started recording.")
      }

      // MARK: Text Cleanup
      Section {
        Toggle("Remove filler words", isOn: $settings.removeFillerWords)
          .help("Removes \"um\", \"uh\", \"like\", \"you know\" and similar filler words from transcriptions.")

        Toggle("Normalize numbers & currency", isOn: $settings.applyITN)
          .help("Convert spoken numbers to written form: \"two hundred\" → \"200\", \"five dollars\" → \"$5\"")
      } header: {
        Text("Text Cleanup")
      } footer: {
        Text("Automatic corrections applied to transcriptions before output. These run locally and don't use AI.")
      }

      // MARK: Sound Feedback
      Section {
        Toggle("Play sound on success", isOn: $settings.successSoundEnabled)
          .help("Play an audio cue when transcription is delivered.")

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
      } header: {
        Text("Sound Feedback")
      } footer: {
        Text("Plays an audio cue when transcription is complete and pasted.")
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
```

- [ ] **Step 2: Update SettingsView.swift routing**

In `detailView`, change:
```swift
case .output:
  DictationOutputTab()
```
to:
```swift
case .output:
  TranscriptionTab()
```

- [ ] **Step 3: Remove DictationOutputTab from SettingsView.swift**

Delete the entire `DictationOutputTab` struct (lines 1285–1393 in original).

- [ ] **Step 4: Build to verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/Views/Settings/Tabs/TranscriptionTab.swift VoxNotch/Views/Settings/SettingsView.swift
git commit -m "refactor: extract TranscriptionTab, promote Sound Feedback and Text Cleanup to sections"
```

---

### Task 8: Extract and update TonesTab

**Files:**
- Create: `VoxNotch/Views/Settings/Tabs/TonesTab.swift`
- Modify: `VoxNotch/Views/Settings/SettingsView.swift` (remove DictationAITab)

- [ ] **Step 1: Create TonesTab.swift**

Create `VoxNotch/Views/Settings/Tabs/TonesTab.swift`. Rename `DictationAITab` to `TonesTab`. Key changes:

1. **Add explainer paragraph** between pane title and first section. Since the pane title is rendered by the parent `SettingsView`, add it as the first element in the Form:

```swift
Section {
  Text("Tones use AI to refine your transcription — fixing grammar, adjusting formality, or rewriting in a specific style. Choose \"None\" to get the raw transcription.")
    .font(.footnote)
    .foregroundStyle(.secondary)
}
```

Or better: add it as a section footer on the Preset Tones section header area. The cleanest approach in a Form is to place it as a section footer:

In the Tones section footer, replace current:
```swift
footer: { Text("Select a tone to apply AI processing to your transcriptions.") }
```
With:
```swift
footer: {
  Text("Tones use AI to refine your transcription — fixing grammar, adjusting formality, or rewriting in a specific style. Choose \"None\" to get the raw transcription.")
}
```

2. **Add tooltips:**
   - Custom Tones DisclosureGroup label: Add `.help("Write your own AI prompt to control exactly how transcriptions are refined. Full Markdown supported.")` to the Custom Tones DisclosureGroup
   - Provider section header: keep as "Provider" but add `.help()` to the Picker: `.help("Which AI service processes your transcription. Apple Intelligence runs on-device. Ollama requires a local server.")`
   - Quick Switch section footer: already has good text, update to: `"Pin tones to quickly switch between them using hotkey + up/down arrow keys while recording."`

3. **Provider section footer:**
   Add: `"Apple Intelligence processes text on-device. Ollama requires running a local AI server."`

Copy the full struct with all state properties and methods (testConnection, etc.) verbatim except for the changes above.

Add required imports:
```swift
import SwiftUI
import os.log
```

- [ ] **Step 2: Update SettingsView.swift routing**

In `detailView`, change:
```swift
case .ai:
  DictationAITab()
```
to:
```swift
case .ai:
  TonesTab()
```

- [ ] **Step 3: Remove DictationAITab from SettingsView.swift**

Delete the entire `DictationAITab` struct (lines 1397–1820 in original).

- [ ] **Step 4: Build to verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/Views/Settings/Tabs/TonesTab.swift VoxNotch/Views/Settings/SettingsView.swift
git commit -m "refactor: extract TonesTab with explainer paragraph and tooltips"
```

---

### Task 9: Final cleanup of SettingsView.swift

**Files:**
- Modify: `VoxNotch/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Delete SettingsSection struct**

The custom `SettingsSection` container is no longer used (Speech Model tab now uses Form/Section). Delete it from wherever it ended up (originally lines 1221–1254). If it was already moved to SettingsComponents.swift in Task 1, delete it there instead.

- [ ] **Step 2: Clean up imports in SettingsView.swift**

SettingsView.swift should now only need:
```swift
import SwiftUI
```

Remove unused imports: `ServiceManagement`, `AVFoundation`, `CoreAudio`, `UniformTypeIdentifiers`, `os.log`, `GRDB`.

- [ ] **Step 3: Verify SettingsView.swift is slim**

The file should now contain only:
1. `settingsLogger` (can be removed if no longer used)
2. `SettingsPanel` enum (~53 lines)
3. `SettingsView` struct (~45 lines: sidebar + detailView routing)

Total: ~100 lines.

- [ ] **Step 4: Add a Preview back**

Add at the bottom of SettingsView.swift:
```swift
#Preview {
  SettingsView()
}
```

- [ ] **Step 5: Build to verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add VoxNotch/Views/Settings/SettingsView.swift VoxNotch/Views/Settings/Components/SettingsComponents.swift
git commit -m "refactor: clean up SettingsView.swift to slim sidebar coordinator"
```

---

### Task 10: Add files to Xcode project and full verification

**Files:**
- Modify: Xcode project file (if needed — may auto-detect with folder references)

- [ ] **Step 1: Verify all new files are included in the build**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild build -scheme VoxNotch -destination 'platform=macOS' 2>&1 | tail -10
```

If any files are missing from the build, they need to be added to the Xcode project's target membership. Check:
```bash
grep -r "SettingsComponents\|GeneralTab\|HistoryTab\|RecordingTab\|SpeechModelTab\|TranscriptionTab\|TonesTab" VoxNotch.xcodeproj/project.pbxproj | head -20
```

- [ ] **Step 2: Run the app and verify all 6 tabs**

Launch the app, open Settings, and verify each tab:

1. **Recording** (Input group): Hotkey works, behavior toggles work, Advanced disclosure toggles, mic test works
2. **Speech Model** (Input group): Model cards render in Form sections, selection works, download progress shows, quick-switch list works
3. **Transcription** (Output group): Delivery toggles work, Text Cleanup section visible, Sound Feedback section visible with sound picker
4. **Tones** (Output group): Explainer paragraph visible below title, preset grid works, custom tone editor works, provider selection works, quick-switch list works
5. **General** (App group): Startup toggle works, Privacy toggle works, About info shows, Storage shows size and delete button
6. **History** (App group): History toggle works, Retention section appears/hides conditionally, Clear history works

Also verify:
- Sidebar groups display with "INPUT", "OUTPUT", "APP" section headers
- All tooltips appear on hover (hold mouse over toggle/label with ⓘ for 1-2 seconds)
- Deep-linking still works (navigate to Speech Model or Tones programmatically)
- Window size unchanged (860x580)

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: settings redesign — grouped sidebar, unified Form styling, tooltips"
```

---

## File Summary

| Action | Path |
|--------|------|
| Create | `VoxNotch/Views/Settings/Components/SettingsComponents.swift` |
| Create | `VoxNotch/Views/Settings/Tabs/GeneralTab.swift` |
| Create | `VoxNotch/Views/Settings/Tabs/HistoryTab.swift` |
| Create | `VoxNotch/Views/Settings/Tabs/RecordingTab.swift` |
| Create | `VoxNotch/Views/Settings/Tabs/SpeechModelTab.swift` |
| Create | `VoxNotch/Views/Settings/Tabs/TranscriptionTab.swift` |
| Create | `VoxNotch/Views/Settings/Tabs/TonesTab.swift` |
| Modify | `VoxNotch/Views/Settings/SettingsView.swift` (slim to ~100 lines) |
| Unchanged | `VoxNotch/Views/Settings/SettingsWindowController.swift` |
| Unchanged | `VoxNotch/Views/Settings/HotkeyRecorderView.swift` |
| Unchanged | `VoxNotch/Views/Settings/PromptEditorView.swift` |
| Unchanged | `VoxNotch/Views/Settings/CustomModelSheet.swift` |
| Unchanged | `VoxNotch/Views/Settings/HFModelBrowserSheet.swift` |
