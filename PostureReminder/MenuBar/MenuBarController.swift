import AppKit
import Combine

final class MenuBarController {

    private let statusItem: NSStatusItem
    private let stateManager: StateManager
    private var settingsWC: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    private enum Tag: Int {
        case stateLabel        = 1
        case sittingLabel      = 2
        case deepThinkingLabel = 3
        case diagCamera        = 10
        case diagPerson        = 11
        case diagIdle          = 12
    }

    init(stateManager: StateManager) {
        self.stateManager = stateManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        observeState()
        refreshButton(display: .sittingWorking)
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        // ── Status rows ───────────────────────────────────────────────────────
        let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateItem.tag = Tag.stateLabel.rawValue
        menu.addItem(stateItem)

        let sittingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        sittingItem.tag = Tag.sittingLabel.rawValue
        menu.addItem(sittingItem)

        let deepItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        deepItem.tag = Tag.deepThinkingLabel.rawValue
        deepItem.isHidden = true
        menu.addItem(deepItem)

        menu.addItem(.separator())

        // ── Diagnostics ───────────────────────────────────────────────────────
        for tag in [Tag.diagCamera, .diagPerson, .diagIdle] {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.tag = tag.rawValue
            item.isEnabled = false                      // non-interactive, dimmed
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // ── Actions ───────────────────────────────────────────────────────────
        let testItem = NSMenuItem(
            title: "Test Notification",
            action: #selector(handleTestNotification),
            keyEquivalent: ""
        )
        testItem.target = self
        menu.addItem(testItem)

        let resetItem = NSMenuItem(
            title: NSLocalizedString("menu.reset_timer", comment: ""),
            action: #selector(handleReset),
            keyEquivalent: "r"
        )
        resetItem.target = self
        menu.addItem(resetItem)

        let settingsItem = NSMenuItem(
            title: NSLocalizedString("menu.settings", comment: ""),
            action: #selector(handleSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.quit", comment: ""),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    // MARK: - Observation

    private func observeState() {
        Publishers.CombineLatest3(
            stateManager.$currentState,
            stateManager.$deepThinkingDuration,
            stateManager.$latestPose
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] state, _, pose in
            let display = DisplayState.derive(from: state, pose: pose)
            self?.refreshButton(display: display)
            self?.refreshMenuItems()
        }
        .store(in: &cancellables)

        // Sitting duration + diagnostics refresh
        Publishers.CombineLatest3(
            stateManager.$sittingDuration,
            stateManager.$isCameraActive,
            stateManager.$currentIdleSeconds
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in self?.refreshMenuItems() }
        .store(in: &cancellables)
    }

    // MARK: - Status bar button

    private func refreshButton(display: DisplayState) {
        guard let button = statusItem.button else { return }

        let symbolCfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.image = NSImage(
            systemSymbolName: display.sfSymbol,
            accessibilityDescription: stateManager.currentState.displayName
        )?.withSymbolConfiguration(symbolCfg)

        button.title = ""
        button.imagePosition = .imageOnly

        button.toolTip = String(
            format: NSLocalizedString("tooltip.format", comment: ""),
            stateManager.currentState.displayName
        )
    }

    // MARK: - Menu item refresh

    private func refreshMenuItems() {
        guard let menu = statusItem.menu else { return }
        let state = stateManager.currentState

        // State label
        if let item = menu.item(withTag: Tag.stateLabel.rawValue) {
            item.title = String(
                format: NSLocalizedString("menu.state_label", comment: ""),
                state.displayName
            )
        }

        // Sitting / break
        if let item = menu.item(withTag: Tag.sittingLabel.rawValue) {
            switch state {
            case .resting:
                item.title = NSLocalizedString("menu.on_break", comment: "")
            case .working, .deepThinking:
                let mins = Int(stateManager.sittingDuration / 60)
                item.title = String(
                    format: NSLocalizedString("menu.sitting_minutes", comment: ""),
                    mins
                )
            }
        }

        // Focus duration (only in deepThinking)
        if let item = menu.item(withTag: Tag.deepThinkingLabel.rawValue) {
            if state == .deepThinking {
                item.isHidden = false
                item.title = String(
                    format: NSLocalizedString("menu.focus_duration", comment: ""),
                    formatDuration(stateManager.deepThinkingDuration)
                )
            } else {
                item.isHidden = true
            }
        }

        // ── Diagnostics ───────────────────────────────────────────────────────
        if let item = menu.item(withTag: Tag.diagCamera.rawValue) {
            item.title = NSLocalizedString(
                stateManager.isCameraActive ? "diag.camera_on" : "diag.camera_off",
                comment: ""
            )
        }

        if let item = menu.item(withTag: Tag.diagPerson.rawValue) {
            item.title = NSLocalizedString(
                stateManager.latestPose.isPersonDetected ? "diag.person_yes" : "diag.person_no",
                comment: ""
            )
        }

        if let item = menu.item(withTag: Tag.diagIdle.rawValue) {
            item.title = String(
                format: NSLocalizedString("diag.idle", comment: ""),
                formatDuration(stateManager.currentIdleSeconds)
            )
        }
    }

    // MARK: - Helpers

    /// Formats seconds as MM:SS (or H:MM:SS when ≥ 1 hour).
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    // MARK: - Actions

    @objc private func handleTestNotification() {
        stateManager.sendTestNotification()
    }

    @objc private func handleReset() {
        stateManager.resetSittingTimer()
    }

    @objc private func handleSettings() {
        if settingsWC == nil { settingsWC = SettingsWindowController() }
        settingsWC?.show()
    }
}
