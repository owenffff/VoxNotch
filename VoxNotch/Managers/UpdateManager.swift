//
//  UpdateManager.swift
//  VoxNotch
//
//  Manages app update checking and installation using Sparkle framework
//

import Foundation
import AppKit

/// Manages app updates using the Sparkle framework
///
/// ## Setup Instructions
/// 1. Add Sparkle to Package.swift or via SPM:
///    `.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")`
/// 2. Add SUFeedURL to Info.plist pointing to your appcast XML
/// 3. Enable automatic update checks in Settings
///
/// ## Appcast XML Example
/// ```xml
/// <?xml version="1.0" encoding="utf-8"?>
/// <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
///   <channel>
///     <title>VoxNotch Updates</title>
///     <item>
///       <title>Version 1.0.1</title>
///       <sparkle:version>1.0.1</sparkle:version>
///       <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
///       <description><![CDATA[<h2>Bug Fixes</h2><ul><li>Fixed crash</li></ul>]]></description>
///       <pubDate>Mon, 20 Jan 2025 12:00:00 +0000</pubDate>
///       <enclosure url="https://example.com/VoxNotch-1.0.1.dmg"
///                  sparkle:edSignature="..."
///                  length="12345678"
///                  type="application/octet-stream"/>
///     </item>
///   </channel>
/// </rss>
/// ```
@Observable
final class UpdateManager {

  // MARK: - Singleton

  static let shared = UpdateManager()

  // MARK: - Published State

  /// Whether an update is currently available
  var updateAvailable = false

  /// Latest available version string
  var latestVersion: String?

  /// Changelog/release notes for the update
  var releaseNotes: String?

  /// Whether we're currently checking for updates
  var isChecking = false

  /// Last error message if check failed
  var lastError: String?

  /// Last check date
  var lastCheckDate: Date?

  /// Whether to check for updates automatically (synced with SettingsManager)
  var checkForUpdatesAutomatically: Bool {
    get { UserDefaults.standard.bool(forKey: "checkForUpdatesAutomatically") }
    set { UserDefaults.standard.set(newValue, forKey: "checkForUpdatesAutomatically") }
  }

  // MARK: - Configuration

  /// URL for the appcast feed (set in Info.plist as SUFeedURL)
  private let feedURL: URL? = {
    if let urlString = Bundle.main.infoDictionary?["SUFeedURL"] as? String {
      return URL(string: urlString)
    }
    return nil
  }()

