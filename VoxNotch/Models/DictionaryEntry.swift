//
//  DictionaryEntry.swift
//  VoxNotch
//
//  Custom dictionary for spoken-form → written-form replacements in transcription
//

import Foundation

// MARK: - DictionaryEntry

/// A custom spoken→written replacement rule for transcription post-processing
struct DictionaryEntry: Codable, Identifiable, Hashable, Sendable {
  /// Stable identifier (UUID string)
  let id: String
  /// How the user says it (e.g., "gee pee tee") — matched case-insensitively
  var spokenForm: String
  /// What appears in the output text (e.g., "GPT")
  var writtenForm: String

  init(spokenForm: String, writtenForm: String) {
    self.id = UUID().uuidString
    self.spokenForm = spokenForm
    self.writtenForm = writtenForm
  }
}

// MARK: - DictionaryRegistry

/// Observable registry of custom dictionary entries, persisted in UserDefaults
@Observable
final class DictionaryRegistry: @unchecked Sendable {

  static let shared = DictionaryRegistry()

  private let defaultsKey = "customDictionaryEntries"

  private(set) var entries: [DictionaryEntry] = []

  private init() {
    load()
    syncToNemo()
  }

  // MARK: - Public Methods

  /// Add a new dictionary entry
  func add(_ entry: DictionaryEntry) {
    entries.append(entry)
    save()
    if SettingsManager.shared.customDictionaryEnabled {
      NemoTextProcessing.addRule(spoken: entry.spokenForm, written: entry.writtenForm)
    }
  }

  /// Update an existing entry
  func update(_ entry: DictionaryEntry) {
    guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
    let old = entries[index]
    if SettingsManager.shared.customDictionaryEnabled {
      NemoTextProcessing.removeRule(spoken: old.spokenForm)
    }
    entries[index] = entry
    save()
    if SettingsManager.shared.customDictionaryEnabled {
      NemoTextProcessing.addRule(spoken: entry.spokenForm, written: entry.writtenForm)
    }
  }

  /// Remove an entry by ID
  func remove(id: String) {
    guard let entry = entries.first(where: { $0.id == id }) else { return }
    if SettingsManager.shared.customDictionaryEnabled {
      NemoTextProcessing.removeRule(spoken: entry.spokenForm)
    }
    entries.removeAll { $0.id == id }
    save()
  }

  /// Check if a spoken form already exists (case-insensitive)
  func containsSpokenForm(_ spoken: String) -> Bool {
    entries.contains { $0.spokenForm.lowercased() == spoken.lowercased() }
  }

  /// Reload all rules into NemoTextProcessing.
  /// Called on init and when the master toggle changes.
  func syncToNemo() {
    NemoTextProcessing.clearRules()
    guard SettingsManager.shared.customDictionaryEnabled else { return }
    for entry in entries {
      NemoTextProcessing.addRule(spoken: entry.spokenForm, written: entry.writtenForm)
    }
  }

  // MARK: - Persistence

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: defaultsKey),
          let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
    else { return }
    entries = decoded
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }
}
