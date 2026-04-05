//
//  Transcription.swift
//  VoxNotch
//
//  GRDB Record for storing transcription history
//

import Foundation
import GRDB

// MARK: - Transcription Record

/// A recorded and transcribed voice dictation
struct TranscriptionRecord: Codable, Identifiable, Equatable, Hashable, Sendable,
                            FetchableRecord, MutablePersistableRecord {

  // MARK: - Database Table

  static var databaseTableName: String { "transcription" }

  // MARK: - Properties

  /// Database row ID (auto-generated)
  var id: Int64?

  /// Original transcribed text from speech-to-text
  var rawText: String

  /// Post-processed text after LLM enhancement (nil if no post-processing)
  var processedText: String?

  /// Model used for transcription (e.g., "whisper-base", "funasr-paraformer")
  var model: String

  /// Duration of the audio recording in seconds
  var duration: Double

  /// Confidence score from the transcription model (0.0 to 1.0)
  var confidence: Double?

  /// When the transcription was created
  var timestamp: Date

  /// Path to saved audio file (optional, for replay)
  var audioPath: String?

  /// Additional metadata as JSON string
  var metadata: String?

  // MARK: - Computed Properties

  /// The best text to display (processed if available, otherwise raw)
  var displayText: String {
    processedText ?? rawText
  }

  /// Whether this transcription was post-processed by LLM
  var wasProcessed: Bool {
    processedText != nil
  }

  // MARK: - Initialization

  /// Create a new transcription
  init(
    id: Int64? = nil,
    rawText: String,
    processedText: String? = nil,
    model: String,
    duration: Double,
    confidence: Double? = nil,
    timestamp: Date = Date(),
    audioPath: String? = nil,
    metadata: String? = nil
  ) {
    self.id = id
    self.rawText = rawText
    self.processedText = processedText
    self.model = model
    self.duration = duration
    self.confidence = confidence
    self.timestamp = timestamp
    self.audioPath = audioPath
    self.metadata = metadata
  }

  // MARK: - MutablePersistableRecord

  /// Update id after insert
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }

  // MARK: - Helper Methods

  /// Create a copy with updated processed text
  func withProcessedText(_ text: String) -> TranscriptionRecord {
    var copy = self
    copy.processedText = text
    return copy
  }
}

// MARK: - Column Definitions

extension TranscriptionRecord {

  /// Column expressions for queries
  enum Columns {
    static let id = Column(CodingKeys.id)
    static let rawText = Column(CodingKeys.rawText)
    static let processedText = Column(CodingKeys.processedText)
    static let model = Column(CodingKeys.model)
    static let duration = Column(CodingKeys.duration)
    static let confidence = Column(CodingKeys.confidence)
    static let timestamp = Column(CodingKeys.timestamp)
    static let audioPath = Column(CodingKeys.audioPath)
    static let metadata = Column(CodingKeys.metadata)
  }
}

// MARK: - Query Helpers

extension TranscriptionRecord {

  /// Fetch all transcriptions ordered by timestamp (newest first)
  static func allOrdered() -> QueryInterfaceRequest<TranscriptionRecord> {
    order(Columns.timestamp.desc)
  }

  /// Search transcriptions using full-text search
  ///
  /// Uses FTS5 content table to find matching transcriptions.
  /// Returns results ordered by FTS5 rank (best matches first).
  /// Multi-word queries match all tokens (AND logic).
  static func search(query: String, in db: Database) throws -> [TranscriptionRecord] {
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
      return []
    }

    /// Use FTS5 MATCH with bm25 ranking to find and rank matching rows
    let sql: String = """
      SELECT transcription.*
      FROM transcription
      JOIN transcription_fts ON transcription.id = transcription_fts.rowid
      WHERE transcription_fts MATCH ?
      ORDER BY bm25(transcription_fts) ASC
      """

    /// Escape special FTS5 characters and create AND query for tokens
    /// Each token is quoted and suffixed with * for prefix matching
    let sanitizedQuery: String = query
      .components(separatedBy: .whitespaces)
      .filter { !$0.isEmpty }
      .map { (token: String) -> String in
        /// Escape double quotes in the token
        let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + escaped + "\"*"
      }
      .joined(separator: " AND ")

    return try TranscriptionRecord.fetchAll(db, sql: sql, arguments: [sanitizedQuery])
  }

}

// MARK: - Type Alias

/// Alias for backward compatibility
typealias Transcription = TranscriptionRecord
