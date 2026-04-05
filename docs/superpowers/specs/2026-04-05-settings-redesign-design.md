# Settings Page Redesign — Design Spec

## Context

VoxNotch's settings page has 6 tabs implemented in a single 2,368-line `SettingsView.swift` file. The tabs use inconsistent styling — some use `Form { Section { ... } }`, others use a custom `SettingsSection` container, and others use raw `ScrollView` + `VStack`. Font sizes, spacing, and section patterns vary across tabs. There are no tooltips explaining domain-specific concepts to new users.

This redesign unifies the UI to follow Apple System Settings (macOS Ventura+) patterns, adds tooltips for discoverability, and splits the monolithic file into per-tab files.

## Sidebar Structure

**3 groups, 6 items** — grouped sidebar with section headers, matching Apple System Settings.

| Group  | Item            | SF Symbol                  |
|--------|-----------------|----------------------------|
| Input  | Recording       | `waveform.circle`          |
| Input  | Speech Model    | `waveform`                 |
| Output | Transcription   | `text.cursor`              |
| Output | Tones           | `sparkles`                 |
| App    | General         | `gear`                     |
| App    | History         | `clock.arrow.circlepath`   |

**Changes from current:**
- "Output" tab renamed to "Transcription" (clearer)
- Sidebar items now grouped under uppercase section headers ("INPUT", "OUTPUT", "APP")
- Privacy stays in General (only 1 toggle — not enough for own pane)

## Design System

### Typography Scale

All system fonts. No custom typefaces.

| Role             | SwiftUI                          | Usage                              |
|------------------|----------------------------------|------------------------------------|
| Pane title       | `.title2` + `.fontWeight(.semibold)` | One per pane, top-left         |
| Section header   | Built-in `Section("Header")`     | Automatic from Form/Section        |
| Body / controls  | `.body` (13pt)                   | Toggles, pickers, labels           |
| Help / footer    | `.footnote` + `.foregroundStyle(.secondary)` | Section footers         |
| Caption          | `.caption` + `.foregroundStyle(.tertiary)` | Timestamps, storage sizes  |

### Section Styling

**Every tab** uses `Form { Section { ... } }` with `.formStyle(.grouped)`. The custom `SettingsSection` struct is deleted. Card-based UIs (Speech Model cards, Tone preset grid) are placed inside Form sections.

### Tooltips

Two tooltip mechanisms:
1. **`.help()` modifier** (SwiftUI) — on individual controls. Shows on hover. Used for specific settings.
2. **Explainer paragraph** — below pane title. Used for the Tones pane where the entire concept needs introduction.

### Progressive Disclosure

- `DisclosureGroup` for advanced settings (Recording: auto-stop/mic, kept from current)
- Conditional sections: Retention section in History only visible when history is enabled; AI Provider in Tones only visible when tone != "None"

## File Structure

Split `SettingsView.swift` (2,368 lines) into:

```
Views/Settings/
  SettingsView.swift          — Sidebar + tab routing (slim coordinator)
  SettingsWindowController.swift — Unchanged
  Tabs/
    RecordingTab.swift
    SpeechModelTab.swift
    TranscriptionTab.swift
    TonesTab.swift
    GeneralTab.swift
    HistoryTab.swift
  Components/
    SettingsComponents.swift   — Shared: ModelCard, TonePresetCard, RatingDots, FeaturePill, QuickSwitchOrderedList
  HotkeyRecorderView.swift    — Unchanged
  PromptEditorView.swift       — Unchanged
  CustomModelSheet.swift       — Unchanged
  HFModelBrowserSheet.swift    — Unchanged
```

## Tab Designs

### Recording

Sections: **Hotkey** → **Behavior** → **Advanced** (DisclosureGroup)

| Section   | Controls                                                  |
|-----------|-----------------------------------------------------------|
| Hotkey    | HotkeyRecorderView + Reset button                        |
| Behavior  | Toggle: Hold to record (tooltip), Slider: Min duration (tooltip), Toggle: Escape to cancel |
| Advanced  | Toggle: Auto-stop on silence (tooltip), Sliders: threshold + duration (conditional), Picker: Microphone device, Mic test controls |

**Tooltips:**
- Hold to record: "When enabled, recording stops when you release the hotkey. When disabled, press once to start and once to stop."
- Minimum duration: "Recordings shorter than this are discarded. Prevents accidental triggers."
- Auto-stop on silence: "Automatically stop recording when no speech is detected for a set duration."

### Speech Model

Sections: **Privacy badge** (inline) → **Built-in Models** → **Custom Models** → **Quick Switch (← →)**

Model cards remain inside Form sections. The `SettingsSection` wrapper is replaced with real `Section`.

**Tooltips:**
- Built-in Models header: "Speech-to-text models that run locally on your Mac. Larger models are more accurate but use more memory."
- Custom Models header: "Import Whisper-compatible models from Hugging Face to use models not included by default."
- Quick Switch header: "Pin up to 3 models to quickly switch between them using hotkey + arrow keys."

**Footer text:** "Click a model to switch. Larger models use more memory but produce better transcriptions."

### Transcription (renamed from "Output")

Sections: **Delivery** → **Text Cleanup** → **Sound Feedback**

