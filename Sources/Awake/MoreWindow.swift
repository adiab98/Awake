import SwiftUI
import AppKit

@MainActor
enum MoreWindow {
    private static let contentSize = NSSize(width: 520, height: 760)
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func show(controller: AwakeController) {
        NSApp.setActivationPolicy(.regular)

        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        controller.refreshForPresentation()

        let host = NSHostingController(
            rootView: MoreView().environmentObject(controller)
        )
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.title = "Awake"
        w.setContentSize(Self.contentSize)
        w.contentMinSize = Self.contentSize
        w.contentMaxSize = Self.contentSize
        w.standardWindowButton(.zoomButton)?.isEnabled = false
        w.collectionBehavior.remove(.fullScreenPrimary)
        w.center()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if let observer = closeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    closeObserver = nil
                }
                window = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

private struct MoreView: View {
    @EnvironmentObject var controller: AwakeController

    var body: some View {
        content
        .frame(width: 520, height: 760)
        .background(MoreMaterial())
    }

    private var content: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

            TabView {
                ScrollView {
                    settingsContent
                        .padding(.bottom, 18)
                }
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }

                ScrollView {
                    powerContent
                        .padding(.bottom, 18)
                }
                .tabItem {
                    Label("Power", systemImage: "bolt.fill")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: 0) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 24)
                .padding(.bottom, 8)

            Text("Awake")
                .font(.system(size: 18, weight: .bold))

