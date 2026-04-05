//
//  HistoryWindowView.swift
//  VoxNotch
//
//  Transcription history window -- browse and search past dictations
//

import SwiftUI
import GRDB
import os.log

// MARK: - Transcription History View

/// Main view for browsing and searching past dictation transcriptions
@available(macOS 26.0, *)
struct HistoryWindowView: View {

  @State private var transcriptions: [TranscriptionRecord] = []
  @State private var searchText: String = ""
  @State private var isLoading: Bool = false
  @State private var selectedTranscription: TranscriptionRecord?
  @State private var showDeleteConfirmation: Bool = false
  @State private var transcriptionToDelete: TranscriptionRecord?

  var body: some View {
    NavigationSplitView {
      sidebarContent
    } detail: {
      detailContent
    }
    .navigationTitle("Transcription History")
    .searchable(text: $searchText, prompt: "Search transcriptions")
    .task {
      await loadTranscriptions()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      Task {
        await loadTranscriptions()
      }
    }
    .onChange(of: searchText) { _, newValue in
      Task {
        await filterTranscriptions(query: newValue)
      }
    }
    .confirmationDialog(
      "Delete Transcription?",
      isPresented: $showDeleteConfirmation,
      presenting: transcriptionToDelete
    ) { transcription in
      Button("Delete", role: .destructive) {
        Task {
          await deleteTranscription(transcription)
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("This will permanently delete this transcription. This action cannot be undone.")
    }
  }

  // MARK: - Sidebar

  @ViewBuilder
  private var sidebarContent: some View {
    Group {
      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if transcriptions.isEmpty {
        ContentUnavailableView {
          Label(
            searchText.isEmpty ? "No Transcriptions" : "No Results",
            systemImage: "text.bubble"
          )
        } description: {
          Text(
            searchText.isEmpty
              ? "Your dictation transcriptions will appear here."
              : "Try a different search term."
          )
        }
      } else {
        transcriptionList
      }
    }
    .frame(minWidth: 280)
  }

  private var transcriptionList: some View {
    List(selection: $selectedTranscription) {
      ForEach(transcriptions) { transcription in
        TranscriptionRowView(transcription: transcription)
          .tag(transcription)
          .contextMenu {
            Button("Copy Text") {
              copyText(for: transcription)
            }

            Divider()

            Button("Delete", role: .destructive) {
              transcriptionToDelete = transcription
              showDeleteConfirmation = true
            }
          }
      }
    }
    .listStyle(.sidebar)
  }

  // MARK: - Detail

  @ViewBuilder
  private var detailContent: some View {
    if let transcription = selectedTranscription {
      TranscriptionDetailView(transcription: transcription)
        .id(transcription.id)
    } else {
      ContentUnavailableView {
        Label("Select a Transcription", systemImage: "doc.text")
      } description: {
        Text("Choose a transcription from the list to view the full text.")
      }
    }
  }

  // MARK: - Actions

  private func loadTranscriptions() async {
    isLoading = true
    defer { isLoading = false }

    do {
      transcriptions = try await DatabaseManager.shared.read { db in
        try TranscriptionRecord.allOrdered().fetchAll(db)
      }
    } catch {
      transcriptions = []
    }
  }

  private func filterTranscriptions(query: String) async {
    guard !query.isEmpty else {
      await loadTranscriptions()
      return
    }

    do {
      transcriptions = try await DatabaseManager.shared.read { db in
        try TranscriptionRecord.search(query: query, in: db)
      }
    } catch {
      transcriptions = []
    }
  }

  private func deleteTranscription(_ transcription: TranscriptionRecord) async {
    guard let transcriptionId = transcription.id else {
      return
    }

    do {
      _ = try await DatabaseManager.shared.write { db in
        try TranscriptionRecord.deleteOne(db, id: transcriptionId)
      }
      transcriptions.removeAll { $0.id == transcription.id }
      if selectedTranscription?.id == transcription.id {
        selectedTranscription = nil
      }
    } catch {
      Logger(subsystem: "com.voxnotch", category: "HistoryWindowView").error("Failed to delete transcription: \(error.localizedDescription)")
    }
  }

  private func copyText(for transcription: TranscriptionRecord) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(transcription.displayText, forType: .string)
  }
}

// MARK: - Metadata Helpers

/// Decoded metadata from a TranscriptionRecord's JSON metadata field
private struct TranscriptionMetadata {
  let tone: String?
  let outputMethod: String?

  init(from record: TranscriptionRecord) {
    guard let json = record.metadata,
          let data = json.data(using: .utf8),
          let dict = try? JSONDecoder().decode([String: String].self, from: data)
    else {
      self.tone = nil
      self.outputMethod = nil
      return
    }
    self.tone = dict["tone"]
    self.outputMethod = dict["outputMethod"]
  }

