//
//  FillerWordFilter.swift
//  VoxNotch
//
//  Zero-latency regex filter that strips speech filler words from transcription text.
//

import Foundation

struct FillerWordFilter {
  /// Remove filler words from a transcription string.
  /// Only removes unambiguous fillers (um, uh, er, ah, hmm, hm and elongated variants).
  static func clean(_ text: String) -> String {
    var result = text
    // Remove filler word + optional trailing comma, then collapse surrounding whitespace
    result = result.replacingOccurrences(
      of: #"(?i)\b(um+|uh+|er+|ah+|hmm+|hm+)\b,?"#,
      with: "",
      options: .regularExpression
    )
    // Collapse multiple spaces into one
    result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    // Fix dangling space before comma: " ," → ","
    result = result.replacingOccurrences(of: #"\s+,"#, with: ",", options: .regularExpression)
    result = result.trimmingCharacters(in: .whitespaces)
    // Re-capitalize first letter if removal lowercased the start
    if let first = result.first, first.isLowercase {
      result = first.uppercased() + result.dropFirst()
    }
    return result
  }
}