            #if APP_STORE
            Text("Keeps your Mac awake while AI agents finish their turn.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 6)
            #else
            Text("Keeps your Mac awake while AI agents finish their turn, with guarded closed-lid support.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 6)
            #endif
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("Launch Awake at login")
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $controller.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Launch Awake at login")
                        .accessibilityValue(controller.launchAtLogin ? "On" : "Off")
                }
                if controller.launchAtLoginNeedsApproval {
                    Text("Approve in System Settings, General, Login Items.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = controller.launchAtLoginError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 28)

            Divider()
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 8) {
                Text("AI tools to wait for")
                    .font(.system(size: 13, weight: .semibold))
                Text("Awake stays awake while any enabled tool is working.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(AgentTool.allCases) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            HStack(spacing: 4) {
                                Text(tool.displayName)
                                    .font(.system(size: 12))
                                if tool.experimental {
                                    Text("experimental")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(Color.orange.opacity(0.5), lineWidth: 0.5)
                                        )
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { controller.enabledTools.contains(tool) },
                                set: { controller.setTool(tool, enabled: $0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .accessibilityLabel(tool.displayName)
                        }
                        if let note = tool.experimentalNote,
                           controller.enabledTools.contains(tool) {
                            Text(note)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            #if APP_STORE
            Divider()
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 10) {
                Text("Closed-lid support")
                    .font(.system(size: 13, weight: .semibold))

                Text("The Mac App Store build uses public macOS power assertions. Closed-lid support is available in the direct-download edition.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Learn More") {
                    controller.openClosedLidHelp()
                }
                .controlSize(.small)
                .accessibilityHint("Opens details about Awake's direct-download closed-lid support")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            #else
            Divider()
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 10) {
                Text("Lid-close sleep")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 6) {
                    Circle()
                        .fill(controller.lidPasswordlessReady ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(controller.lidPasswordlessReady
                         ? "Passwordless toggle: enabled"
                         : "Passwordless toggle: not set up")
                        .font(.system(size: 12, weight: .medium))
                }

                Text(verbatim: "Sudoers rule: /etc/sudoers.d/awake")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if controller.lidPasswordlessReady {
                    Text("Awake can toggle lid-close sleep and Low Power Mode silently. Low Power Mode is restored to its previous state when closed-lid support is turned off.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Set up once with your password and Awake will toggle lid-close sleep and Low Power Mode silently from then on. The lid override works on battery or charger power, with Low Power Mode kept on, and stops on high heat.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let lidSafetyMessage = controller.lidSafetyMessage {
                    Text(lidSafetyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                lidActionButtons

                if let error = controller.lidSetupError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            #endif

            Text("Version 0.1")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 24)
                .padding(.bottom, 18)
        }
    }

    private var powerContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Power status")
                    .font(.system(size: 13, weight: .semibold))
                Text("These are the macOS power values Awake uses or depends on when it keeps work running.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PowerStatusGroup(title: "Awake controls", rows: awakeControlRows)
            PowerStatusGroup(title: "macOS state", rows: macOSPowerRows)

            #if !APP_STORE
            if controller.powerStatus.sleepDisabled == true && !controller.lidGuardEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SleepDisabled is on outside Awake's closed-lid toggle.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    Text("That means macOS will keep lid-close sleep disabled until it is restored, even though Awake is not currently managing closed-lid mode.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    restoreLidSleepButton
                }
            }
            #endif

            if let error = controller.powerStatus.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var awakeControlRows: [PowerStatusRow] {
        [
            PowerStatusRow(
                title: "Awake session",
                value: controller.isCaffeinated ? "active" : "inactive",
                isActive: controller.isCaffeinated,
                explanation: "Active means Awake is currently asking macOS to keep the computer from idling."
            ),
            PowerStatusRow(
                title: "Wait for AI agent turn",
                value: controller.waitForAgents ? "on" : "off",
                isActive: controller.waitForAgents,
                explanation: "When on, agent activity can start or extend Awake's sleep prevention automatically."
            ),
            PowerStatusRow(
                title: "Stay awake with lid closed",
                value: controller.lidGuardEnabled ? "on" : "off",
                isActive: controller.lidGuardEnabled,
                explanation: "When on, Awake can manage the SleepDisabled setting while an Awake session is active. Turning this off does not always clear a stale or external SleepDisabled value."
            ),
            PowerStatusRow(
                title: "Keep display awake",
                value: controller.preventDisplaySleep ? "on" : "off",
                isActive: controller.preventDisplaySleep,
                explanation: "When off, the display may turn off while the Mac keeps running in the background."
            ),
            PowerStatusRow(
                title: "Passwordless lid toggle",
                value: controller.lidPasswordlessReady ? "ready" : "not ready",
                isActive: controller.lidPasswordlessReady,
                explanation: "Ready means Awake can change lid-close sleep without asking for your password each time."
            )
        ]
    }

    private var macOSPowerRows: [PowerStatusRow] {
        let status = controller.powerStatus
        return [
            PowerStatusRow(
                title: "SleepDisabled",
                value: numericBool(status.sleepDisabled),
                isActive: status.sleepDisabled,
                explanation: "1 means macOS lid-close sleep is disabled system-wide; 0 means closing the lid normally puts the Mac to sleep."
            ),
            PowerStatusRow(
                title: "PreventUserIdleSystemSleep",
                value: numericBool(status.preventUserIdleSystemSleep),
                isActive: status.preventUserIdleSystemSleep,
                explanation: "1 means at least one process is preventing idle system sleep so CPU work can continue."
            ),
            PowerStatusRow(
                title: "PreventSystemSleep",
                value: numericBool(status.preventSystemSleep),
                isActive: status.preventSystemSleep,
                explanation: "1 means a process is requesting stronger system-sleep prevention while it is active."
            ),
            PowerStatusRow(
                title: "PreventUserIdleDisplaySleep",
                value: numericBool(status.preventUserIdleDisplaySleep),
                isActive: status.preventUserIdleDisplaySleep,
                explanation: "1 means something is keeping the screen lit; 0 means the screen is allowed to turn off."
            ),
            PowerStatusRow(
                title: "lowpowermode",
                value: numericBool(status.lowPowerMode),
                isActive: status.lowPowerMode,
                explanation: "Awake turns this on during closed-lid support, then restores the previous state when that support is turned off."
            ),
            PowerStatusRow(
                title: "sleep",
                value: minutes(status.systemSleepMinutes),
                isActive: nil,
                explanation: "The idle system-sleep timer in minutes. Active sleep assertions temporarily override it."
            ),
            PowerStatusRow(
                title: "displaysleep",
                value: minutes(status.displaySleepMinutes),
                isActive: nil,
                explanation: "The idle display-sleep timer in minutes. This can still run while the Mac itself stays awake."
            )
        ]
    }

    private func numericBool(_ value: Bool?) -> String {
        guard let value else { return "unknown" }
        return value ? "1" : "0"
    }

    private func minutes(_ value: Int?) -> String {
        guard let value else { return "unknown" }
        return value == 1 ? "1 minute" : "\(value) minutes"
    }

    #if !APP_STORE
    private var lidActionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                primaryLidActionButton
                restoreLidSleepButton
            }

            VStack(alignment: .leading, spacing: 8) {
                primaryLidActionButton
                restoreLidSleepButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var primaryLidActionButton: some View {
        if controller.lidPasswordlessReady {
            Button("Revoke Passwordless Access") {
                controller.userRevokePasswordlessLid()
            }
            .controlSize(.small)
            .disabled(controller.lidActionInFlight)
        } else {
            Button("Set Up Passwordless Toggle") {
                controller.userInstallPasswordlessLid()
            }
            .controlSize(.small)
            .disabled(controller.lidActionInFlight)
        }
    }

    @ViewBuilder
    private var restoreLidSleepButton: some View {
        if controller.disablesleepActive {
            Button("Restore Lid Sleep") {
                controller.userRestoreLidSleep()
            }
            .controlSize(.small)
            .disabled(controller.lidActionInFlight)
        }
    }
    #endif
}

private struct PowerStatusRow: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let isActive: Bool?
    let explanation: String
}

private struct PowerStatusGroup: View {
    let title: String
    let rows: [PowerStatusRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    PowerStatusItem(row: row)
                }
            }
        }
    }
}

private struct PowerStatusItem: View {
    let row: PowerStatusRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(row.title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer(minLength: 8)
                Text(row.value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }
            Text(row.explanation)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 15)
        }
    }

    private var statusColor: Color {
        switch row.isActive {
        case true:
            return .green
        case false:
            return .secondary
        case nil:
            return .blue
        }
    }
}

private struct MoreMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .windowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