Sound Feedback is promoted from inside an Advanced DisclosureGroup to its own top-level section (it's not advanced).

| Section        | Controls                                                      |
|----------------|---------------------------------------------------------------|
| Delivery       | Toggle: Instant output (tooltip), Toggle: Restore clipboard (tooltip), Toggle: Add space |
| Text Cleanup   | Toggle: Remove filler words (tooltip), Toggle: Normalize numbers |
| Sound Feedback | Toggle: Play sound on success, Picker/button: Sound selection  |

**Tooltips:**
- Instant output: "Pastes transcription directly into the active app using the clipboard. Temporarily replaces your clipboard contents."
- Restore clipboard: "After pasting, restores whatever was on your clipboard before the transcription."
- Text Cleanup header: "Automatic corrections applied to transcriptions before output. These run locally and don't use AI."
- Remove filler words: "Removes 'um', 'uh', 'like', 'you know' and similar filler words from transcriptions."

**Footer text:** "Transcribed text is pasted into whichever app was active when you started recording." / "Example: 'two hundred dollars' → '$200'"

### Tones

**Explainer paragraph** below title (not a tooltip — the whole concept needs introduction):
> "Tones use AI to refine your transcription — fixing grammar, adjusting formality, or rewriting in a specific style. Choose 'None' to get the raw transcription."

Sections: **Preset Tones** → **Custom Tones** → **AI Provider** (conditional) → **Quick Switch (↑↓)**

| Section       | Controls                                                            |
|---------------|---------------------------------------------------------------------|
| Preset Tones  | 2-column LazyVGrid of TonePresetCards inside Section                |
| Custom Tones  | List of custom tones + "Create Custom Tone" button, inline editor   |
| AI Provider   | Picker: Provider (Apple Intelligence / Ollama), status/config below |
| Quick Switch  | Reorderable pinned list, "Original" always first                    |

**Tooltips:**
- Custom Tones header: "Write your own AI prompt to control exactly how transcriptions are refined. Full Markdown supported."
- AI Provider header: "Which AI service processes your transcription. Apple Intelligence runs on-device. Ollama requires a local server."
- Quick Switch header: "Pin tones to quickly switch between them using hotkey + up/down arrow keys while recording."

**Footer text:** "Select a tone to apply to all transcriptions. You can also create custom tones with your own AI prompt." / "Apple Intelligence processes text on-device. Ollama requires running a local AI server."

### General

Sections: **Startup** → **Privacy** → **About** → **Storage**

Reordered from current (Privacy was first). Startup is most commonly used, moved to top.

| Section  | Controls                                                          |
|----------|-------------------------------------------------------------------|
| Startup  | Toggle: Launch at login (tooltip)                                 |
| Privacy  | Toggle: Hide from screen recording (tooltip)                      |
| About    | LabeledContent: Version, LabeledContent: Build                    |
| Storage  | LabeledContent: Total model storage, Button: Delete All Models (destructive) |

**Tooltips:**
- Launch at login: "Automatically start VoxNotch when you log into your Mac."
- Hide from screen recording: "When enabled, VoxNotch windows won't appear in screen recordings, screenshots by other apps, or screen sharing."
- Storage header: "Disk space used by downloaded speech models. Deleting models frees space but you'll need to re-download them."

### History

Sections: **History** → **Retention** (conditional) → **Storage**

Retention section only visible when history is enabled.

| Section   | Controls                                                             |
|-----------|----------------------------------------------------------------------|
| History   | Toggle: Save dictation history (tooltip)                             |
| Retention | Picker: Auto-delete after (tooltip), Toggle: Save audio (tooltip)    |
| Storage   | LabeledContent: Saved transcriptions, Button: Clear All History (destructive) |

**Tooltips:**
- Save dictation history: "Saves all your transcriptions locally so you can search and review them later."
- Auto-delete after: "Automatically removes transcriptions older than this. Set to 'Forever' to keep everything."
- Save audio recordings: "Also saves the original audio alongside each transcription. Uses more disk space."

**Footer text:** "View your history from the menu bar icon → History." / "Audio recordings let you re-transcribe with a different model later."

## What Does NOT Change

- `SettingsWindowController.swift` — window sizing, presentation, autosave
- `SettingsManager.swift` — all settings properties and persistence
- `HotkeyRecorderView.swift` — custom hotkey recorder
- `PromptEditorView.swift` — markdown prompt editor
- `CustomModelSheet.swift` / `HFModelBrowserSheet.swift` — modal sheets
- Deep-linking via `NotificationCenter` (`.settingsNavigateTo`)
- All existing settings properties and their behavior

## Verification

1. Build and run — settings window opens, all 6 tabs render correctly
2. Every toggle/picker/slider still reads and writes the correct `SettingsManager` property
3. Tooltips appear on hover for all listed controls
4. Sidebar groups display with section headers
5. Sidebar selection + deep-linking navigation still works
6. Progressive disclosure: Advanced section collapses/expands, conditional sections appear/hide
7. Model cards: selection, download, progress UI still functional
8. Tone presets: selection, custom tone creation/editing still functional
9. Destructive actions (Delete All Models, Clear All History) still show confirmation dialogs
10. Window size and autosave behavior unchanged
