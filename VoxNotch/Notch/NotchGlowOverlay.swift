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

  private var glowOpacity: CGFloat {
    guard isActive else { return 0 }
    return breathing ? breatheMax : breatheMin
  }

  // MARK: - Body

  var body: some View {
    NotchShape(
      topCornerRadius: topCornerRadius,
      bottomCornerRadius: bottomCornerRadius
    )
    .stroke(Self.glowColor, lineWidth: strokeWidth)
    .blur(radius: blurRadius)
    .opacity(glowOpacity)
    .animation(
      breathing
        ? .easeInOut(duration: breathePeriod / 2).repeatForever(autoreverses: true)
        : .default,
      value: breathing
    )
    .onAppear {
      if isActive {
        withAnimation(.easeIn(duration: 0.4)) { breathing = true }
      }
    }
    .onChange(of: isActive) { _, active in
      if active {
        withAnimation(.easeIn(duration: 0.4)) { breathing = true }
      } else {
        withAnimation(.easeOut(duration: 0.5)) { breathing = false }
      }
    }
    .allowsHitTesting(false)
  }
}
