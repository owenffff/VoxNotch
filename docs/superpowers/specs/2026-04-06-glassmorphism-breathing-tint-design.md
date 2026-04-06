# Glassmorphism + Breathing Tint — Design Spec

## Summary

Replace the flat black notch background with a frosted glass (glassmorphism) backdrop that fades in from the bottom, topped with a subtle breathing color tint during recording. The glass composites with real desktop pixels via `NSVisualEffectView` with `.behindWindow` blending, masked by a vertical gradient so the top stays black (blending with the physical MacBook notch) and the bottom shows frosted glass.

## Requirements

- **Glassmorphism**: `NSVisualEffectView` with `.behindWindow` blending, `.sidebar` material, `.active` state.
- **Gradient fade**: Masked by a `LinearGradient` from `.clear` (top) to `.black` (bottom). The top of the notch stays opaque black to match the physical notch; frosted glass gradually appears toward the bottom.
- **Breathing tint**: A full-bleed color rectangle in Lilac Haze `rgb(158, 135, 188)` with opacity pulsing between 0.02 and 0.07 on a repeating `easeInOut(duration: 0.85)` animation.
- **Recording only**: Tint visible only when `dictationPhase == .recording`. Fades out over 0.4s when recording stops.
- **Clipping**: All layers clipped by the existing `NotchShape` — nothing bleeds outside.
- **Physical notch blending**: The top region must remain visually black to blend seamlessly with the hardware notch.

## Architecture

### Layer stack (bottom → top, inside NotchShape clip)

1. `.background(.black)` — base layer, always present
2. `VibrancyBackground` (NSVisualEffectView) — frosted glass, masked with vertical gradient
3. Breathing tint rect — Lilac Haze color, opacity pulses during recording
4. Content — existing `NotchExpandedFallbackView`

### New file: `VoxNotch/Notch/VibrancyBackground.swift`

`NSViewRepresentable` wrapping `NSVisualEffectView`:
- `material`: configurable (`.sidebar` for dark appearance)
- `blendingMode`: `.behindWindow` (samples real desktop pixels)
- `state`: `.active` (always on, even when window loses focus)
- `updateNSView`: no-op (material doesn't change at runtime)

### Modified file: `VoxNotch/Notch/NotchContentView.swift`

Changes:
1. Add `private let appState = AppState.shared`
2. Add `@State private var recordingBreath = false`
3. Add `.background { VibrancyBackground(...).mask { LinearGradient(...) } }` after `.background(.black)`
4. Add `.overlay { Color(...).opacity(...) }` for breathing tint
5. Add `.onChange(of: appState.dictationPhase)` to start/stop breath animation

The modifier chain becomes:
```
.background(.black)
.background { VibrancyBackground(material: .sidebar).mask { gradient } }
.overlay { breathing tint }
.clipShape(NotchShape(...))
.shadow(...)
```

## Breathing animation details

- **State**: `@State private var recordingBreath: Bool = false`
- **Opacity**: `dictationPhase == .recording ? (recordingBreath ? 0.07 : 0.02) : 0`
- **Breathing animation**: `.easeInOut(duration: 0.85).repeatForever(autoreverses: true)`, keyed on `recordingBreath`
- **Fade-out animation**: `.easeInOut(duration: 0.4)`, keyed on `dictationPhase`
- **Start**: `onChange(of: dictationPhase)` — when `.recording`, call `withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { recordingBreath = true }`
- **Stop**: when not `.recording`, set `recordingBreath = false` (the declarative animation block handles fade-out)

## Tuning parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| Tint color | rgb(158, 135, 188) | Lilac Haze — configurable constant |
| Tint opacity min | 0.02 | Dimmest point of breath |
| Tint opacity max | 0.07 | Brightest point of breath |
| Breath duration | 0.85s | Half-cycle of easeInOut |
| Fade-out duration | 0.4s | How fast tint disappears |
| Gradient start | .clear | Top of notch (invisible glass) |
| Gradient end | .black | Bottom of notch (full glass) |
| Material | .sidebar | Dark frosted glass appearance |

## Edge cases

- **External monitors (no physical notch)**: The gradient mask still applies — the top is clear (showing black base), bottom shows glass. The existing `currentOpacity` fade on external monitors also fades the entire compositing group.
- **Rapid start/stop recording**: `recordingBreath` reset to false triggers the declarative animation for fade-out; SwiftUI interpolates from current opacity. No visual glitches.
- **Non-recording expanded states**: Tint opacity is 0. The glassmorphism backdrop is always visible when expanded — this is intentional, it gives the expanded notch a premium look at all times, not just during recording.
- **Hidden/collapsed state**: The notch is clipped to physical notch size with black background — the glass layer is present but invisible because the gradient mask makes the top region fully transparent.

## Files changed

| File | Change |
|------|--------|
| `VoxNotch/Notch/VibrancyBackground.swift` | New — NSViewRepresentable for frosted glass |
| `VoxNotch/Notch/NotchContentView.swift` | Add vibrancy layer, breathing tint overlay, recording breath state |

## Files unchanged

- `NotchShape.swift` — reused as-is for clipping
- `NotchExpandedFallbackView.swift` — content unaffected
- `NotchPanel.swift` — window config unaffected (already has `isOpaque = false`, `backgroundColor = .clear`)
