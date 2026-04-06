# Smooth Notch Collapse + Frosted Edge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the visible snap when the notch collapses by fading opacity before `orderOut`, and add a frosted glass edge halo when expanded.

**Architecture:** Two independent changes to the existing notch animation system. Change 1 adds a `panelOpacity` property to `NotchManager` and sequences a fade-out animation before `orderOut`. Change 2 overlays `.ultraThinMaterial` with a soft ring mask inside `NotchContentView` when expanded.

**Tech Stack:** Swift, SwiftUI, AppKit (NSPanel)

---

### Task 1: Add `panelOpacity` and fade-out task to NotchManager

**Files:**
- Modify: `VoxNotch/Notch/NotchManager.swift`

- [ ] **Step 1: Add `panelOpacity` property and `fadeOutTask`**

In `NotchManager`, add these alongside the existing observable state and private properties:

```swift
// In "Observable State" section, after `hasPhysicalNotch`:
/// Opacity multiplier for the entire notch overlay.
/// Animated to 0 before `orderOut` to avoid the visible snap.
var panelOpacity: CGFloat = 1.0

// In "Private" section, after `orderOutTask`:
private var fadeOutTask: Task<Void, Never>?
```

- [ ] **Step 2: Add `cancelFadeOut` helper**

Add alongside `cancelOrderOut()`:

```swift
private func cancelFadeOut() {
  fadeOutTask?.cancel()
  fadeOutTask = nil
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add VoxNotch/Notch/NotchManager.swift
git commit -m "feat(notch): add panelOpacity property and fadeOutTask"
```

---

### Task 2: Wire fade-out sequencing into hide paths

**Files:**
- Modify: `VoxNotch/Notch/NotchManager.swift`

- [ ] **Step 1: Create `scheduleFadeAndOrderOut` helper**

Replace the existing `scheduleOrderOut()` method with a new `scheduleFadeAndOrderOut()` that sequences: wait 0.35s → fade opacity to 0 over 0.2s → wait 0.25s → `orderOut`:

```swift
/// Fade the notch overlay to transparent, then order out the panel.
/// Timeline: 0.35s wait (spring mostly settled) → 0.2s opacity fade → orderOut.
private func scheduleFadeAndOrderOut() {
  cancelFadeOut()
  fadeOutTask = Task { [weak self] in
    // Wait for the spring collapse to mostly settle.
    try? await Task.sleep(for: .seconds(0.35))
    guard let self, !Task.isCancelled else { return }

    withAnimation(.easeOut(duration: 0.2)) {
      self.panelOpacity = 0
    }

    // Wait for the opacity fade to complete, then remove the panel.
    try? await Task.sleep(for: .seconds(0.25))
    guard let self, !Task.isCancelled else { return }
    self.panel?.orderOut(nil)
  }
}
```

- [ ] **Step 2: Update `hide()` to use `scheduleFadeAndOrderOut`**

Replace the current `hide()` method:

```swift
func hide() {
  cancelAutoHide()
  withAnimation(.smooth(duration: 0.4)) {
    appState.isShowingSuccess = false
    appState.isShowingClipboard = false
    appState.isShowingConfirmation = false
  }
  withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
    notchState = .hidden
  }
  scheduleFadeAndOrderOut()
}
```

- [ ] **Step 3: Update `scheduleAutoHide(after:)` to use `scheduleFadeAndOrderOut`**

Replace the current `scheduleAutoHide(after:)` method:

```swift
private func scheduleAutoHide(after seconds: Double) {
  autoHideTask = Task { [weak self] in
    try? await Task.sleep(for: .seconds(seconds))
    guard let self, !Task.isCancelled else { return }
    withAnimation(.smooth(duration: 0.4)) {
      self.appState.isShowingSuccess = false
      self.appState.isShowingClipboard = false
      self.appState.isShowingConfirmation = false
      self.appState.lastError = nil
      self.appState.lastErrorRecovery = nil
    }
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      self.notchState = .hidden
    }
    self.scheduleFadeAndOrderOut()
  }
}
```

- [ ] **Step 4: Update `showExpanded()` to reset opacity and cancel fade**

Replace the current `showExpanded()` method:

```swift
private func showExpanded() {
  cancelOrderOut()
  cancelFadeOut()
  panelOpacity = 1.0
  ensurePanelVisible()

  guard notchState != .expanded else { return }
  withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
    notchState = .expanded
  }
}
```

Note: `panelOpacity = 1.0` is set without animation — the panel may not be visible yet, so no transition is needed.

- [ ] **Step 5: Remove the old `scheduleOrderOut` method**

