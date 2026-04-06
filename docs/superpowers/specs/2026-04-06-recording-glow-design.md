# Recording Glow Effect — Design Spec

## Summary

Add a soft inner glow to the expanded notch during recording. The glow fades in when recording starts, breathes (pulses opacity) while active, and fades out fluidly when recording ends. Implemented as a SwiftUI overlay using a stroke+blur technique clipped to the notch shape.

## Requirements

- **When**: Glow is visible only when the notch is expanded AND `dictationPhase == .recording`.
- **Color**: Lilac Haze `rgb(158, 135, 188)` — soft, desaturated purple. Defined as a constant for easy backend configurability.
- **Placement**: Inner glow bleeding inward from the notch edges.
- **Animation — breathing**: Opacity oscillates between ~0.3 and ~0.6 with a repeating `easeInOut` animation, ~2s period. Creates a subtle "alive" pulse while recording.
- **Animation — fade in**: ~0.4s ease-in when recording starts.
- **Animation — fade out**: ~0.5s ease-out when recording ends (slightly slower for fluid feel).
- **Clipping**: Glow must not bleed outside the notch shape boundary.

## Architecture

### New file: `VoxNotch/Notch/NotchGlowOverlay.swift`

A SwiftUI view with these responsibilities:

1. Accept `isActive: Bool`, `topCornerRadius: CGFloat`, `bottomCornerRadius: CGFloat`.
2. Render an inner glow by stroking the `NotchShape` with `glowColor` at `lineWidth: ~6`, then applying `.blur(radius: ~8)`.
3. Because the parent view clips with the same `NotchShape`, the outer half of the stroke is cut away — only the inward-bleeding half remains, creating the inner edge glow.
4. When `isActive` is true: fade in over 0.4s, then start a repeating breathing animation (opacity 0.3 <-> 0.6, 2s period, `easeInOut`).
5. When `isActive` becomes false: stop breathing, fade opacity to 0 over 0.5s.

### Modified file: `VoxNotch/Notch/NotchContentView.swift`

Add the glow overlay between `.background(.black)` and `.clipShape(...)`:

```swift
.background(.black)
.overlay {
  NotchGlowOverlay(
    isActive: notchManager.notchState == .expanded
              && AppState.shared.dictationPhase == .recording,
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
```

Add a reference to `AppState.shared` (already a singleton, no new dependency injection needed).

### Glow color constant

Defined in `NotchGlowOverlay.swift`:

```swift
private static let glowColor = Color(
  red: 158/255, green: 135/255, blue: 188/255
)
```

Configurable by changing this single constant. No user-facing setting for now.

## Files changed

| File | Change |
|------|--------|
| `VoxNotch/Notch/NotchGlowOverlay.swift` | New — glow overlay view with breathing animation |
| `VoxNotch/Notch/NotchContentView.swift` | Add `.overlay { NotchGlowOverlay(...) }` and `AppState.shared` reference |

## Files unchanged

- `NotchShape.swift` — reused as-is for both clipping and stroke path
- `NotchExpandedFallbackView.swift` — content unaffected
- `NotchPanel.swift` — window configuration unaffected
- Expand/collapse animation timings — unaffected

## Tuning parameters

These values are starting points and may need visual tuning:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| Stroke line width | 6pt | Controls glow thickness before blur |
| Blur radius | 8pt | Controls glow softness/spread |
| Breathing min opacity | 0.3 | Dimmest point of pulse |
| Breathing max opacity | 0.6 | Brightest point of pulse |
| Breathing period | 2s | Full cycle duration |
| Fade-in duration | 0.4s | How fast glow appears |
| Fade-out duration | 0.5s | How fast glow disappears |

## Edge cases

- **External monitors (no physical notch)**: The glow is clipped inside the notch shape, so it works identically. The existing `currentOpacity` fade on external monitors will also fade the glow since it's inside the compositing group.
- **Rapid start/stop**: If recording stops during fade-in, the fade-out animation takes over smoothly from the current opacity (SwiftUI handles this natively).
- **Non-recording expanded states**: Glow is not visible during transcribing, processing, error, success, etc. Only during `.recording`.
