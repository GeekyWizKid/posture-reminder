import AppKit
import SwiftUI

// MARK: - Reusable row: label + text field + unit + stepper

private struct DurationRow: View {
    let labelKey: LocalizedStringKey
    let helpKey:  LocalizedStringKey
    let unitKey:  LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step:  Int

    @State  private var inputText: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(labelKey)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            TextField("", text: $inputText)
                .multilineTextAlignment(.trailing)
                .frame(width: 46)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onAppear { inputText = "\(value)" }
                // Stepper changed value → sync text
                .onChange(of: value) { newVal in
                    if Int(inputText) != newVal { inputText = "\(newVal)" }
                }
                // User finished editing → commit & clamp
                .onChange(of: focused) { isFocused in
                    if !isFocused { commit() }
                }
                .onSubmit { commit() }

            Text(unitKey)
                .foregroundStyle(.secondary)
                .fixedSize()

            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
        .help(helpKey)
    }

    private func commit() {
        if let n = Int(inputText) {
            value = min(max(n, range.lowerBound), range.upperBound)
        }
        inputText = "\(value)"
    }
}

// MARK: - Settings form

private struct SettingsView: View {
    @ObservedObject var s = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DurationRow(
                labelKey: "settings.sitting_alert.label",
                helpKey:  "settings.sitting_alert.help",
                unitKey:  "settings.unit.min",
                value:    $s.sittingAlertMinutes,
                range:    10...180,
                step:     5
            )
            Divider()
            DurationRow(
                labelKey: "settings.idle_threshold.label",
                helpKey:  "settings.idle_threshold.help",
                unitKey:  "settings.unit.min",
                value:    $s.idleThresholdMinutes,
                range:    1...10,
                step:     1
            )
            Divider()
            DurationRow(
                labelKey: "settings.break_duration.label",
                helpKey:  "settings.break_duration.help",
                unitKey:  "settings.unit.min",
                value:    $s.breakMinutes,
                range:    1...30,
                step:     1
            )
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Window controller

final class SettingsWindowController: NSWindowController {

    convenience init() {
        let host = NSHostingController(rootView: SettingsView())
        let win  = NSWindow(contentViewController: host)
        win.title             = NSLocalizedString("settings.window_title", comment: "")
        win.styleMask         = [.titled, .closable]
        win.isReleasedWhenClosed = false
        self.init(window: win)
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
