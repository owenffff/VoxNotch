//
//  SettingsComponents.swift
//  VoxNotch
//
//  Shared view components used across multiple settings tabs.
//  Extracted from SettingsView.swift for reuse.
//

import SwiftUI

// MARK: - Formatting Helpers

func formatBytes(_ bytes: Int64) -> String {
  if bytes == 0 { return "None" }
  let formatter = ByteCountFormatter()
  formatter.countStyle = .file
  return formatter.string(fromByteCount: bytes)
}

func formatSpeed(_ bytesPerSecond: Double) -> String {
  if bytesPerSecond == 0 { return "0 KB/s" }
  let formatter = ByteCountFormatter()
  formatter.countStyle = .file
  return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
}

// MARK: - Info Label

/// A label with a trailing ⓘ icon that carries a hover tooltip.
/// Use in place of plain string labels on settings controls
/// to make help text visually discoverable.
struct InfoLabel: View {
  let title: String
  let tooltip: String

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
      Image(systemName: "info.circle")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .help(tooltip)
    }
  }
}

// MARK: - Custom Model Card

struct CustomModelCard: View {
  let model: CustomSpeechModel
  let isSelected: Bool
  let downloadState: UIDownloadState
  let onSelect: () -> Void
  let onDownload: () -> Void
  let onDelete: () -> Void

  @State private var isHovered = false
  @State private var showDeleteConfirmation = false