  /// Current app version
  var currentVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
  }

  /// Current build number
  var currentBuild: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
  }

  // MARK: - Private Properties

  #if canImport(Sparkle)
  private var updater: SPUUpdater?
  private var delegate: UpdaterDelegate?
  #endif

  // MARK: - Initialization

  private init() {
    setupSparkle()
  }

  // MARK: - Sparkle Setup

  private func setupSparkle() {
    #if canImport(Sparkle)
    /// Initialize Sparkle updater
    /// This requires Sparkle to be added as a dependency
    do {
      let delegate = UpdaterDelegate()
      self.delegate = delegate

      let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: delegate,
        userDriverDelegate: nil
      )
      self.updater = controller.updater

      /// Configure update settings
      updater?.automaticallyChecksForUpdates = SettingsManager.shared.checkForUpdatesAutomatically
      updater?.automaticallyDownloadsUpdates = false  // Let user choose

    } catch {
      lastError = "Failed to initialize updater: \(error.localizedDescription)"
    }
    #endif
  }

  // MARK: - Public Methods

  /// Check for updates manually
  func checkForUpdates() {
    guard !isChecking else {
      return
    }

    isChecking = true
    lastError = nil

    #if canImport(Sparkle)
    updater?.checkForUpdates()
    #else
    /// Fallback: Manual check without Sparkle
    Task {
      await checkForUpdatesManually()
    }
    #endif
  }

  /// Check for updates in background (non-interactive)
  func checkForUpdatesInBackground() {
    #if canImport(Sparkle)
    updater?.checkForUpdatesInBackground()
    #else
    Task {
      await checkForUpdatesManually()
    }
    #endif
  }

  /// Download and install available update
  func downloadAndInstallUpdate() {
    #if canImport(Sparkle)
    /// Sparkle handles this automatically when user accepts
    updater?.checkForUpdates()
    #else
    /// Open download page in browser as fallback
    // TODO(release): set real update URL before distribution
    if let downloadURL = URL(string: "") {
      NSWorkspace.shared.open(downloadURL)
    }
    #endif
  }

  /// Update automatic check setting
  func setAutomaticCheckEnabled(_ enabled: Bool) {
    SettingsManager.shared.checkForUpdatesAutomatically = enabled

    #if canImport(Sparkle)
    updater?.automaticallyChecksForUpdates = enabled
    #endif
  }

  // MARK: - Manual Update Check (Fallback)

  /// Check for updates using GitHub Releases API (fallback when Sparkle not available)
  private func checkForUpdatesManually() async {
    defer {
      Task { @MainActor in
        isChecking = false
        lastCheckDate = Date()
      }
    }

    guard let feedURL = feedURL else {
      await MainActor.run {
        lastError = "No update feed URL configured"
      }
      return
    }

    do {
      let (data, _) = try await URLSession.shared.data(from: feedURL)

      /// Parse appcast XML or JSON depending on format
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let tagName = json["tag_name"] as? String
      {
        /// GitHub Releases JSON format
        let latestVersion = tagName.replacingOccurrences(of: "v", with: "")

        await MainActor.run {
          self.latestVersion = latestVersion
          self.updateAvailable = isNewerVersion(latestVersion, than: currentVersion)
          self.releaseNotes = json["body"] as? String
        }
      } else {
        /// Try parsing as appcast XML
        await parseAppcastXML(data)
      }

    } catch {
      await MainActor.run {
        lastError = "Failed to check for updates: \(error.localizedDescription)"
      }
    }
  }

  /// Parse Sparkle appcast XML format
  private func parseAppcastXML(_ data: Data) async {
    /// Simple XML parsing for appcast
    guard let xmlString = String(data: data, encoding: .utf8) else {
      return
    }

    /// Extract version using regex
    if let versionRange = xmlString.range(of: "(?<=sparkle:version>)[^<]+", options: .regularExpression) {
      let version = String(xmlString[versionRange])

      await MainActor.run {
        self.latestVersion = version
        self.updateAvailable = isNewerVersion(version, than: currentVersion)
      }
    }

    /// Extract release notes
    if let notesRange = xmlString.range(of: "(?<=<description><!\\[CDATA\\[)[^\\]]+", options: .regularExpression) {
      let notes = String(xmlString[notesRange])

      await MainActor.run {
        self.releaseNotes = notes
      }
    }
  }

  /// Compare version strings
  private func isNewerVersion(_ latest: String, than current: String) -> Bool {
    let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
    let currentComponents = current.split(separator: ".").compactMap { Int($0) }

    for i in 0..<max(latestComponents.count, currentComponents.count) {
      let latestPart = i < latestComponents.count ? latestComponents[i] : 0
      let currentPart = i < currentComponents.count ? currentComponents[i] : 0

      if latestPart > currentPart {
        return true
      } else if latestPart < currentPart {
        return false
      }
    }

    return false
  }
}

// MARK: - Sparkle Delegate

#if canImport(Sparkle)
import Sparkle

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    Task { @MainActor in
      UpdateManager.shared.updateAvailable = true
      UpdateManager.shared.latestVersion = item.displayVersionString
      UpdateManager.shared.releaseNotes = item.itemDescription
      UpdateManager.shared.isChecking = false
    }
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
    Task { @MainActor in
      UpdateManager.shared.updateAvailable = false
      UpdateManager.shared.isChecking = false
      UpdateManager.shared.lastCheckDate = Date()
    }
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
    Task { @MainActor in
      UpdateManager.shared.lastError = error.localizedDescription
      UpdateManager.shared.isChecking = false
    }
  }
}
#endif

// MARK: - Settings Extension

extension SettingsManager {

  /// Whether to check for updates automatically on launch
  var checkForUpdatesAutomatically: Bool {
    get { UserDefaults.standard.bool(forKey: "checkForUpdatesAutomatically") }
    set { UserDefaults.standard.set(newValue, forKey: "checkForUpdatesAutomatically") }
  }
}
