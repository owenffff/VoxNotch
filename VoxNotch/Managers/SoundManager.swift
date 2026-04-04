//
//  SoundManager.swift
//  VoxNotch
//
//  Manages audio feedback sounds with customizable sound files
//

import AppKit
import AVFoundation

final class SoundManager {

  // MARK: - Singleton

  static let shared = SoundManager()

  /// User-accessible sounds directory: ~/Library/Application Support/VoxNotch/Sounds/
  let soundsDirectory: URL

  /// Holds a strong reference to the player so it doesn't get deallocated mid-playback
  private var currentPlayer: AVAudioPlayer?

  private init() {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    self.soundsDirectory = appSupport
      .appendingPathComponent("VoxNotch", isDirectory: true)
      .appendingPathComponent("Sounds", isDirectory: true)

    try? FileManager.default.createDirectory(
      at: soundsDirectory,
      withIntermediateDirectories: true
    )
  }

  // MARK: - Playback

  /// Play the success sound (non-blocking). Respects the enabled setting.
  func playSuccessSound() {
    guard SettingsManager.shared.successSoundEnabled else { return }
    playResolvedSound()
  }

  /// Preview the current sound (for the settings UI)
  func previewSound() {
    playResolvedSound()
  }

  // MARK: - Private

  private func playResolvedSound() {
    let customPath = SettingsManager.shared.customSuccessSoundPath
    if !customPath.isEmpty, FileManager.default.fileExists(atPath: customPath) {
      playFile(at: URL(fileURLWithPath: customPath))
    } else if let bundledURL = Bundle.main.url(forResource: "success", withExtension: "wav") {
      playFile(at: bundledURL)
    } else {
      NSSound(named: "Tink")?.play()
    }
  }

  private func playFile(at url: URL) {
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      currentPlayer = player
      player.play()
    } catch {
      print("SoundManager: Failed to play \(url.lastPathComponent): \(error)")
      NSSound(named: "Tink")?.play()
    }
  }
}
