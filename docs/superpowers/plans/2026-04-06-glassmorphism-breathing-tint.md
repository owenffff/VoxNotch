# Glassmorphism + Breathing Tint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a frosted glass backdrop with gradient fade and a breathing color tint during recording to the notch.

**Architecture:** An `NSViewRepresentable` wrapping `NSVisualEffectView` provides real behind-window blur. It's masked by a vertical gradient (clear top → opaque bottom) so the top stays black to blend with the physical notch. A full-bleed color rectangle with narrow opacity oscillation (0.02–0.07) overlays the glass during recording. Everything is clipped by the existing `NotchShape`.

**Tech Stack:** SwiftUI, AppKit (`NSVisualEffectView`, `NSViewRepresentable`), existing `NotchShape`

**Spec:** `docs/superpowers/specs/2026-04-06-glassmorphism-breathing-tint-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `VoxNotch/Notch/VibrancyBackground.swift` | Create | NSViewRepresentable wrapping NSVisualEffectView |
| `VoxNotch/Notch/NotchContentView.swift` | Modify | Add vibrancy layer, breathing tint, recording state |

---

### Task 1: Create VibrancyBackground

**Files:**
- Create: `VoxNotch/Notch/VibrancyBackground.swift`

- [ ] **Step 1: Create the file**

Create `VoxNotch/Notch/VibrancyBackground.swift`:

```swift
//
//  VibrancyBackground.swift
//  VoxNotch
//
//  NSViewRepresentable wrapping NSVisualEffectView for behind-window blur.
//

import SwiftUI

struct VibrancyBackground: NSViewRepresentable {

    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild -scheme VoxNotch -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VoxNotch/Notch/VibrancyBackground.swift
git commit -m "feat(notch): add VibrancyBackground NSViewRepresentable for frosted glass"
```

---

### Task 2: Integrate glassmorphism + breathing tint into NotchContentView

**Files:**
- Modify: `VoxNotch/Notch/NotchContentView.swift`

The current file has this structure (relevant parts):

```swift
struct NotchContentView: View {
  private let notchManager = NotchManager.shared
  // ... sizing, corner radii, animation ...

  var body: some View {
    VStack(spacing: 0) {
      Color.clear.frame(height: notchManager.physicalNotchSize.height)
      if notchManager.notchState == .expanded {
        NotchExpandedFallbackView()
          .frame(height: expandedContentHeight)
          .transition(...)
      }
    }
    .frame(width: currentWidth, height: currentHeight)
    .background(.black)
    .clipShape(NotchShape(...))
    .shadow(...)
    .compositingGroup()
    .opacity(currentOpacity * notchManager.panelOpacity)
    .allowsHitTesting(...)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .animation(animation, value: notchManager.notchState)
  }
}
```

- [ ] **Step 1: Add appState reference and recording breath state**

Add these two properties at the top of the struct, after the existing `notchManager`:

```swift
  private let notchManager = NotchManager.shared
  private let appState = AppState.shared

  @State private var recordingBreath = false
```

- [ ] **Step 2: Add the vibrancy background layer**

Insert a `.background { ... }` modifier AFTER the existing `.background(.black)` and BEFORE `.clipShape(...)`:

```swift
    .background(.black)
    .background {
      VibrancyBackground(material: .sidebar)
        .mask {
          LinearGradient(
            colors: [.clear, .black],
            startPoint: .top,
            endPoint: .bottom
          )
        }
    }
    .overlay {
      Color(red: 158/255, green: 135/255, blue: 188/255)
        .opacity(
          appState.dictationPhase == .recording
            ? (recordingBreath ? 0.07 : 0.02) : 0
        )
        .animation(
          appState.dictationPhase == .recording
            ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
            : .easeInOut(duration: 0.4),
          value: recordingBreath
        )
        .animation(.easeInOut(duration: 0.4), value: appState.dictationPhase)
    }
    .clipShape(
```

- [ ] **Step 3: Add onChange to start/stop breathing**

Add an `.onChange` modifier after the existing `.animation(animation, value: notchManager.notchState)` at the end of the body:

```swift
    .animation(animation, value: notchManager.notchState)
    .onChange(of: appState.dictationPhase) { _, phase in
      if case .recording = phase {
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
          recordingBreath = true
        }
      } else {
        recordingBreath = false
      }
    }
```

- [ ] **Step 4: Build and verify**

```bash
cd /Users/jingyuan.liang/Desktop/dev/VoxNotch && xcodebuild -scheme VoxNotch -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add VoxNotch/Notch/NotchContentView.swift
git commit -m "feat(notch): glassmorphism backdrop with gradient fade + breathing tint during recording"
```

---

### Task 3: Manual smoke test

- [ ] **Step 1: Run and test**

Build and run the app. Test:
1. Expand the notch — the bottom portion should show subtle frosted glass effect, fading to black at the top near the physical notch.
2. Start recording — a subtle Lilac Haze tint should pulse gently (barely perceptible, 0.02–0.07 opacity).
3. Stop recording — the tint fades out over ~0.4s.
4. The glassmorphism backdrop should be visible in ALL expanded states, not just recording.
5. Verify the top of the notch still blends seamlessly with the physical MacBook notch (black).
6. Verify nothing bleeds outside the notch shape.

- [ ] **Step 2: Tune if needed**

Adjustable values in `NotchContentView.swift`:
- Tint opacity range: 0.02/0.07 (increase for more visible pulse)
- Breath duration: 0.85s (slower = more relaxed)
- Gradient stops: can add intermediate stops for different fade curve
- Material: `.sidebar` (try `.hudWindow` or `.popover` for different glass looks)

- [ ] **Step 3: Commit tuning changes**

```bash
git add -A
git commit -m "feat(notch): tune glassmorphism + breathing tint parameters"
```

(Skip if no tuning needed.)
