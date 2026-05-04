import SwiftUI
import AppKit

@MainActor
enum MoreWindow {
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
        w.setContentSize(NSSize(width: 380, height: 420))
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
        VStack(spacing: 0) {

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 24)
                .padding(.bottom, 8)

            Text("Awake")
                .font(.system(size: 18, weight: .bold))

            Text("Keeps your Mac awake while AI agents finish their turn, even with the lid closed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 6)

            Divider()
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

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
                        if tool.experimental && controller.enabledTools.contains(tool) {
                            Text("Cursor's UI keeps API connections open even when idle. Detection is best-effort; turn off if Awake stays caffeinated when you're not actively prompting.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

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
                    Text("Awake can toggle lid-close sleep silently — no password prompt. Revoking removes the rule.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Set up once with your password and Awake will toggle lid-close sleep silently from then on. Until you do, the lid toggle in the menu will prompt for setup on first use.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
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
                    if controller.disablesleepActive {
                        Button("Restore Lid Sleep") {
                            controller.userRestoreLidSleep()
                        }
                        .controlSize(.small)
                        .disabled(controller.lidActionInFlight)
                    }
                }

                if let error = controller.lidSetupError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            Spacer()

            Text("Version 1.0")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .frame(width: 380)
        .background(MoreMaterial())
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
