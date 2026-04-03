//
//  ScrollingWaveformView.swift
//  VoxNotch
//
//  Canvas-based scrolling audio waveform visualizer (ported from Ditto)
//

import Combine
import SwiftUI

struct ScrollingWaveformView: View {
  let level: Float

  @State private var samples: [Float] = [Float](repeating: 0, count: 80)
  @State private var envelope: Float = 0.0
  @State private var prevEnv: Float = 0.0
  @State private var boostExcess: CGFloat = 0.0

  private let barWidth: CGFloat = 3.5
  private let barGap: CGFloat = 1.5

  var body: some View {
    Canvas { ctx, size in
      let stride = barWidth + barGap
      let visible = Int(size.width / stride)
      let slice = samples.suffix(visible)
      let minH = max(1.5, size.height * 0.04)
      let cy = size.height / 2
      let fadeRatio = 0.2
      let totalCount = slice.count

      for (i, sample) in slice.enumerated() {
        let x = CGFloat(i) * stride
        let progress = CGFloat(i) / CGFloat(max(1, visible - 1))

        let raw: CGFloat
        if progress < fadeRatio {
          raw = progress / fadeRatio
        } else if progress > 1 - fadeRatio {
          raw = (1 - progress) / fadeRatio
        } else {
          raw = 1
        }
        let t = raw * raw * (3 - 2 * raw)

        let boost = (i == totalCount - 1) ? (1.0 + boostExcess) : 1.0
        let rawH = CGFloat(pow(sample, 0.5)) * size.height * boost
        let h = max(minH, min(size.height * 0.95, rawH))
        let rect = CGRect(x: x, y: cy - h / 2, width: barWidth, height: h)
        ctx.fill(
          Path(roundedRect: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)),
          with: .color(.primary.opacity(0.75 * t))
        )
      }
    }
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
      if samples.count > 80 {
        samples.removeFirst(samples.count - 80)
      }

      boostExcess = max(0, boostExcess * 0.8)
    }
  }
}
