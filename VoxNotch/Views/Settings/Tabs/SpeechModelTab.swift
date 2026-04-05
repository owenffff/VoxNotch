//
//  SpeechModelTab.swift
//  VoxNotch
//
//  Speech model selection: built-in models, custom models, quick-switch
//

import SwiftUI
import os.log

private let settingsLogger = Logger(subsystem: "com.voxnotch", category: "SpeechModelTab")

struct SpeechModelTab: View {

  @Bindable private var settings = SettingsManager.shared
  @State private var fluidModelManager = FluidAudioModelManager.shared
  @State private var mlxModelManager = MLXAudioModelManager.shared
  @State private var customRegistry = CustomModelRegistry.shared
  @State private var showAddCustomModel = false
  @State private var showBrowseModels = false

  private var selectedBuiltinModel: SpeechModel? {
    SpeechModel(rawValue: settings.speechModel)
  }

  private var selectedCustomModel: CustomSpeechModel? {
    CustomModelRegistry.shared.model(withID: settings.speechModel)
  }

  var body: some View {
    Form {
      // Built-in Models
      Section {
        // Privacy badge
        Label("On-device, private, no network required", systemImage: "checkmark.shield")
          .foregroundStyle(.green)
          .font(.callout)

        ForEach(SpeechModel.allCases) { model in
          ModelCard(
            model: model,
            isSelected: selectedBuiltinModel == model,
            downloadState: downloadState(for: model),
            onSelect: { selectModel(model) },
            onDownload: { downloadModel(model) }
          )
        }
      } header: {
        Text("Built-in Models")
      } footer: {
        Text("Speech-to-text models that run locally on your Mac. Larger models are more accurate but use more memory.")
      }

      // Custom Models
      Section {
        if customRegistry.models.isEmpty {
          Text("No custom models added yet.")
            .foregroundStyle(.secondary)
            .font(.callout)
        } else {
          ForEach(customRegistry.models) { model in
            CustomModelCard(
              model: model,
              isSelected: selectedCustomModel?.id == model.id,
              downloadState: customDownloadState(for: model),
              onSelect: { settings.speechModel = model.id },
              onDownload: { downloadCustomModel(model) },
              onDelete: { deleteCustomModel(model) }
            )
          }
        }

        HStack(spacing: 0) {
          Button {
            showAddCustomModel = true
          } label: {
            Label("Add Custom Model", systemImage: "plus.circle.fill")
              .frame(maxWidth: .infinity)
              .padding(.vertical, 10)
          }
          .buttonStyle(.borderless)

          Divider().frame(height: 28)

          Button {
            showBrowseModels = true
          } label: {
            Label("Browse HuggingFace Models", systemImage: "safari")
              .frame(maxWidth: .infinity)
              .padding(.vertical, 10)
          }
          .buttonStyle(.borderless)
        }
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
            .foregroundStyle(Color(nsColor: .separatorColor))
        )
      } header: {
        Text("Custom Models")
      } footer: {
        Text("Import Whisper-compatible models from Hugging Face to use models not included by default.")
      }

      // Quick-Switch
      Section {
        QuickSwitchOrderedList(
          pinnedIDs: $settings.pinnedModelIDs,
          availableItems: allModelOptions,
          maxItems: 3
        )
      } header: {
        Text("Quick-Switch (\u{2190} \u{2192})")
      } footer: {
        Text("Pin up to 3 models to quickly switch between them using hotkey + arrow keys.")
      }
    }
    .formStyle(.grouped)
    .scrollIndicators(.never)
    .padding()
    .onAppear {
      fluidModelManager.refreshAllModelStates()
      mlxModelManager.refreshAllModelStates()
    }
    .onChange(of: settings.speechModel) { _, _ in
      TranscriptionService.shared.reconfigure()
      refreshModelsNeeded()
    }
    .sheet(isPresented: $showAddCustomModel) {
      CustomModelSheet { newModel in
        // Auto-select newly added model
        settings.speechModel = newModel.id
        refreshModelsNeeded()
      }
    }
    .sheet(isPresented: $showBrowseModels) {
      HFModelBrowserSheet()
    }
  }

  // MARK: - Quick-Switch Helpers

  private var allModelOptions: [(id: String, name: String)] {
    var options: [(id: String, name: String)] = SpeechModel.allCases.map { ($0.rawValue, $0.displayName) }
    options += customRegistry.models.map { ($0.id, $0.displayName) }
    return options
  }

  // MARK: - Built-in Model Helpers

  private func downloadState(for model: SpeechModel) -> UIDownloadState {
    switch model.engine {
    case .fluidAudio:
      guard let version = model.fluidAudioVersion else { return .notDownloaded }
      let state = fluidModelManager.modelStates[version] ?? .notDownloaded
      return state.uiState
    case .mlxAudio:
      guard let version = model.mlxAudioVersion else { return .notDownloaded }
      let state = mlxModelManager.modelStates[version] ?? .notDownloaded
      return state.uiState
    }
  }

  private func selectModel(_ model: SpeechModel) {
    settings.speechModel = model.rawValue
  }

  private func downloadModel(_ model: SpeechModel) {
    Task {
      do {
        switch model.engine {
        case .fluidAudio:
          guard let version = model.fluidAudioVersion else { return }
          try await fluidModelManager.downloadBatchModel(version: version)
          await MainActor.run {
            fluidModelManager.refreshAllModelStates()
            refreshModelsNeeded()
          }
        case .mlxAudio:
          guard let version = model.mlxAudioVersion else { return }
          try await mlxModelManager.downloadAndLoad(version: version)
          await MainActor.run {
            mlxModelManager.refreshAllModelStates()
            refreshModelsNeeded()
          }
        }
      } catch {
        settingsLogger.error("Model download failed: \(error.localizedDescription)")
        // Model managers already update their state to .failed internally
      }
    }
  }

  // MARK: - Custom Model Helpers

  private func customDownloadState(for model: CustomSpeechModel) -> UIDownloadState {
    if let state = mlxModelManager.customModelStates[model.id] {
      return state.uiState
    }
    return model.isDownloaded ? .ready : .notDownloaded
  }

  private func downloadCustomModel(_ model: CustomSpeechModel) {
    Task {
      do {
        try await mlxModelManager.downloadAndLoadCustom(model: model)
      } catch {
        settingsLogger.error("Custom model download failed (\(model.hfRepoID)): \(error.localizedDescription)")
      }
      await MainActor.run { refreshModelsNeeded() }
    }
  }

  private func deleteCustomModel(_ model: CustomSpeechModel) {
    mlxModelManager.deleteCustomModel(model)
    // If this was the selected model, fall back to default
    if settings.speechModel == model.id {
      settings.speechModel = SpeechModel.defaultModel.rawValue
    }
    // Remove from pinned slots
    settings.pinnedModelIDs = settings.pinnedModelIDs.filter { $0 != model.id }
    refreshModelsNeeded()
  }

  private func refreshModelsNeeded() {
    let appState = AppState.shared
    let isReady: Bool
    let displayName: String

    if let builtin = selectedBuiltinModel {
      let state = downloadState(for: builtin)
      isReady = state == .ready
      displayName = builtin.displayName
    } else if let custom = selectedCustomModel {
      isReady = custom.isDownloaded
      displayName = custom.displayName
    } else {
      isReady = false
      displayName = "Unknown"
    }

    appState.isModelReady = isReady
    appState.modelsNeeded = !isReady
    appState.modelsNeededMessage = isReady ? "" : "Not downloaded: \(displayName)"
  }
}
