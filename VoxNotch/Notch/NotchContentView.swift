//
//  NotchContentView.swift
//  VoxNotch
//
//  Root SwiftUI view hosted inside the persistent NotchPanel.
//  Integrates with the physical MacBook notch: the hidden state
//  matches the physical notch dimensions (black on black = invisible),
//  and the expanded state grows downward from the physical notch.
//

import SwiftUI

struct NotchContentView: View {

  private let notchManager = NotchManager.shared

  // MARK: - Expanded Size

  /// Width of the expanded notch panel.
  private let expandedWidth: CGFloat = 320

  /// Height of the visible content area below the physical notch.
  private let expandedContentHeight: CGFloat = 34

  // MARK: - Derived Sizing

  /// Current width of the notch shape.
  private var currentWidth: CGFloat {
    if notchManager.notchState == .expanded { return expandedWidth }
    return notchManager.hasPhysicalNotch
      ? notchManager.physicalNotchSize.width
      : 40
  }

  /// Current total height including the physical notch region at top.
  /// Hidden: just the physical notch height (invisible black region).
  /// Expanded: physical notch height + content below it.
  private var currentHeight: CGFloat {
    if notchManager.notchState == .expanded {
      return notchManager.physicalNotchSize.height + expandedContentHeight
    }
    return notchManager.hasPhysicalNotch
      ? notchManager.physicalNotchSize.height
      : 4
  }

  /// On external monitors the hidden state fades to transparent so the
  /// shrinking shape dissolves instead of lingering as a visible black pill.
  private var currentOpacity: CGFloat {
    if notchManager.hasPhysicalNotch { return 1 }
    return notchManager.notchState == .expanded ? 1 : 0
  }

  // MARK: - Corner Radii

  private var topCornerRadius: CGFloat {
    notchManager.notchState == .expanded ? 12 : 6
  }

  private var bottomCornerRadius: CGFloat {
    notchManager.notchState == .expanded ? 16 : 14
  }

  // MARK: - Animation

  private var animation: Animation {
    switch notchManager.notchState {
    case .expanded:
      .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    case .hidden:
      .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    }
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      // Top region: occupies the physical notch height (black, invisible).
      Color.clear
        .frame(height: notchManager.physicalNotchSize.height)

      // Content region: only visible when expanded.
      if notchManager.notchState == .expanded {
        NotchExpandedFallbackView()
          .frame(height: expandedContentHeight)
          .transition(
            .opacity.combined(with: .scale(scale: 0.8, anchor: .top))
          )
      }
    }
    .frame(width: currentWidth, height: currentHeight)
    .background(.black)
    .clipShape(
      NotchShape(
        topCornerRadius: topCornerRadius,
        bottomCornerRadius: bottomCornerRadius
      )
    )
    .mask {
      if notchManager.notchState == .expanded {
        VStack(spacing: 0) {
          // Top: fully opaque (blends with physical notch).
          Color.white
            .frame(height: notchManager.physicalNotchSize.height)
          // Below: translucent edges, opaque center.
          ZStack {
            Color.white.opacity(0.75)
            Color.white
              .padding(8)
              .blur(radius: 10)
          }
        }
      } else {
        Color.white
      }
    }
    .overlay {
      // Glassmorphism border glow on left, right, and bottom edges only.
      if notchManager.notchState == .expanded {
        NotchShape(
          topCornerRadius: topCornerRadius,
          bottomCornerRadius: bottomCornerRadius
        )
        .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
        .blur(radius: 1)
        .clipShape(
          NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
          )
        )
        .mask {
          VStack(spacing: 0) {
            // Hide glow in physical notch area.
            Color.clear
              .frame(height: notchManager.physicalNotchSize.height)
            // Show glow on sides and bottom.
            Color.white
          }
        }
        .transition(.opacity)
      }
    }
    .shadow(
      color: notchManager.notchState == .expanded
        ? .black.opacity(0.5) : .clear,
      radius: 6
    )
    .compositingGroup()
    .opacity(currentOpacity * notchManager.panelOpacity)
    .allowsHitTesting(notchManager.notchState == .expanded)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .animation(animation, value: notchManager.notchState)
  }
}
