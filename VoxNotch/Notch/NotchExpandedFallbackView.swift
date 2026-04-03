//
//  NotchExpandedFallbackView.swift
//  VoxNotch
//
//  Expanded-mode fallback for non-notch Macs. Renders the same
//  horizontal leading + trailing layout inside the floating panel.
//

import SwiftUI

struct NotchExpandedFallbackView: View {

  var body: some View {
    HStack(spacing: 12) {
      CompactLeadingView()
        .frame(maxWidth: .infinity, alignment: .leading)

      CompactTrailingView()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
    .frame(minWidth: 200)
  }
}
