# Flexible Onboarding Design

**Date:** 2026-04-05
**Status:** Approved

## Problem

Onboarding is rigid — 5 sequential steps where the user cannot skip the 500MB model download or other gated steps. If a user is on step 3 staring at a large download, they're stuck. The only escape is "Skip Setup" on the Welcome screen, which bypasses everything.

## Goals

- Let users skip any gated step (Permissions, Model, Tutorial) and come back later
- Keep the guided linear flow — don't turn it into a free-form dashboard
- Show contextual nudges at first use when skipped steps matter (no persistent nagging)
- Adapt the tutorial to what's actually available

## Approach

**Step State Model (Approach B):** Each skippable step tracks its own completion state (`pending`, `completed`, `skipped`) persisted in `SettingsManager`. The existing linear navigation stays but gains per-step Skip buttons. The master `hasCompletedOnboarding` flag remains unchanged.

## Design

### 1. Step State Model

New enum (in `OnboardingView.swift`, alongside the existing `OnboardingStep` enum):

```swift
enum OnboardingStepState: String {
  case pending
  case completed
  case skipped
}
```

Three new persisted properties in `SettingsManager`:

| Key | Type | Default |
|-----|------|---------|
| `onboardingPermissionsState` | `String` | `"pending"` |
| `onboardingModelState` | `String` | `"pending"` |
| `onboardingTutorialState` | `String` | `"pending"` |

Welcome and Complete steps don't need state tracking — Welcome has no gate, Complete is the terminal step.

### 2. Navigation Changes

Skip/Later button appears on Permissions, Model, and Tutorial steps, positioned on the left side of the navigation bar:

```
[Back]  [Skip]                    [Continue]
```

**Per-step behavior:**

| Step | Skip available? | Gate removed? | Notes |
|------|----------------|---------------|-------|
| Welcome | No (has existing "Skip Setup") | N/A | "Skip Setup" jumps to `completeOnboarding()` as today |
| Permissions | Yes, always | Yes | User gets nudged at first dictation if permissions missing |
| Model | Yes, unless download in progress | Partial — "Continue" still requires download, but "Skip" bypasses | Two paths: download-then-continue, or skip |
| Tutorial | Yes, always | Yes | `allCompleted` gate on Continue removed |
| Complete | No | N/A | Terminal step |

When Skip is pressed:
1. Step state persisted as `.skipped`
2. `advanceStep()` called — user moves forward

During active model download: Skip and Back are both disabled (matches current Back behavior).

### 3. Adaptive Tutorial

The tutorial checklist adapts based on model availability:

**Model available:** All 4 items — press hotkey, release hotkey, model switch, tone switch.

**No model (skipped model step):** 2 items only — press hotkey, release hotkey. Model-switch and tone-switch rows are hidden entirely (not greyed out).

Changes to `TutorialHotkeyCoordinator`:
- Accept a `hasModel: Bool` parameter (or derive from `SpeechModel` state)
- Filter `availableItems` based on `hasModel`
- `allCompleted` checks only available items

Changes to `OnboardingView.tutorialStep`:
- Filter the `ForEach` to only show rows for available items

The coordinator still calls `QuickDictationController.shared.start()` on activate — hotkey press/release works without a model.

### 4. First-Use Nudges

**Model nudge:** Already built. `QuickDictationController` (lines 298-305) detects `!isModelDownloaded`, sets `appState.modelsNeeded`, and calls `NotchManager.shared.showModelsNeeded(...)`.

One change: when `onboardingModelState == .skipped` and no model exists on disk, use a more actionable message:
- Current: `"Not downloaded: Parakeet v2"`
- New: `"Download a speech model in Settings to start dictating"`

**Permissions nudge:** Already handled. `QuickDictationController` checks mic permission before recording; `HotkeyManager` checks accessibility. No new code needed.

No persistent badges, no menu bar indicators. Nudges appear only when the user tries an action that requires the missing step.

### 5. Complete Step Adaptation

The "Ready!" screen reflects what actually happened:

**All steps completed:**
- Icon: green checkmark seal (current)
- Title: "You're All Set!"
- Subtitle: "Hold [hotkey] to start dictating."

**Some steps skipped:**
- Icon: orange exclamation mark
- Title: "You're Almost Set!"
- Subtitle: conditional lines based on what was skipped:
  - Skipped model: "Download a speech model in Settings before dictating."
  - Skipped permissions: "Grant Microphone and Accessibility permissions in Settings."
  - Skipped both: both lines shown

This is copy/icon changes in the existing `completeStep` view, reading from step states. No new UI components.

## Files to Modify

| Action | File | Change |
|--------|------|--------|
| Modify | `VoxNotch/Managers/SettingsManager.swift` | Add 3 step state keys + properties |
| Modify | `VoxNotch/Views/Onboarding/OnboardingView.swift` | Add Skip buttons, read/write step states, adapt tutorial filter, adapt complete step |
| Modify | `VoxNotch/Views/Onboarding/TutorialHotkeyCoordinator.swift` | Add `hasModel` parameter, filter available items |
| Modify | `VoxNotch/Controllers/QuickDictationController.swift` | Improve "no model" nudge message for skipped-onboarding case |

No new files needed.

## Out of Scope

- Freely navigable (tab-style) onboarding steps
- Persistent badges or menu bar indicators for incomplete steps
- Background model downloading during other onboarding steps
- Resumable model downloads across app quits
- Decomposing `OnboardingView.swift` into per-step files (can do later)