  var outputMethodLabel: String? {
    guard let method = outputMethod else { return nil }
    return method == "paste" ? "Pasted" : "Clipboard"
  }

  var outputMethodIcon: String {
    outputMethod == "paste" ? "text.cursor" : "doc.on.clipboard"
  }
}

// MARK: - Model Name Resolver

private func resolveModelDisplayName(_ rawModel: String) -> String {
  if let builtin = SpeechModel(rawValue: rawModel) {
    return builtin.displayName
  }
  if let custom = CustomModelRegistry.shared.model(withID: rawModel) {
    return custom.displayName
  }
  return rawModel
}

// MARK: - Transcription Row View

@available(macOS 26.0, *)
struct TranscriptionRowView: View {

  let transcription: TranscriptionRecord

  private var metadata: TranscriptionMetadata {
    TranscriptionMetadata(from: transcription)
  }

  private var relativeDate: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: transcription.timestamp, relativeTo: Date())
  }

  private var formattedDuration: String {
    let total = Int(transcription.duration)
    let m = total / 60
    let s = total % 60
    if m > 0 {
      return "\(m)m \(s)s"
    }
    return "\(s)s"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Preview text
      Text(transcription.displayText)
        .font(.body)
        .lineLimit(2)

      // Metadata pills
      HStack(spacing: 6) {
        MetadataPill(icon: "clock", text: relativeDate)

        MetadataPill(icon: "waveform", text: resolveModelDisplayName(transcription.model))

        if transcription.wasProcessed, let tone = metadata.tone {
          MetadataPill(icon: "sparkles", text: tone, tint: .purple)
        }

        Spacer()

        Text(formattedDuration)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .monospacedDigit()
      }
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Metadata Pill

private struct MetadataPill: View {
  let icon: String
  let text: String
  var tint: Color? = nil

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: icon)
        .font(.system(size: 9))
      Text(text)
        .font(.caption2)
        .lineLimit(1)
    }
    .foregroundStyle(tint ?? .secondary)
  }
}

// MARK: - Transcription Detail View

@available(macOS 26.0, *)
struct TranscriptionDetailView: View {

  let transcription: TranscriptionRecord

  private var metadata: TranscriptionMetadata {
    TranscriptionMetadata(from: transcription)
  }

  private var formattedDate: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .full
    formatter.timeStyle = .medium
    return formatter.string(from: transcription.timestamp)
  }

  private var formattedDuration: String {
    let total = Int(transcription.duration)
    let m = total / 60
    let s = total % 60
    if m > 0 {
      return String(format: "%dm %02ds", m, s)
    }
    return String(format: "%ds", s)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        // Header badges
        VStack(alignment: .leading, spacing: 10) {
          Text(formattedDate)
            .font(.subheadline)
            .foregroundStyle(.secondary)

          HStack(spacing: 8) {
            DetailBadge(icon: "clock", text: formattedDuration)
            DetailBadge(icon: "waveform", text: resolveModelDisplayName(transcription.model))

            if let confidence = transcription.confidence {
              DetailBadge(icon: "checkmark.seal", text: "\(Int(confidence * 100))%")
            }

            if let tone = metadata.tone, tone != "Original" {
              DetailBadge(icon: "sparkles", text: tone, tint: .purple)
            }

            if let outputLabel = metadata.outputMethodLabel {
              DetailBadge(icon: metadata.outputMethodIcon, text: outputLabel)
            }
          }
        }

        Divider()

        // Text content
        if transcription.wasProcessed {
          // Enhanced + original comparison
          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
              Label("Enhanced", systemImage: "sparkles")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.purple)

              Text(transcription.processedText ?? "")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
              Label("Original", systemImage: "text.quote")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

              Text(transcription.rawText)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
          }
        } else {
          Text(transcription.rawText)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()
      }
      .padding()
      .textSelection(.enabled)
    }
    .toolbar {
      ToolbarItem {
        Button {
          copyFullText()
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .help("Copy transcription text")
      }
    }
  }

  private func copyFullText() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(transcription.displayText, forType: .string)
  }
}

// MARK: - Detail Badge

private struct DetailBadge: View {
  let icon: String
  let text: String
  var tint: Color? = nil

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.system(size: 10))
      Text(text)
        .font(.caption)
    }
    .foregroundStyle(tint ?? .secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background((tint ?? .secondary).opacity(0.08))
    .clipShape(Capsule())
  }
}

// MARK: - Preview

@available(macOS 26.0, *)
#Preview {
  HistoryWindowView()
}
