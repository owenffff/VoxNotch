//
//  ScrollingWaveformView.swift
//  VoxNotch
//
//  Canvas-based scrolling audio waveform visualizer (ported from Ditto)
//

import Combine
import SwiftUI

/// Fixed-size ring buffer to avoid O(n) array mutations every frame.
private struct RingBuffer {
  private var storage: [Float]
  private var head: Int = 0
  let capacity: Int

  init(capacity: Int) {
    self.capacity = capacity
    self.storage = [Float](repeating: 0, count: capacity)
  }

  mutating func append(_ value: Float) {
    storage[head] = value
    head = (head + 1) % capacity
  }

  subscript(index: Int) -> Float {
    storage[(head + index) % capacity]
  }
}

struct ScrollingWaveformView: View {
  let level: Float

  private static let bufferCapacity = 120

  @State private var samples = RingBuffer(capacity: ScrollingWaveformView.bufferCapacity)
  @State private var envelope: Float = 0.0
  @State private var prevEnv: Float = 0.0
  @State private var boostExcess: CGFloat = 0.0

  private let barWidth: CGFloat = 2.5
  private let barGap: CGFloat = 1.0

  var body: some View {
    Canvas { ctx, size in
      let stride = barWidth + barGap
      let visible = min(Self.bufferCapacity, Int(size.width / stride))
      let offset = Self.bufferCapacity - visible
      let minH = max(1.5, size.height * 0.04)
      let cy = size.height / 2

      for i in 0..<visible {
        let sample = samples[offset + i]
        let x = CGFloat(i) * stride
        let progress = CGFloat(i) / CGFloat(max(1, visible - 1))

        // Smooth center-peaked opacity: full at center, gently fading to edges.
        let centerness = 1.0 - abs(progress - 0.5) * 2.0
        let t = 0.35 + 0.65 * centerness * centerness * (3 - 2 * centerness)

        let boost: CGFloat = (i == visible - 1) ? (1.0 + boostExcess) : 1.0
        let rawH = CGFloat(pow(sample, 0.5)) * size.height * boost
        let h = max(minH, min(size.height * 0.95, rawH))
        let rect = CGRect(x: x, y: cy - h / 2, width: barWidth, height: h)
        ctx.fill(
          Path(roundedRect: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)),
          with: .color(.primary.opacity(0.8 * t))
        )
      }
    }
    .drawingGroup()
    .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
      if level > envelope {
        envelope = level
      } else {
        envelope *= 0.93
      }

      let delta = envelope - prevEnv
      if delta > 0.05 {
        boostExcess = min(0.35, CGFloat(delta) * 2.0)
      }
      prevEnv = envelope

      samples.append(envelope)

      boostExcess = max(0, boostExcess * 0.8)
    }
  }
}
