//
//  ToneTemplate.swift
//  VoxNotch
//
//  Customizable tone presets for LLM post-processing
//

import Foundation
import os.log

// MARK: - ToneTemplate

/// A customizable tone preset for LLM post-processing
struct ToneTemplate: Codable, Identifiable, Hashable, Sendable {
  /// Stable identifier: built-ins use PromptTemplate.rawValue; custom use UUID string
  let id: String
  var displayName: String
  var description: String
  var prompt: String
  /// True for the 7 built-in presets seeded from PromptTemplate
  let isBuiltIn: Bool
  /// Original prompt for built-ins only — enables "Revert to Default"
  let originalPrompt: String?

  init(id: String, displayName: String, description: String = "", prompt: String, isBuiltIn: Bool, originalPrompt: String?) {
    self.id = id
    self.displayName = displayName
    self.description = description
    self.prompt = prompt
    self.isBuiltIn = isBuiltIn
    self.originalPrompt = originalPrompt
  }

  enum CodingKeys: String, CodingKey {
    case id, displayName, description, prompt, isBuiltIn, originalPrompt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    prompt = try container.decode(String.self, forKey: .prompt)
    isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
    originalPrompt = try container.decodeIfPresent(String.self, forKey: .originalPrompt)
  }

  func hash(into hasher: inout Hasher) { hasher.combine(id) }
  static func == (lhs: ToneTemplate, rhs: ToneTemplate) -> Bool { lhs.id == rhs.id }
}

// MARK: - ToneRegistry

/// Observable registry of all tone presets (built-in + custom), persisted in UserDefaults
///
/// Thread Safety: `lock` (NSLock) protects all reads/writes to the `tones` array.
@Observable
final class ToneRegistry: @unchecked Sendable {

  static let shared = ToneRegistry()

  private let logger = Logger(subsystem: "com.voxnotch", category: "ToneRegistry")
  private let defaultsKey = "toneTemplates"
  private let lock = NSLock()

  private(set) var tones: [ToneTemplate] = []

  private init() {
    loadOrSeed()
  }

  // MARK: - Public Methods

  /// Add a new custom tone to the registry
  func add(_ tone: ToneTemplate) {
    lock.withLock { tones.append(tone) }
    save()
  }

  /// Update an existing tone
  func update(_ tone: ToneTemplate) {
    lock.withLock {
      guard let index = tones.firstIndex(where: { $0.id == tone.id }) else { return }
      tones[index] = tone
    }
    save()
  }

  /// Remove a tone by ID (only custom tones should be removed)
  func remove(id: String) {
    lock.withLock { tones.removeAll { $0.id == id } }
    save()
  }

  /// Look up a tone by ID
  func tone(forID id: String) -> ToneTemplate? {
    lock.withLock { tones.first { $0.id == id } }
  }

  /// Revert a built-in tone's prompt to its original value
  func revert(id: String) {
    lock.withLock {
      guard let index = tones.firstIndex(where: { $0.id == id }),
            tones[index].isBuiltIn,
            let original = tones[index].originalPrompt
      else { return }
      tones[index].prompt = original
    }
    save()
  }

  // MARK: - Persistence

  private func loadOrSeed() {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: defaultsKey) {
      do {
        tones = try JSONDecoder().decode([ToneTemplate].self, from: data)
      } catch {
        logger.error("Failed to decode tone templates from UserDefaults: \(error)")
      }
    }

