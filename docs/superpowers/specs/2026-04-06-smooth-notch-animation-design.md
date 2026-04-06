# Smooth Notch Collapse + Frosted Edge Effect

## Problem

When the VoxNotch notch UI collapses back to the physical notch, there is a visible "snap" or "pop" at the final moment. The root cause: on notch Macs, the overlay's opacity stays at 1.0 throughout the collapse animation. After the spring animation settles, `panel.orderOut(nil)` instantly removes the panel — and any sub-pixel rendering difference between the overlay and the physical notch creates a visible discontinuity.

Additionally, the expanded notch has a hard black edge that feels flat. A frosted glass halo at the outer boundary would give it a more polished, premium feel.

## Solution

Two changes to the notch animation system:

### Change 1: Opacity Fade Before `orderOut`

Instead of removing the panel at full opacity, fade it to transparent first so it dissolves into the physical notch.

**Current collapse sequence (causes snap):**

```
spring collapse (0.45s) → wait 0.5s → orderOut (instant, visible pop)
```

**New collapse sequence:**

```
spring collapse (0.45s) → wait 0.35s → fade opacity to 0 (0.2s easeOut) → orderOut
```

**Implementation:**

- **NotchManager**: Add observable `panelOpacity: CGFloat = 1.0`.
  - `hide()`: After starting the spring collapse, schedule a 0.35s delay, then `withAnimation(.easeOut(duration: 0.2)) { panelOpacity = 0 }`. Schedule `orderOut` after the fade completes (~0.55s total from collapse start).
  - `scheduleAutoHide(after:)`: Same fade-then-orderOut pattern.
  - `showExpanded()`: Reset `panelOpacity = 1.0` immediately (before making the panel visible, no animation needed since the panel may be off-screen).

- **NotchContentView**: Change `.opacity(currentOpacity)` to `.opacity(currentOpacity * notchManager.panelOpacity)`. The fade uses its own `withAnimation` context and does not conflict with the spring animation on `notchState`.

**Timing:** Total collapse duration is ~0.55s, nearly identical to the current 0.5s `orderOut` delay. No perceptible slowdown.

### Change 2: Frosted Glass Edge Halo (Expanded Only)

A subtle frosted glass effect at the outer boundary of the expanded notch, fading to solid black toward the center.

**Visual effect:**
- Outer edge: semi-transparent frosted glass (`.ultraThinMaterial`)
- ~6-8pt inward: gradually transitions to fully opaque black
- Center: solid black, matching the physical notch
- Top region (physical notch area): stays pure black — the halo only appears around the expanded content boundary

**Implementation:**

- Overlay a `.ultraThinMaterial` fill inside the `NotchShape` clip, on top of the `.black` background.
- Mask the material layer with a soft-edged ring:
  - Outer boundary: white (fully visible material)
  - Inner boundary (~6-8pt inset): black with blur (fades material to transparent)
  - This is achieved by compositing a full white `NotchShape` with a blurred, inset black `NotchShape` on top.
- Only render this overlay when `notchState == .expanded`.
- The overlay participates in the existing expand/collapse spring animation via the `.animation(animation, value: notchManager.notchState)` modifier, so it transitions in/out naturally.

## Files Modified

| File | Change |
|------|--------|
| `VoxNotch/Notch/NotchManager.swift` | Add `panelOpacity` property; update `hide()`, `scheduleAutoHide()`, and `showExpanded()` with fade-then-orderOut sequencing |
| `VoxNotch/Notch/NotchContentView.swift` | Apply `panelOpacity` multiplier to opacity; add frosted glass overlay in expanded state |

## Behavior Summary

| State | Opacity | Frosted Edge | Panel Visible |
|-------|---------|-------------|---------------|
| Hidden (idle) | 0 | No | No (`orderOut`) |
| Expanding | 1 (immediate) | Animates in | Yes |
| Expanded | 1 | Yes | Yes |
| Collapsing (spring) | 1 → fades to 0 after 0.35s | Animates out | Yes |
| After collapse | 0 | No | No (`orderOut`) |

## Non-Goals

- Keeping the panel always-visible (boring.notch approach) — rejected to avoid any resource overhead and notch-area interaction concerns.
- Pixel-perfect physical notch matching — fragile across MacBook models and not needed with the fade approach.
- Frosted effect in collapsed state — would alter the physical notch appearance.
