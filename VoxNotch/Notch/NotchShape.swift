//
//  NotchShape.swift
//  VoxNotch
//
//  Notch-shaped bezier path with animatable corner radii.
//  Based on DynamicNotchKit / BoringNotch's NotchShape by Kai Azim.
//

import SwiftUI

struct NotchShape: Shape {

  private var topCornerRadius: CGFloat
  private var bottomCornerRadius: CGFloat

  init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14) {
    self.topCornerRadius = topCornerRadius
    self.bottomCornerRadius = bottomCornerRadius
  }

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { .init(topCornerRadius, bottomCornerRadius) }
    set {
      topCornerRadius = newValue.first
      bottomCornerRadius = newValue.second
    }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()

    // Top-left corner
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + topCornerRadius,
                  y: rect.minY + topCornerRadius),
      control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
    )

    // Left side down
    path.addLine(
      to: CGPoint(x: rect.minX + topCornerRadius,
                  y: rect.maxY - bottomCornerRadius)
    )

    // Bottom-left corner
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius,
                  y: rect.maxY),
      control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
    )

    // Bottom edge
    path.addLine(
      to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius,
                  y: rect.maxY)
    )

    // Bottom-right corner
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - topCornerRadius,
                  y: rect.maxY - bottomCornerRadius),
      control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
    )

    // Right side up
    path.addLine(
      to: CGPoint(x: rect.maxX - topCornerRadius,
                  y: rect.minY + topCornerRadius)
    )

    // Top-right corner
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY),
      control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
    )

    // Close top edge
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

    return path
  }
}