    if !tones.isEmpty {
      ensureNoneTone()
      // Backfill descriptions for built-in tones (added in progressive disclosure update)
      var backfilled = false
      for i in tones.indices where tones[i].isBuiltIn && tones[i].description.isEmpty {
        if tones[i].id == "none" {
          tones[i] = ToneTemplate(
            id: tones[i].id,
            displayName: tones[i].displayName,
            description: "No AI processing — transcribed text is used as-is",
            prompt: tones[i].prompt,
            isBuiltIn: true,
            originalPrompt: tones[i].originalPrompt
          )
          backfilled = true
        } else if let template = PromptTemplate(rawValue: tones[i].id) {
          tones[i] = ToneTemplate(
            id: tones[i].id,
            displayName: tones[i].displayName,
            description: template.toneDescription,
            prompt: tones[i].prompt,
            isBuiltIn: true,
            originalPrompt: tones[i].originalPrompt
          )
          backfilled = true
        }
      }
      if backfilled { save() }
      // Migrate old "No Processing" display name to "Original"
      if let idx = tones.firstIndex(where: { $0.id == "none" && $0.displayName == "No Processing" }) {
        tones[idx] = ToneTemplate(
          id: "none",
          displayName: "Original",
          prompt: "",
          isBuiltIn: true,
          originalPrompt: ""
        )
        save()
      }
      // Remove deprecated built-in tones
      let removedBuiltInIDs: Set<String> = ["cleanup", "punctuation", "filler-removal", "casual", "translation"]
      let hadRemoved = tones.contains { removedBuiltInIDs.contains($0.id) && $0.isBuiltIn }
      if hadRemoved {
        tones.removeAll { removedBuiltInIDs.contains($0.id) && $0.isBuiltIn }
        // If active tone was one of the removed ones, reset to "none"
        if removedBuiltInIDs.contains(SettingsManager.shared.activeToneID) {
          SettingsManager.shared.activeToneID = "none"
        }
        // Strip removed tones from pinned list
        SettingsManager.shared.pinnedToneIDs.removeAll { removedBuiltInIDs.contains($0) }
        save()
      }
      // Seed any new built-in tones that don't exist yet (for existing users)
      let existingIDs = Set(tones.map(\.id))
      let newBuiltIns = PromptTemplate.allCases
        .filter { $0 != .custom && !existingIDs.contains($0.rawValue) }
        .map { template in
          ToneTemplate(
            id: template.rawValue,
            displayName: template.displayName,
            description: template.toneDescription,
            prompt: template.prompt,
            isBuiltIn: true,
            originalPrompt: template.prompt
          )
        }
      if !newBuiltIns.isEmpty {
        tones.append(contentsOf: newBuiltIns)
        save()
      }
      // Refresh built-in prompts when the upstream template has changed and
      // the user hasn't customized the prompt (prompt still matches old originalPrompt).
      var refreshed = false
      for i in tones.indices where tones[i].isBuiltIn && tones[i].id != "none" {
        guard let template = PromptTemplate(rawValue: tones[i].id) else { continue }
        let currentPrompt = template.prompt
        // Skip if already up-to-date
        guard tones[i].originalPrompt != currentPrompt else { continue }
        // Only overwrite if user hasn't customized (prompt == old originalPrompt)
        if tones[i].prompt == tones[i].originalPrompt {
          tones[i] = ToneTemplate(
            id: tones[i].id,
            displayName: tones[i].displayName,
            description: template.toneDescription,
            prompt: currentPrompt,
            isBuiltIn: true,
            originalPrompt: currentPrompt
          )
          refreshed = true
        } else {
          // User customized the prompt — only update originalPrompt so "Revert" targets the new default
          tones[i] = ToneTemplate(
            id: tones[i].id,
            displayName: tones[i].displayName,
            description: tones[i].description,
            prompt: tones[i].prompt,
            isBuiltIn: true,
            originalPrompt: currentPrompt
          )
          refreshed = true
        }
      }
      if refreshed { save() }
    } else {
      seedBuiltIns()
      migrateCustomTone()
      save()
    }
  }

  /// Seed built-in tones from PromptTemplate cases (excluding the old "custom" case)
  private func seedBuiltIns() {
    let noneTone = ToneTemplate(
      id: "none",
      displayName: "Original",
      description: "No AI processing — transcribed text is used as-is",
      prompt: "",
      isBuiltIn: true,
      originalPrompt: ""
    )
    let builtIns = PromptTemplate.allCases
      .filter { $0 != .custom }
      .map { template in
        ToneTemplate(
          id: template.rawValue,
          displayName: template.displayName,
          description: template.toneDescription,
          prompt: template.prompt,
          isBuiltIn: true,
          originalPrompt: template.prompt
        )
      }
    tones = [noneTone] + builtIns
  }

  /// Ensure the "Original" tone exists (migration for existing users)
  private func ensureNoneTone() {
    guard !tones.contains(where: { $0.id == "none" }) else { return }
    let noneTone = ToneTemplate(
      id: "none",
      displayName: "Original",
      prompt: "",
      isBuiltIn: true,
      originalPrompt: ""
    )
    tones.insert(noneTone, at: 0)
    save()
  }

  /// Migrate a non-empty custom prompt from old settings into a "My Custom Tone" entry
  private func migrateCustomTone() {
    let defaults = UserDefaults.standard
    guard defaults.string(forKey: "promptTemplate") == "custom",
          let oldPrompt = defaults.string(forKey: "customPrompt"),
          !oldPrompt.isEmpty
    else { return }

    let customID = "migrated-custom"
    guard tones.first(where: { $0.id == customID }) == nil else { return }

    let customTone = ToneTemplate(
      id: customID,
      displayName: "My Custom Tone",
      prompt: oldPrompt,
      isBuiltIn: false,
      originalPrompt: nil
    )
    tones.append(customTone)

    // Update SettingsManager (it is already initialized since it initializes before first ToneRegistry access)
    SettingsManager.shared.activeToneID = customID
  }

  /// Persist current tones to UserDefaults.
  /// Called outside the mutation lock — safe because we re-acquire the lock
  /// here to snapshot. Encoding + I/O must stay outside the lock to avoid
  /// blocking readers and to prevent NSLock deadlock (non-reentrant).
  private func save() {
    let snapshot = lock.withLock { tones }
    do {
      let data = try JSONEncoder().encode(snapshot)
      UserDefaults.standard.set(data, forKey: defaultsKey)
    } catch {
      logger.error("Failed to encode tone templates: \(error)")
    }
  }
}
