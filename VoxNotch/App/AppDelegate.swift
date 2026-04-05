//
//  AppDelegate.swift
//  VoxNotch
//
//  NSApplicationDelegate for menu bar integration and app lifecycle
//

import SwiftUI
import AppKit
import CoreAudio

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var deviceChangeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupNotch()
        initializeDatabase()
        setupSleepWakeHandling()
        configureAppBehavior()

        if SettingsManager.shared.hasCompletedOnboarding {
            startNormalOperation()
        } else {
            showOnboardingWizard()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running when windows are closed (menu bar app)
        return false
    }

    // MARK: - Notch

    private func setupNotch() {
        NotchManager.shared.setup()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoxNotch")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Setup Wizard (re-run)
        menu.addItem(NSMenuItem(
            title: "Setup Wizard...",
            action: #selector(openSetupWizard),
            keyEquivalent: ""
        ))

        // Settings
        menu.addItem(NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))

        // Microphone submenu (tag 103 — relied on by buildMicrophoneSubmenu refresh logic and device change observer)
        let micMenuItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micMenuItem.tag = 103
        let micSubmenu = NSMenu(title: "Microphone")
        micMenuItem.submenu = micSubmenu
        menu.addItem(micMenuItem)
        buildMicrophoneSubmenu(micSubmenu)

        menu.addItem(NSMenuItem.separator())

        // Start/Stop Recording (tag 104)
        let recordItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordItem.tag = 104
        menu.addItem(recordItem)

        // Select Model (tag 105)
        let modelItem = NSMenuItem(
            title: "Select Model...",
            action: #selector(openModelSettings),
            keyEquivalent: ""
        )
        modelItem.tag = 105
        menu.addItem(modelItem)

        // History
        let historyItem = NSMenuItem(
            title: "History...",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(
            title: "Quit VoxNotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        self.statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func statusBarButtonClicked() {
        // Toggle menu (handled by the menu property)
    }

    @objc private func toggleRecording() {
        QuickDictationController.shared.toggleDictation()
        updateStatusIcon()
    }

    @objc private func openModelSettings() {
        SettingsWindowController.shared.showNavigatingToSpeechModel()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openSetupWizard() {
        let wizard = OnboardingWindowController.shared
        wizard.onComplete = {
            SettingsManager.shared.hasCompletedOnboarding = true
        }
        // Reset so the wizard shows all steps fresh
        SettingsManager.shared.hasCompletedOnboarding = false
        wizard.show()
    }

    @objc private func openHistory() {
        if #available(macOS 26.0, *) {
            HistoryWindowController.shared.show()
        }
    }

    // MARK: - Microphone Submenu

    private func buildMicrophoneSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let audioManager = AudioCaptureManager.shared
        let currentSelection = audioManager.selectedDeviceID

        /// System Default item
        let defaultItem = NSMenuItem(
            title: "System Default",
            action: #selector(selectMicrophone(_:)),
            keyEquivalent: ""
        )
        defaultItem.tag = 0
        defaultItem.target = self
        defaultItem.state = currentSelection == nil ? .on : .off
        menu.addItem(defaultItem)

        menu.addItem(NSMenuItem.separator())

        /// Available devices
        let devices = audioManager.availableInputDevices()

        if devices.isEmpty {
            let noDeviceItem = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            noDeviceItem.isEnabled = false
            menu.addItem(noDeviceItem)
        } else {
            for device in devices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(selectMicrophone(_:)),
                    keyEquivalent: ""
                )
                item.tag = Int(device.id)
                item.target = self
                item.state = currentSelection == device.id ? .on : .off
                menu.addItem(item)
            }
        }
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        let deviceID = sender.tag
        let audioManager = AudioCaptureManager.shared

        if deviceID == 0 {
            audioManager.selectInputDevice(nil)
        } else {
            audioManager.selectInputDevice(AudioDeviceID(deviceID))
        }

        /// Rebuild the submenu to update checkmarks
        if let menu = statusItem?.menu,
           let micMenuItem = menu.item(withTag: 103),
           let micSubmenu = micMenuItem.submenu
        {
            buildMicrophoneSubmenu(micSubmenu)
        }
    }

    // MARK: - Audio Device Monitoring

    private func setupAudioDeviceMonitoring() {
        let audioManager = AudioCaptureManager.shared

        /// Restore persisted device selection
        audioManager.restoreDeviceSelection()
        audioManager.warmUp()

        /// Start listening for device connect/disconnect
        audioManager.startDeviceChangeListener()

        /// Rebuild mic submenu when devices change
        deviceChangeObserver = NotificationCenter.default.addObserver(
            forName: AudioCaptureManager.inputDevicesChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self,
                  let menu = self.statusItem?.menu,
                  let micMenuItem = menu.item(withTag: 103),
                  let micSubmenu = micMenuItem.submenu
            else {
                return
            }

            self.buildMicrophoneSubmenu(micSubmenu)
        }
    }

    // MARK: - Status Updates

    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let appState = AppState.shared
        let symbolName: String

        switch appState.status {
        case .recording:
            symbolName = "waveform.circle.fill"
        case .warmingUp, .transcribing, .processing, .downloading:
            symbolName = "waveform.badge.ellipsis"
        case .error:
            symbolName = "waveform.badge.exclamationmark"
        case .modelsNeeded:
            symbolName = "arrow.down.circle"
        case .ready:
            symbolName = "waveform"
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VoxNotch - \(appState.status.rawValue)")
    }

    func updateMenuStatus() {
        guard let menu = statusItem?.menu else { return }

        let appState = AppState.shared

        // Update recording item title (tag 104)
        if let recordItem = menu.item(withTag: 104) {
            recordItem.title = appState.isRecording ? "Stop Recording" : "Start Recording"
        }
    }

    // MARK: - Database

    private func initializeDatabase() {
        Task {
            do {
                try await DatabaseManager.shared.initialize()
            } catch {
                print("Failed to initialize database: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Quick Dictation

    private func setupQuickDictation() {
        let controller = QuickDictationController.shared

        // Listen for state changes to update UI
        controller.onStateChange = { [weak self] state in
            self?.updateStatusIcon()
            self?.updateMenuStatus()
        }

        // Start the controller
        controller.start()

        // Check model readiness (no auto-download)
        let appState = AppState.shared
        Task {
            let modelManager = FluidAudioModelManager.shared
            let isReady = modelManager.quickDictationModelsReady()
            await MainActor.run {
                appState.isModelReady = isReady
                appState.isDownloadingModel = false
                if !isReady {
                    appState.modelsNeeded = true
                    let speechModelID = SettingsManager.shared.speechModel
                    let (builtin, custom) = SpeechModel.resolve(speechModelID)
                    let name = builtin?.displayName ?? custom?.displayName ?? speechModelID
                    appState.modelsNeededMessage = "Not downloaded: \(name)"
                }
            }
        }
    }

    // MARK: - First-Run Wizard

    private func showOnboardingWizard() {
        let wizard = OnboardingWindowController.shared
        wizard.onComplete = { [weak self] in
            self?.startNormalOperation()
        }
        wizard.show()
    }

    private func startNormalOperation() {
        setupQuickDictation()
        setupAudioDeviceMonitoring()

        // Refresh model states in case onboarding just downloaded a model
        FluidAudioModelManager.shared.refreshAllModelStates()
        MLXAudioModelManager.shared.refreshAllModelStates()
    }

    // MARK: - Configuration

    private func configureAppBehavior() {
        // Hide dock icon (menu bar only app)
        // Note: This should be set in Info.plist with LSUIElement = YES for production
        // For development, we keep the dock icon visible

        // Ensure app activates properly
        NSApp.setActivationPolicy(.accessory)

        // Check for updates on launch if enabled
        if SettingsManager.shared.checkForUpdatesAutomatically {
            UpdateManager.shared.checkForUpdatesInBackground()
        }
    }

    // MARK: - Sleep/Wake

    private func setupSleepWakeHandling() {
        let ws = NSWorkspace.shared.notificationCenter

        sleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = self // prevent unused warning
            QuickDictationController.shared.stop()
            ModelMemoryManager.shared.stopIdleTimer()
        }

        wakeObserver = ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = self
            QuickDictationController.shared.start()
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        QuickDictationController.shared.stop()

        // Clean up device monitoring
        AudioCaptureManager.shared.stopDeviceChangeListener()
        if let observer = deviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            deviceChangeObserver = nil
        }

        // Clean up sleep/wake observers
        let ws = NSWorkspace.shared.notificationCenter
        if let observer = sleepObserver {
            ws.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = wakeObserver {
            ws.removeObserver(observer)
            wakeObserver = nil
        }

        statusItem = nil
    }
}
