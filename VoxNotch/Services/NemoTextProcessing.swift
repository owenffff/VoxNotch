import Foundation
import CNemoTextProcessing

/// Swift wrapper for NeMo Text Processing (Inverse Text Normalization).
///
/// Converts spoken-form ASR output to written form:
/// - "two hundred thirty two" → "232"
/// - "five dollars and fifty cents" → "$5.50"
/// - "january fifth twenty twenty five" → "January 5, 2025"
/// - "period" → "."
public enum NemoTextProcessing {

    /// Normalize a full sentence, replacing spoken-form spans with written form.
    ///
    /// Scans for normalizable spans within a larger sentence using a sliding window.
    /// Uses a default max span of 16 tokens.
    ///
    /// - Parameter input: Sentence containing spoken-form spans
    /// - Returns: Sentence with spoken-form spans replaced
    public static func normalizeSentence(_ input: String) -> String {
        guard let cString = input.cString(using: .utf8) else {
            return input
        }

        guard let resultPtr = nemo_normalize_sentence(cString) else {
            return input
        }

        defer { nemo_free_string(resultPtr) }

        return String(cString: resultPtr)
    }
}
