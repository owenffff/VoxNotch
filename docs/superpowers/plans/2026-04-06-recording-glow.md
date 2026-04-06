# Recording Glow Effect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a breathing inner glow to the notch during recording that fades in/out fluidly with dictation state.

**Architecture:** A new `NotchGlowOverlay` SwiftUI view strokes the `NotchShape` path and blurs it to create an inner edge glow. It's placed as an `.overlay` on the notch body inside the existing `.clipShape`, so the outer half of the stroke is clipped away — leaving only the inward-bleeding glow. A repeating `easeInOut` animation drives the breathing pulse; a separate transition animation handles fade-in/out.

**Tech Stack:** SwiftUI, `@Observable` (AppState/NotchManager singletons), existing `NotchShape`

**Spec:** `docs/superpowers/specs/2026-04-06-recording-glow-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `VoxNotch/Notch/NotchGlowOverlay.swift` | Create | Inner glow rendering + breathing animation + fade lifecycle |
| `VoxNotch/Notch/NotchContentView.swift` | Modify | Add `.overlay { NotchGlowOverlay(...) }` and `AppState.shared` reference |

---

### Task 1: Create NotchGlowOverlay view

**Files:**
- Create: `VoxNotch/Notch/NotchGlowOverlay.swift`

- [ ] **Step 1: Create the glow overlay file**

Create `VoxNotch/Notch/NotchGlowOverlay.swift` with the full implementation:

```swift
//
//  NotchGlowOverlay.swift
//  VoxNotch
//
//  Soft inner glow that breathes while recording.
//  Rendered as a blurred stroke of NotchShape, clipped by the parent.
//

import SwiftUI

struct NotchGlowOverlay: View {

  /// Whether the glow should be visible (recording state).
  var isActive: Bool

  /// Corner radii matching the parent NotchShape.
  var topCornerRadius: CGFloat
  var bottomCornerRadius: CGFloat

  // MARK: - Glow Configuration

  /// Lilac Haze — soft desaturated purple.
  static let glowColor = Color(red: 158/255, green: 135/255, blue: 188/255)

  private let strokeWidth: CGFloat = 6
  private let blurRadius: CGFloat = 8
  private let breatheMin: CGFloat = 0.3
  private let breatheMax: CGFloat = 0.6
  private let breathePeriod: TimeInterval = 2.0

  // MARK: - State

  @State private var breathing = false

  // MARK: - Body

  var body: some View {
    NotchShape(
      topCornerRadius: topCornerRadius,
      bottomCornerRadius: bottomCornerRadius
    )
    .stroke(Self.glowColor, lineWidth: strokeWidth)
    .blur(radius: blurRadius)
    .opacity(isActive ? (breathing ? breatheMax : breatheMin) : 0)
    .animation(
      isActive
        ? .easeInOut(duration: breathePeriod / 2).repeatForever(autoreverses: true)
        : .easeOut(duration: 0.5),
      value: breathing
    )
    .animation(.easeOut(duration: isActive ? 0.4 : 0.5), value: isActive)
    .onChange(of: isActive) { _, active in
      if active {
        breathing = true
      } else {
        breathing = false
      }
    }
    .allowsHitTesting(false)
  }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

The project uses Xcode's automatic file discovery or pbxproj references. Add the file to the Xcode project's `VoxNotch/Notch` group. If using Xcode file navigator, drag the file into the Notch group. If the project auto-discovers files in the directory, this step is automatic.

Run a build to verify:

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild -scheme VoxNotch -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (the view exists but isn't referenced yet, so it just needs to compile)

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/Notch/NotchGlowOverlay.swift
git commit -m "feat(notch): add NotchGlowOverlay view with breathing animation"
```

---

### Task 2: Integrate glow overlay into NotchContentView

**Files:**
- Modify: `VoxNotch/Notch/NotchContentView.swift`

- [ ] **Step 1: Add AppState reference**

In `NotchContentView.swift`, add an `appState` property next to the existing `notchManager`:

```swift
struct NotchContentView: View {

  private let notchManager = NotchManager.shared
  private let appState = AppState.shared
```

- [ ] **Step 2: Add the glow overlay**

In the `body`, insert `.overlay { ... }` between `.background(.black)` and `.clipShape(...)`. The full modifier chain becomes:

```swift
    .frame(width: currentWidth, height: currentHeight)
    .background(.black)
    .overlay {
      NotchGlowOverlay(
        isActive: notchManager.notchState == .expanded
          && appState.dictationPhase == .recording,
        topCornerRadius: topCornerRadius,
        bottomCornerRadius: bottomCornerRadius
      )
    }
    .clipShape(
      NotchShape(
        topCornerRadius: topCornerRadius,
        bottomCornerRadius: bottomCornerRadius
      )
    )
    .shadow(
```

The key insertion point is after `.background(.black)` (line 93) and before `.clipShape(` (line 94). The existing `.clipShape` clips the glow so nothing bleeds outside.

- [ ] **Step 3: Build and verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild -scheme VoxNotch -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add VoxNotch/Notch/NotchContentView.swift
git commit -m "feat(notch): integrate recording glow overlay into notch content view"
```

---

### Task 3: Manual smoke test

- [ ] **Step 1: Run the app and test the glow**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && open VoxNotch.xcodeproj
```

1. Build and run the app (Cmd+R in Xcode).
2. Trigger a recording with the hotkey.
3. Verify:
   - The notch expands and a soft purple inner glow fades in (~0.4s).
   - The glow pulses/breathes while recording (subtle opacity oscillation).
   - Stop recording — the glow fades out smoothly (~0.5s) while the notch transitions to the next state.
   - The glow does NOT appear during transcribing, processing, success, or error states.
   - The glow does NOT bleed outside the notch shape boundary.

- [ ] **Step 2: Tune if needed**

If the glow is too intense or too subtle, adjust these values in `NotchGlowOverlay.swift`:
- `strokeWidth` (default 6) — thicker = wider glow band
- `blurRadius` (default 8) — higher = softer/more diffuse
- `breatheMin` / `breatheMax` (default 0.3/0.6) — opacity range
- `breathePeriod` (default 2.0s) — slower = more relaxed breathing

- [ ] **Step 3: Final commit after tuning**

```bash
git add -A
git commit -m "feat(notch): recording glow effect — tuned values"
```

(Skip this commit if no tuning was needed.)
