//
//  HFModelBrowserSheet.swift
//  VoxNotch
//
//  Browses Hugging Face Hub for MLX ASR models and lets the user add them.
//

import SwiftUI

// MARK: - HF Model Browser Sheet

struct HFModelBrowserSheet: View {

  @Environment(\.dismiss) private var dismiss

  @State private var searchText: String = ""
  @State private var selectedFamily: HFModelFamily = .all
  @State private var models: [HFModelInfo] = []
  @State private var isLoading: Bool = true
  @State private var isOffline: Bool = false
  @State private var addedModelID: String?   // repo ID just added (for feedback)
  @State private var downloadError: String?  // error message from failed download

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {

      // Header
      HStack {
        Text("Browse HuggingFace Models")
          .font(.title2)
          .fontWeight(.semibold)
        Spacer()
        Button("Done") { dismiss() }
          .buttonStyle(.bordered)
      }
      .padding(.horizontal, 24)
      .padding(.top, 20)
      .padding(.bottom, 12)

      // Search bar
      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Search models\u{2026}", text: $searchText)
          .textFieldStyle(.plain)
          .onSubmit { Task { await loadModels() } }
        if !searchText.isEmpty {
          Button {
            searchText = ""
            Task { await loadModels() }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(8)
      .background(.background.secondary)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .padding(.horizontal, 24)
      .padding(.bottom, 10)

      // Family filter chips
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach([HFModelFamily.all, .glm, .qwen3, .voxtral]) { family in
            FamilyChip(family: family, isSelected: selectedFamily == family) {
              selectedFamily = family
            }
          }
        }
        .padding(.horizontal, 24)
      }
      .padding(.bottom, 10)

      // Offline banner
      if isOffline {
        HStack(spacing: 8) {
          Image(systemName: "wifi.slash")
            .font(.caption)
          Text("Can't reach Hugging Face \u{2014} showing cached models only.")
            .font(.caption)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
      }

      Divider()

      // Content
      Group {
        if isLoading {
          VStack {
            Spacer()
            ProgressView("Loading models\u{2026}")
            Spacer()
          }
        } else if filteredModels.isEmpty {
          VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
              .font(.largeTitle)
              .foregroundStyle(.secondary)
            Text(emptyMessage)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadModels() } }
              .buttonStyle(.bordered)
              .controlSize(.small)
            Spacer()
          }
          .frame(maxWidth: .infinity)
          .padding()
        } else {
          List(filteredModels) { model in
            HFModelRow(model: model, justAdded: addedModelID == model.id) {
              addModel(model)
            }
          }
          .listStyle(.plain)
        }
      }
    }
    .frame(width: 560, height: 520)
    .task { await loadModels() }
    .alert("Download Failed", isPresented: Binding(
      get: { downloadError != nil },
      set: { if !$0 { downloadError = nil } }
    )) {
      Button("OK") { downloadError = nil }
    } message: {
      if let downloadError {
        Text(downloadError)
      }
    }
  }

  // MARK: - Filtering

  private var filteredModels: [HFModelInfo] {
    models.filter { model in
      let familyMatch = selectedFamily == .all || model.family == selectedFamily
      return familyMatch
    }
  }

  private var emptyMessage: String {
    if isOffline && models.isEmpty {
      return "No models found. Connect to the internet to browse available models."
    }
    return "No models match your filter."
  }

  // MARK: - Actions

  private func loadModels() async {
    isLoading = true
    isOffline = false

    // Always show local models immediately
    let local = HuggingFaceHubService.shared.discoverLocalModels()

    do {
      let remote = try await HuggingFaceHubService.shared.searchASRModels(query: searchText)
      // Merge: remote first, then local entries not already present
      var seen = Set<String>()
      var merged: [HFModelInfo] = []
      for m in remote + local {
        if seen.insert(m.id).inserted { merged.append(m) }
      }
      models = merged
    } catch {
      isOffline = true
      models = local
    }

    isLoading = false
  }

  private func addModel(_ model: HFModelInfo) {
    let name = model.displayName
    let customModel = CustomModelRegistry.shared.add(repoID: model.id, displayName: name)
    addedModelID = model.id

    Task {
      do {
        try await MLXAudioModelManager.shared.downloadAndLoadCustom(model: customModel)
      } catch {
        downloadError = error.localizedDescription
      }
    }
  }
}

// MARK: - Family Chip

private struct FamilyChip: View {
  let family: HFModelFamily
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(family.rawValue)
        .font(.caption)
        .fontWeight(isSelected ? .semibold : .regular)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? chipBackground : Color.secondary.opacity(0.12))
        .foregroundStyle(isSelected ? chipForeground : .primary)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private var chipBackground: Color {
    switch family {
    case .glm:      .green.opacity(0.2)
    case .qwen3:    .blue.opacity(0.2)
    case .voxtral:  .purple.opacity(0.2)
    case .parakeet: .orange.opacity(0.2)
    default:        .accentColor.opacity(0.15)
    }
  }

  private var chipForeground: Color {
    switch family {
    case .glm:      .green
    case .qwen3:    .blue
    case .voxtral:  .purple
    case .parakeet: .orange
    default:        .accentColor
    }
  }
}

// MARK: - HF Model Row

private struct HFModelRow: View {
  let model: HFModelInfo
  let justAdded: Bool
  let onAdd: () -> Void

  @State private var registry = CustomModelRegistry.shared

  private var isAdded: Bool {
    registry.contains(repoID: model.id)
  }

  var body: some View {
    HStack(spacing: 12) {
      // Family badge color indicator
      RoundedRectangle(cornerRadius: 3)
        .fill(familyColor)
        .frame(width: 4, height: 36)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(model.displayName)
            .fontWeight(.medium)
          familyBadge
          if model.isOnDisk {
            diskBadge
          }
        }
        Text(model.id)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      if model.totalSizeBytes > 0 {
        Text(formattedSize)
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }

      addButton
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var familyBadge: some View {
    if model.family != .unknown {
      Text(model.family.rawValue)
        .font(.caption2)
        .fontWeight(.medium)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(familyColor.opacity(0.15))
        .foregroundStyle(familyColor)
        .clipShape(Capsule())
    }
  }

  private var diskBadge: some View {
    Text("On Disk")
      .font(.caption2)
      .fontWeight(.medium)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(.green.opacity(0.12))
      .foregroundStyle(.green)
      .clipShape(Capsule())
  }

  @ViewBuilder
  private var addButton: some View {
    if isAdded {
      Label(justAdded ? "Added!" : "Added", systemImage: "checkmark")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 76)
    } else {
      Button("Add", action: onAdd)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .frame(width: 76)
    }
  }

  private var familyColor: Color {
    switch model.family {
    case .glm:      .green
    case .qwen3:    .blue
    case .voxtral:  .purple
    case .parakeet: .orange
    default:        .gray
    }
  }

  private var formattedSize: String {
    let mb = Double(model.totalSizeBytes) / 1_000_000
    if mb >= 1000 {
      return String(format: "%.1f GB", mb / 1000)
    }
    return String(format: "%.0f MB", mb)
  }
}

// MARK: - Preview

#Preview {
  HFModelBrowserSheet()
}
