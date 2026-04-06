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
    .onAppear {
      if isActive { breathing = true }
    }
    .onChange(of: isActive) { _, active in
      breathing = active
    }
    .allowsHitTesting(false)
  }
}
