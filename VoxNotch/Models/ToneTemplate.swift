//
//  ToneTemplate.swift
//  VoxNotch
//
//  Customizable tone presets for LLM post-processing
//

import Foundation

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
@Observable
final class ToneRegistry: @unchecked Sendable {

  static let shared = ToneRegistry()

  private let defaultsKey = "toneTemplates"

  private(set) var tones: [ToneTemplate] = []

  private init() {
    loadOrSeed()
  }

  // MARK: - Public Methods

  /// Add a new custom tone to the registry
  func add(_ tone: ToneTemplate) {
    tones.append(tone)
    save()
  }

  /// Update an existing tone
  func update(_ tone: ToneTemplate) {
    guard let index = tones.firstIndex(where: { $0.id == tone.id }) else { return }
    tones[index] = tone
    save()
  }

  /// Remove a tone by ID (only custom tones should be removed)
  func remove(id: String) {
    tones.removeAll { $0.id == id }
    save()
  }

  /// Look up a tone by ID
  func tone(forID id: String) -> ToneTemplate? {
    tones.first { $0.id == id }
  }

  /// Revert a built-in tone's prompt to its original value
  func revert(id: String) {
    guard let index = tones.firstIndex(where: { $0.id == id }),
          tones[index].isBuiltIn,
          let original = tones[index].originalPrompt
    else { return }
    tones[index].prompt = original
    save()
  }

  // MARK: - Persistence

  private func loadOrSeed() {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: defaultsKey),
       let decoded = try? JSONDecoder().decode([ToneTemplate].self, from: data)
    {
      tones = decoded
      ensureNoneTone()
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
      // Remove deprecated built-in tones (cleanup, punctuation, filler-removal)
      let removedBuiltInIDs: Set<String> = ["cleanup", "punctuation", "filler-removal"]
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

  private func save() {
    guard let data = try? JSONEncoder().encode(tones) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }
}