  var body: some View {
    HStack(spacing: 12) {
      // Selection indicator
      Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

      VStack(alignment: .leading, spacing: 2) {
        Text(model.displayName)
          .fontWeight(isSelected ? .semibold : .medium)
        Text(model.hfRepoID)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      actionView

      // Delete button
      Button(role: .destructive) {
        showDeleteConfirmation = true
      } label: {
        Image(systemName: "trash")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .confirmationDialog("Remove \(model.displayName)?", isPresented: $showDeleteConfirmation) {
        Button("Remove", role: .destructive) { onDelete() }
      } message: {
        Text("This will remove the model from your list and delete downloaded files.")
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isSelected ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(
          isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
          lineWidth: isSelected ? 2 : 1
        )
    )
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .onTapGesture {
      if downloadState == .ready { onSelect() }
    }
    .onHover { hovering in isHovered = hovering }
  }

  @ViewBuilder
  private var actionView: some View {
    switch downloadState {
    case .notDownloaded:
      Button("Download") { onDownload() }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)

    case .downloading(let progress, let downloadedBytes, let totalBytes, let speedBytesPerSecond):
      VStack(alignment: .trailing, spacing: 2) {
        HStack(spacing: 6) {
          if progress > 0 {
            ProgressView(value: progress)
              .frame(width: 60)
            Text("\(Int(progress * 100))%")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          } else {
            ProgressView().scaleEffect(0.7)
            Text("Downloading...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if totalBytes > 0 {
          Text("\(formatBytes(downloadedBytes)) / \(formatBytes(totalBytes)) \u{2022} \(formatSpeed(speedBytesPerSecond))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
      }

    case .ready:
      if isSelected {
        Label("Now Using", systemImage: "checkmark")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.green)
      } else {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Ready")
            .font(.caption)
            .foregroundStyle(.green)
        }
      }

    case .failed:
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .font(.caption)
        Button("Retry") { onDownload() }
          .controlSize(.small)
      }
    }
  }
}

// MARK: - Model Card

/// Full-width card for a built-in SpeechModel with rich metadata display
struct ModelCard: View {
  let model: SpeechModel
  let isSelected: Bool
  let downloadState: UIDownloadState
  let onSelect: () -> Void
  let onDownload: () -> Void

  @State private var isHovered = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      // Top row: icon + name + badge
      HStack(alignment: .center, spacing: 10) {
        // Provider icon
        ZStack {
          RoundedRectangle(cornerRadius: 7)
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 34, height: 34)
          Image(systemName: model.providerIconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        }

        // Model name
        Text(model.displayName)
          .font(.system(.body, design: .default, weight: .semibold))

        // Tagline badge
        ModelBadge(text: model.tagline, model: model)

        Spacer()
      }

      // Description
      Text(model.modelDescription)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      // Feature row
      HStack(spacing: 8) {
        // Accuracy dots
        HStack(spacing: 3) {
          RatingDots(rating: model.accuracyRating, icon: "target")
          Text("Accuracy")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text("\u{00B7}").foregroundStyle(.tertiary).font(.caption)

        // Speed dots
        HStack(spacing: 3) {
          RatingDots(rating: model.speedRating, icon: "bolt.fill")
          Text("Speed")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text("\u{00B7}").foregroundStyle(.tertiary).font(.caption)

        // Size pill
        FeaturePill(icon: "internaldrive", text: formatSize(model.estimatedSizeMB))

        // Language pill
        FeaturePill(
          icon: "globe",
          text: model.languageDescription
        )

        Spacer()

        // Action area
        actionView
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isSelected ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(
          isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
          lineWidth: isSelected ? 2 : 1
        )
    )
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .onTapGesture {
      if downloadState == .ready { onSelect() }
    }
    .onHover { hovering in isHovered = hovering }
  }

  @ViewBuilder
  private var actionView: some View {
    switch downloadState {
    case .notDownloaded:
      Button("Download") { onDownload() }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)

    case .downloading(let progress, let downloadedBytes, let totalBytes, let speedBytesPerSecond):
      VStack(alignment: .trailing, spacing: 2) {
        HStack(spacing: 6) {
          if progress > 0 {
            ProgressView(value: progress)
              .frame(width: 60)
            Text("\(Int(progress * 100))%")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          } else {
            ProgressView().scaleEffect(0.7)
            Text("Downloading\u{2026}")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if totalBytes > 0 {
          Text("\(formatBytes(downloadedBytes)) / \(formatBytes(totalBytes)) \u{2022} \(formatSpeed(speedBytesPerSecond))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
      }

    case .ready:
      if isSelected {
        Label("Now Using", systemImage: "checkmark")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.green)
      }

    case .failed:
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .font(.caption)
        Button("Retry") { onDownload() }
          .controlSize(.small)
      }
    }
  }

  private func formatSize(_ mb: Int) -> String {
    mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000.0) : "\(mb) MB"
  }
}

// MARK: - Rating Dots

struct RatingDots: View {
  let rating: Int
  let icon: String
  private let total = 5

  var body: some View {
    HStack(spacing: 2) {
      ForEach(0..<total, id: \.self) { i in
        Circle()
          .fill(i < rating ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
          .frame(width: 6, height: 6)
      }
    }
  }
}

// MARK: - Feature Pill

struct FeaturePill: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: icon)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
      Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Model Badge

struct ModelBadge: View {
  let text: String
  let model: SpeechModel

  private var badgeColor: Color {
    switch model {
    case .glmAsrNano: .orange
    case .qwen3Asr: .purple
    default: .accentColor
    }
  }

  var body: some View {
    Text(text)
      .font(.caption2)
      .fontWeight(.semibold)
      .foregroundStyle(badgeColor)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(
        Capsule().fill(badgeColor.opacity(0.12))
      )
  }
}

// MARK: - Tone Preset Card

struct TonePresetCard: View {

  let tone: ToneTemplate
  let isActive: Bool
  let onActivate: () -> Void

  var body: some View {
    Button(action: onActivate) {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(tone.displayName)
            .font(.headline)
            .foregroundStyle(isActive ? .white : .primary)

          Spacer()

          if isActive {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.white)
          }
        }

        if !tone.description.isEmpty {
          Text(tone.description)
            .font(.caption)
            .foregroundStyle(isActive ? .white.opacity(0.85) : .secondary)
            .lineLimit(2)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(isActive ? Color.clear : Color.secondary.opacity(0.15), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Quick-Switch Ordered List

/// Reusable ordered drag list for pinned quick-switch items (models or tones).
/// Shows up to `maxItems` pinned entries with drag-to-reorder and remove buttons,
/// plus a popover "+ Add" picker when there's room for more.
struct QuickSwitchOrderedList: View {

  @Binding var pinnedIDs: [String]
  let availableItems: [(id: String, name: String)]
  let maxItems: Int
  var fixedFirstItem: (id: String, name: String)? = nil

  @State private var showAddPopover = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if fixedFirstItem != nil || !pinnedIDs.isEmpty {
        List {
          if let fixed = fixedFirstItem {
            HStack(spacing: 10) {
              // Number badge
              Text("1")
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.secondary.opacity(0.12))
                .clipShape(Circle())

              Text(fixed.name)
                .font(.body)

              Spacer()

              Image(systemName: "lock.fill")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            }
            .padding(.vertical, 2)
            .moveDisabled(true)
          }

          ForEach(Array(zip(pinnedIDs.indices, pinnedIDs)), id: \.1) { index, id in
            HStack(spacing: 10) {
              // Number badge
              Text("\(index + (fixedFirstItem != nil ? 2 : 1))")
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.secondary.opacity(0.12))
                .clipShape(Circle())

              Text(name(for: id))
                .font(.body)

              Spacer()

              Button {
                pinnedIDs.removeAll { $0 == id }
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
                  .imageScale(.medium)
              }
              .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
          }
          .onMove { from, to in pinnedIDs.move(fromOffsets: from, toOffset: to) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: CGFloat(pinnedIDs.count + (fixedFirstItem != nil ? 1 : 0)) * 40)
      }

      if pinnedIDs.count < maxItems {
        Button {
          showAddPopover = true
        } label: {
          Label("Add", systemImage: "plus.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, 2)
        .popover(isPresented: $showAddPopover, arrowEdge: .bottom) {
          addPicker
        }
      }
    }
  }

  private var addPicker: some View {
    let unpinned = availableItems.filter { item in
      !pinnedIDs.contains(item.id) && item.id != fixedFirstItem?.id
    }
    return VStack(alignment: .leading, spacing: 0) {
      if unpinned.isEmpty {
        Text("All items are pinned")
          .foregroundStyle(.secondary)
          .font(.callout)
          .padding()
      } else {
        ForEach(unpinned, id: \.id) { item in
          Button {
            if pinnedIDs.count < maxItems {
              pinnedIDs.append(item.id)
            }
            showAddPopover = false
          } label: {
            Text(item.name)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          if item.id != unpinned.last?.id {
            Divider()
          }
        }
      }
    }
    .frame(minWidth: 200)
    .padding(.vertical, 4)
  }

  private func name(for id: String) -> String {
    availableItems.first(where: { $0.id == id })?.name ?? id
  }
}

// MARK: - Tone Row View

struct ToneRowView: View {

  let tone: ToneTemplate
  let isActive: Bool
  let isSelected: Bool
  let onSelect: () -> Void
  let onActivate: () -> Void
  let onDelete: () -> Void

  @State private var showDeleteConfirm = false

  var body: some View {
    HStack(spacing: 8) {
      // Active indicator
      Button(action: onActivate) {
        Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(isActive ? Color.accentColor : .secondary)
      }
      .buttonStyle(.plain)
      .help(isActive ? "Active tone" : "Set as active tone")

      // Name
      Text(tone.displayName)
        .font(.body)
        .fontWeight(isSelected ? .semibold : .regular)

      Spacer()

      // Badge
      if tone.isBuiltIn && tone.id != "none" {
        Text("built-in")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.secondary.opacity(0.1))
          .clipShape(Capsule())
      }

      // Delete (custom only)
      if !tone.isBuiltIn {
        Button(role: .destructive) {
          showDeleteConfirm = true
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 11))
            .foregroundStyle(.red.opacity(0.7))
        }
        .buttonStyle(.plain)
        .confirmationDialog("Delete \"\(tone.displayName)\"?", isPresented: $showDeleteConfirm) {
          Button("Delete", role: .destructive) { onDelete() }
        }
      }
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .padding(.horizontal, -4)
    )
    .onTapGesture { onSelect() }
  }
}

// MARK: - New Tone Sheet

struct NewToneSheet: View {

  let registry: ToneRegistry
  let onCreate: (String, String) -> Void

  @State private var name = ""
  @State private var prompt = ""
  @State private var templateBase = "blank"
  @Environment(\.dismiss) private var dismiss

  private var templateOptions: [(id: String, name: String)] {
    var options: [(id: String, name: String)] = [("blank", "Blank")]
    for tone in registry.tones where tone.isBuiltIn && tone.id != "none" {
      options.append((tone.id, "Based on \(tone.displayName)"))
    }
    return options
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("New Tone")
        .font(.title2)
        .fontWeight(.semibold)

      HStack(spacing: 12) {
        TextField("Name", text: $name)
          .textFieldStyle(.roundedBorder)

        Picker("Start from", selection: $templateBase) {
          ForEach(templateOptions, id: \.id) { option in
            Text(option.name).tag(option.id)
          }
        }
        .frame(width: 200)
        .onChange(of: templateBase) { _, newVal in
          if newVal == "blank" {
            prompt = ""
          } else if let tone = registry.tone(forID: newVal) {
            prompt = tone.prompt
          }
        }
      }

      PromptEditorView(text: $prompt)

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.escape)

        Spacer()

        Button("Create") {
          guard !name.isEmpty else { return }
          onCreate(name, prompt)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.isEmpty)
        .keyboardShortcut(.return)
      }
    }
    .padding(24)
    .frame(width: 520, height: 520)
  }
}

// MARK: - Model Download Row

struct ModelDownloadRow: View {
  let title: String
  let description: String
  let state: ModelDownloadState
  let onDownload: () -> Void
  let onDelete: () -> Void
  let onRetry: () -> Void

  @State private var showDeleteConfirmation = false

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      statusView
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var statusView: some View {
    switch state {
    case .ready, .downloaded:
      HStack(spacing: 8) {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Ready")
            .font(.caption)
            .foregroundStyle(.green)
        }

        Button(role: .destructive) {
          showDeleteConfirmation = true
        } label: {
          Image(systemName: "trash")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .confirmationDialog("Delete \(title)?", isPresented: $showDeleteConfirmation) {
          Button("Delete", role: .destructive) {
            onDelete()
          }
        } message: {
          Text("You can re-download this model at any time.")
        }
      }

    case .downloading(let progress, let downloadedBytes, let totalBytes, let speedBytesPerSecond):
      VStack(alignment: .trailing, spacing: 2) {
        if progress > 0 {
          HStack(spacing: 8) {
            ProgressView(value: progress)
              .frame(width: 60)
            Text("\(Int(progress * 100))%")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        } else {
          HStack(spacing: 4) {
            ProgressView().scaleEffect(0.7)
            Text("Downloading...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if totalBytes > 0 {
          Text("\(formatBytes(downloadedBytes)) / \(formatBytes(totalBytes)) \u{2022} \(formatSpeed(speedBytesPerSecond))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
      }

    case .loading:
      HStack(spacing: 4) {
        ProgressView()
          .scaleEffect(0.7)
        Text("Loading...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .notDownloaded:
      Button("Download") {
        onDownload()
      }
      .font(.caption)
      .buttonStyle(.borderedProminent)
      .controlSize(.small)

    case .failed(let message):
      HStack(spacing: 8) {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text("Failed")
            .font(.caption)
            .foregroundStyle(.red)
        }
        .help(message)

        Button("Retry") {
          onRetry()
        }
        .font(.caption)
        .controlSize(.small)
      }
    }
  }
}

// MARK: - Ollama Model Row

struct OllamaModelRow: View {
  let model: CuratedOllamaModel
  let state: OllamaPullState
  let onPull: () -> Void
  let onDelete: () -> Void
  let onSelect: () -> Void

  @State private var showDeleteConfirmation = false

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(model.displayName)
          .font(.body)
        HStack(spacing: 4) {
          Text(model.estimatedSizeDescription)
          Text("\u{00B7}")
          Text(model.description)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      statusView
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private var statusView: some View {
    switch state {
    case .completed:
      HStack(spacing: 8) {
        Button("Use") {
          onSelect()
        }
        .font(.caption)
        .controlSize(.small)

        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Ready")
            .font(.caption)
            .foregroundStyle(.green)
        }

        Button(role: .destructive) {
          showDeleteConfirmation = true
        } label: {
          Image(systemName: "trash")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .confirmationDialog("Delete \(model.displayName)?", isPresented: $showDeleteConfirmation) {
          Button("Delete", role: .destructive) {
            onDelete()
          }
        }
      }

    case .pulling(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress)
          .frame(width: 60)
        Text("\(Int(progress * 100))%")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }

    case .idle:
      Button("Pull") {
        onPull()
      }
      .font(.caption)
      .buttonStyle(.borderedProminent)
      .controlSize(.small)

    case .failed(let message):
      HStack(spacing: 8) {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text("Failed")
            .font(.caption)
            .foregroundStyle(.red)
        }
        .help(message)

        Button("Retry") {
          onPull()
        }
        .font(.caption)
        .controlSize(.small)
      }
    }
  }
}
