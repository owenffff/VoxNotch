//
//  HistoryWindowView.swift
//  VoxNotch
//
//  Transcription history window -- browse and search past dictations
//

import SwiftUI
import GRDB

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
    .frame(minWidth: 250)
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
      // Silently handle
    }
  }

  private func copyText(for transcription: TranscriptionRecord) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(transcription.displayText, forType: .string)
  }
}

// MARK: - Transcription Row View

@available(macOS 26.0, *)
struct TranscriptionRowView: View {

  let transcription: TranscriptionRecord

  private var formattedDate: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: transcription.timestamp)
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
    VStack(alignment: .leading, spacing: 4) {
      Text(transcription.displayText)
        .font(.body)
        .lineLimit(2)

      HStack(spacing: 8) {
        Text(formattedDate)
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        if transcription.wasProcessed {
          Image(systemName: "sparkles")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Label(formattedDuration, systemImage: "clock")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(transcription.model)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Transcription Detail View

@available(macOS 26.0, *)
struct TranscriptionDetailView: View {

  let transcription: TranscriptionRecord

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
      VStack(alignment: .leading, spacing: 16) {
        /// Header
        Group {
          Text(formattedDate)
            .font(.subheadline)
            .foregroundStyle(.secondary)

          HStack(spacing: 16) {
            Label(formattedDuration, systemImage: "clock")
            Label(transcription.model, systemImage: "waveform")
            if let confidence = transcription.confidence {
              Label("\(Int(confidence * 100))%", systemImage: "checkmark.circle")
            }
            if transcription.wasProcessed {
              Label("AI Enhanced", systemImage: "sparkles")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Divider()

        /// Main text
        if transcription.wasProcessed {
          VStack(alignment: .leading, spacing: 8) {
            Text("Enhanced Text")
              .font(.caption)
              .foregroundStyle(.secondary)
              .textCase(.uppercase)

            Text(transcription.processedText ?? "")
              .font(.body)
              .fixedSize(horizontal: false, vertical: true)
          }

          Divider()

          VStack(alignment: .leading, spacing: 8) {
            Text("Original Text")
              .font(.caption)
              .foregroundStyle(.secondary)
              .textCase(.uppercase)

            Text(transcription.rawText)
              .font(.body)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Preview

@available(macOS 26.0, *)
#Preview {
  HistoryWindowView()
}
