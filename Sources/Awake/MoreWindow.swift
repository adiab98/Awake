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
        .frame(maxWidth: .infinity)
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