Delete the `scheduleOrderOut()` method entirely — it is fully replaced by `scheduleFadeAndOrderOut()`. Keep `cancelOrderOut()` since `scheduleFadeAndOrderOut` still uses `orderOutTask` internally... actually, looking at the new code, `scheduleFadeAndOrderOut` uses `fadeOutTask` and calls `panel?.orderOut(nil)` directly. We should update it to also use `orderOutTask` for consistency, or simplify.

Delete the following items that are no longer needed — `scheduleFadeAndOrderOut` fully replaces them, and `showExpanded()` now calls `cancelFadeOut()` instead of `cancelOrderOut()`:

1. Delete `scheduleOrderOut()` method
2. Delete `cancelOrderOut()` method
3. Delete `private var orderOutTask: Task<Void, Never>?` property

- [ ] **Step 6: Build to verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add VoxNotch/Notch/NotchManager.swift
git commit -m "feat(notch): fade opacity to 0 before orderOut to eliminate snap"
```

---

### Task 3: Apply `panelOpacity` in NotchContentView

**Files:**
- Modify: `VoxNotch/Notch/NotchContentView.swift`

- [ ] **Step 1: Multiply `currentOpacity` by `panelOpacity`**

In `NotchContentView`, change line 106 from:

```swift
.opacity(currentOpacity)
```

to:

```swift
.opacity(currentOpacity * notchManager.panelOpacity)
```

No other changes to this file in this task.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/Notch/NotchContentView.swift
git commit -m "feat(notch): wire panelOpacity into NotchContentView"
```

---

### Task 4: Add frosted glass edge halo overlay

**Files:**
- Modify: `VoxNotch/Notch/NotchContentView.swift`

- [ ] **Step 1: Add the frosted glass overlay**

In the `body` of `NotchContentView`, add an `.overlay` modifier between `.background(.black)` (line 93) and `.clipShape(...)` (line 94). The overlay uses `.ultraThinMaterial` masked to a soft ring that excludes the top physical notch region:

Replace the current modifier chain:

```swift
.frame(width: currentWidth, height: currentHeight)
.background(.black)
.clipShape(
```

with:

```swift
.frame(width: currentWidth, height: currentHeight)
.background(.black)
.overlay {
  if notchManager.notchState == .expanded {
    Rectangle()
      .fill(.ultraThinMaterial)
      .mask {
        VStack(spacing: 0) {
          // Physical notch area: no frosted effect.
          Color.clear
            .frame(height: notchManager.physicalNotchSize.height)
          // Expanded content area: soft-edged ring.
          ZStack {
            Color.white
            Color.white
              .padding(8)
              .blur(radius: 6)
              .blendMode(.destinationOut)
          }
          .compositingGroup()
        }
      }
      .transition(.opacity)
  }
}
.clipShape(
```

**How this works:**
- `Rectangle().fill(.ultraThinMaterial)` fills the entire frame with frosted glass.
- The mask has two zones: `Color.clear` at top (hides material over the physical notch) and a ring in the bottom zone.
- The ring is created by drawing a full white rectangle, then cutting out the center with `.blendMode(.destinationOut)` and `.blur(radius: 6)` for a soft ~8pt gradient edge.
- `.clipShape(NotchShape(...))` (applied after) clips the outer boundary to the notch contour.
- `.transition(.opacity)` fades the overlay in/out with the expand/collapse animation.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme VoxNotch -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Visual verification**

Run the app and trigger a dictation. Verify:
1. **Expanded state:** A subtle frosted glass halo is visible at the outer edges of the expanded notch content area. The center is solid black. The top physical notch region has no frosted effect.
2. **Collapse:** The frosted halo fades out as the notch collapses. The notch dissolves smoothly into the physical notch — no snap or pop.
3. **Re-expand:** The notch appears at full opacity with the frosted halo. No visual glitches from the previous fade-out.

If `.ultraThinMaterial` doesn't produce a visible effect (because the notch area overlaps the menu bar which is dark), try replacing `.ultraThinMaterial` with `.regularMaterial` or `.thickMaterial` for a more pronounced effect during testing. Adjust back to the subtlest option that's still visible.

- [ ] **Step 4: Commit**

```bash
git add VoxNotch/Notch/NotchContentView.swift
git commit -m "feat(notch): add frosted glass edge halo when expanded"
```

---

### Task 5: Final integration test

- [ ] **Step 1: Full flow verification**

Run the app and test the complete flow:
1. Trigger dictation → notch expands with frosted edge
2. Complete dictation → success overlay shows, then notch collapses with smooth fade
3. Trigger again quickly during collapse → notch re-expands cleanly (opacity resets, no ghost)
4. Let auto-hide timer fire → same smooth fade-out
5. On a non-notch Mac (or external display): notch should fade to transparent as before, with no visible snap

- [ ] **Step 2: Commit any adjustments**

If any timing or visual tweaks were needed, commit them:

```bash
git add -A
git commit -m "fix(notch): tune animation timing for smooth collapse"
```
