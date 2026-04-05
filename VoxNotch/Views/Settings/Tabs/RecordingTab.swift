//
//  RecordingTab.swift
//  VoxNotch
//
//  Recording settings: hotkey, behavior, advanced (mic, auto-stop)
//

import SwiftUI
import AVFoundation
import CoreAudio

struct RecordingTab: View {

  @Bindable private var settings = SettingsManager.shared
  @State private var hotkeyError: String?

  // Microphone test state
  @State private var isTesting = false
  @State private var isPlaying = false
  @State private var testAudioURL: URL?
  @State private var testTranscription: String?
  @State private var testError: String?
  @State private var audioPlayer: AVAudioPlayer?
  @State private var availableMicrophones: [(id: AudioDeviceID, name: String)] = []

  var body: some View {
    Form {
      // MARK: Microphone
      Section {
        Picker("Device", selection: Binding(
          get: { settings.selectedMicrophoneDeviceID },
          set: { newValue in
            settings.selectedMicrophoneDeviceID = newValue
            AudioCaptureManager.shared.selectInputDevice(newValue == 0 ? nil : newValue)
          }
        )) {
          Text("System Default").tag(UInt32(0))
          Divider()
          ForEach(availableMicrophones, id: \.id) { mic in
            Text(mic.name).tag(mic.id)
          }
        }

        HStack {
          Button(isTesting ? "Stop Test" : "Start Test") {
            if isTesting {
              stopTest()
            } else {
              startTest()
            }
          }
          .buttonStyle(.borderedProminent)
          .tint(isTesting ? .red : .accentColor)

          if isTesting {
            HStack(spacing: 4) {
              Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(0.8)
              Text("Recording...")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Spacer()

          if testAudioURL != nil && !isTesting {
            Button(isPlaying ? "Stop Playback" : "Play Audio") {
              if isPlaying {
                stopPlayback()
              } else {
                startPlayback()
              }
            }
            .buttonStyle(.bordered)
          }
        }

        if let error = testError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }

        if let transcription = testTranscription {
          VStack(alignment: .leading, spacing: 4) {
            Text("Dictation Result:")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(transcription.isEmpty ? "(No speech detected)" : transcription)
              .font(.body)
              .padding(8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.secondary.opacity(0.1))
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
        }
      } header: {
        Text("Microphone")
      }

      // MARK: Hotkey
      Section {
        LabeledContent("Recording Hotkey") {
          HotkeyRecorderView(
            displayString: $settings.hotkeyModifiers,
            modifierFlags: $settings.hotkeyModifierFlags
          )
        }

        if let error = hotkeyError {
          Text(error)
            .foregroundStyle(.red)
            .font(.caption)
        }

        Button("Reset to Default (\u{2303}\u{2325})") {
          settings.updateHotkey(modifierFlags: 0xC0000, displayString: "\u{2303}\u{2325}")
        }
        .buttonStyle(.borderless)
      } header: {
        Text("Hotkey")
      } footer: {
        Text("Press and hold this shortcut to start recording.")
      }

      // MARK: Recording Behavior
      Section {
        Toggle(isOn: $settings.holdToRecord) {
          InfoLabel(title: "Hold to record", tooltip: "When enabled, recording stops when you release the hotkey. When disabled, press once to start and once to stop.")
        }

        if settings.holdToRecord {
          LabeledContent {
            Slider(value: $settings.minimumRecordingDuration, in: 0.1...1.0, step: 0.1) {
              Text("Duration")
            }
            Text("\(settings.minimumRecordingDuration, specifier: "%.1f")s")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          } label: {
            InfoLabel(title: "Minimum duration", tooltip: "Recordings shorter than this are discarded. Prevents accidental triggers.")
          }
        }

      } header: {
        Text("Recording Behavior")
      }

    }
    .formStyle(.grouped)
    .scrollIndicators(.never)
    .padding()
    .onAppear {
      availableMicrophones = AudioCaptureManager.shared.availableInputDevices()
    }
    .onReceive(NotificationCenter.default.publisher(for: AudioCaptureManager.inputDevicesChangedNotification)) { _ in
      availableMicrophones = AudioCaptureManager.shared.availableInputDevices()
    }
    .onDisappear {
      cleanupTest()
    }
  }

  // MARK: - Test Microphone Logic

  private func startTest() {
    testError = nil
    testTranscription = nil
    testAudioURL = nil
    stopPlayback()

    do {
      try AudioCaptureManager.shared.startRecording()
      isTesting = true
    } catch {
      testError = "Failed to start recording: \(error.localizedDescription)"
    }
  }

  private func stopTest() {
    do {
      let result = try AudioCaptureManager.shared.stopRecording()
      testAudioURL = result.fileURL
      isTesting = false
      transcribeTestAudio(url: result.fileURL)
    } catch {
      testError = "Failed to stop recording: \(error.localizedDescription)"
      isTesting = false
    }
  }

  private func transcribeTestAudio(url: URL) {
    testTranscription = "Transcribing..."

    Task {
      do {
        try await TranscriptionService.shared.ensureModelReady()
        let result = try await TranscriptionService.shared.transcribe(audioURL: url)
        await MainActor.run {
          testTranscription = result.text
        }
      } catch {
        await MainActor.run {
          testTranscription = nil
          testError = "Transcription failed: \(error.localizedDescription)"
        }
      }
    }
  }

  private func startPlayback() {
    guard let url = testAudioURL else { return }

    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.play()
      isPlaying = true

      Task {
        while let player = audioPlayer, player.isPlaying {
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await MainActor.run {
          isPlaying = false
        }
      }
    } catch {
      testError = "Failed to play audio: \(error.localizedDescription)"
    }
  }

  private func stopPlayback() {
    audioPlayer?.stop()
    isPlaying = false
  }

  private func cleanupTest() {
    if isTesting {
      AudioCaptureManager.shared.cancelRecording()
      isTesting = false
    }
    stopPlayback()
    if let url = testAudioURL {
      AudioCaptureManager.shared.cleanupFile(at: url)
    }
  }
}
