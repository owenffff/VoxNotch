//
//  DictionaryEntrySheet.swift
//  VoxNotch
//
//  Sheet for adding or editing a custom dictionary entry
//

import SwiftUI

struct DictionaryEntrySheet: View {

  @Environment(\.dismiss) private var dismiss

  @State private var spokenForm: String = ""
  @State private var writtenForm: String = ""
  @State private var errorMessage: String?

  /// Non-nil when editing an existing entry
  var existing: DictionaryEntry? = nil
  let onSave: (DictionaryEntry) -> Void

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(existing == nil ? "Add Dictionary Entry" : "Edit Dictionary Entry")
        .font(.title2)
        .fontWeight(.semibold)

      // Written form field (shown first — output-first thinking)
      VStack(alignment: .leading, spacing: 6) {
        Text("Written form")
          .font(.caption)
          .foregroundStyle(.secondary)
        TextField("e.g. GPT", text: $writtenForm)
          .textFieldStyle(.roundedBorder)
          .onChange(of: writtenForm) { _, _ in errorMessage = nil }
        Text("What appears in your text")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Spoken form field
      VStack(alignment: .leading, spacing: 6) {
        Text("Spoken form")
          .font(.caption)
          .foregroundStyle(.secondary)
        TextField("e.g. gee pee tee", text: $spokenForm)
          .textFieldStyle(.roundedBorder)
          .onChange(of: spokenForm) { _, _ in errorMessage = nil }
        Text("How you say it when dictating (matched case-insensitively)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Error banner
      if let error = errorMessage {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.callout)
          Text(error)
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }

      Spacer(minLength: 0)

      // Action buttons
      HStack {
        Button("Cancel") { dismiss() }
          .buttonStyle(.bordered)

        Spacer()

        Button(existing == nil ? "Add" : "Save") {
          save()
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          spokenForm.trimmingCharacters(in: .whitespaces).isEmpty
            || writtenForm.trimmingCharacters(in: .whitespaces).isEmpty
        )
      }
    }
    .padding(24)
    .frame(width: 400)
    .onAppear {
      if let existing {
        spokenForm = existing.spokenForm
        writtenForm = existing.writtenForm
      }
    }
  }

  // MARK: - Save

  private func save() {
    let spoken = spokenForm.trimmingCharacters(in: .whitespaces)
    let written = writtenForm.trimmingCharacters(in: .whitespaces)

    guard !spoken.isEmpty else {
      errorMessage = "Spoken form cannot be empty."
      return
    }
    guard !written.isEmpty else {
      errorMessage = "Written form cannot be empty."
      return
    }

    // Duplicate check (skip if editing the same entry)
    if existing?.spokenForm.lowercased() != spoken.lowercased(),
       DictionaryRegistry.shared.containsSpokenForm(spoken)
    {
      errorMessage = "A rule for \"\(spoken)\" already exists."
      return
    }

    let entry = DictionaryEntry(spokenForm: spoken, writtenForm: written)
    onSave(entry)
    dismiss()
  }
}

// MARK: - Preview

#Preview {
  DictionaryEntrySheet { _ in }
}
