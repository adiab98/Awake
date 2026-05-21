import SwiftUI
import AppKit

struct MenuView: View {
    @EnvironmentObject var controller: AwakeController
    @State private var showingCustomTimer = false
    @State private var customTimerInput = ""
    @State private var customTimerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Awake header + main toggle
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Awake")
                        .font(.system(size: 14, weight: .semibold))
                    if let txt = controller.activeUntilText {
                        Text(txt)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { controller.isCaffeinated },
                    set: { newValue in controller.userToggleAwake(on: newValue) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.accentColor)
                .accessibilityLabel("Awake")
                .accessibilityValue(controller.isCaffeinated ? "On" : "Off")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if let error = controller.powerAssertionError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            divider

            // Wait for AI agent turn
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text("Wait for AI agent turn")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    Toggle("", isOn: $controller.waitForAgents)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(.accentColor)
                        .accessibilityLabel("Wait for AI agent turn")
                        .accessibilityValue(controller.waitForAgents ? "On" : "Off")
                }
                if controller.brandStatuses.isEmpty {
                    Text("No agent detected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.brandStatuses, id: \.brand) { status in
                        HStack(spacing: 5) {
                            Text("\(status.brand): \(status.state)")
                                .font(.system(size: 11))
                                .foregroundStyle(status.isActive ? Color.accentColor : .secondary)
                        }
                    }
                }
                if let notice = controller.statusNotice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            divider

            // Timer
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Timer")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if controller.timerEnabled {
                        Menu {
                            ForEach(Duration.timerPresets) { preset in
                                Button(preset.menuLabel) {
                                    controller.selectedDuration = preset
                                    customTimerError = nil
                                    showingCustomTimer = false
                                }
                            }
                            Divider()
                            Button("Custom…") {
                                customTimerInput = controller.timerMinutes > 0
                                    ? String(controller.timerMinutes) : ""
                                customTimerError = nil
                                showingCustomTimer = true
                            }
                        } label: {
                            Text(controller.selectedDuration.menuLabel)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    Toggle("", isOn: Binding(
                        get: { controller.timerEnabled },
                        set: {
                            controller.timerEnabled = $0
                            if !$0 {
                                showingCustomTimer = false
                                customTimerError = nil
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(.accentColor)
                    .accessibilityLabel("Timer")
                    .accessibilityValue(controller.timerEnabled ? "On" : "Off")
                }
                if showingCustomTimer && controller.timerEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            TextField("Minutes", text: $customTimerInput)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(width: 80)
                                .onSubmit { applyCustomTimer() }
                            Text("min")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Set") { applyCustomTimer() }
                                .controlSize(.small)
                            Button("Cancel") {
                                customTimerError = nil
                                showingCustomTimer = false
                            }
                            .controlSize(.small)
                        }
                        if let customTimerError {
                            Text(customTimerError)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.red)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            divider

            // Lid + display
            VStack(alignment: .leading, spacing: 6) {
                #if APP_STORE
                Text("Closed-lid support uses the direct-download edition.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Learn More") {
                    controller.openClosedLidHelp()
                }
                .controlSize(.small)
                .accessibilityHint("Opens details about Awake's direct-download closed-lid support")
                #else
                MenuToggle(
                    title: "Stay awake with lid closed",
                    isOn: Binding(
                        get: { controller.lidGuardEnabled },
                        set: { controller.userToggleLidGuard(on: $0) }
                    )
                )
                if !controller.lidPasswordlessReady {
                    Text(controller.lidActionInFlight
                         ? "Waiting for password…"
                         : "First use asks for your password once.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let lidSafetyMessage = controller.lidSafetyMessage {
                    Text(lidSafetyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if controller.lidGuardEnabled {
                    Text("Low Power Mode is kept on until this is turned off.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                #endif
                MenuToggle(title: "Keep display awake",
                           isOn: $controller.preventDisplaySleep)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            divider

            MenuRow(title: "More…") {
                MoreWindow.show(controller: controller)
            }
            MenuRow(title: "Quit") {
                controller.requestQuit()
            }

            Spacer().frame(height: 8)
        }
        .frame(width: 300)
        .background(MenuMaterial())
        .onAppear { controller.refreshForPresentation() }
        .onDisappear {
            showingCustomTimer = false
            customTimerInput = ""
            customTimerError = nil
            controller.clearStatusNotice()
        }
    }

    private func applyCustomTimer() {
        let trimmed = customTimerInput.trimmingCharacters(in: .whitespaces)
        guard let n = Int(trimmed), (1...10080).contains(n) else {
            customTimerError = "Enter 1 to 10080 minutes."
            return
        }
        controller.selectedDuration = .minutes(n)
        customTimerError = nil
        showingCustomTimer = false
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
}

private struct MenuToggle: View {
    let title: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.accentColor)
                .accessibilityLabel(title)
                .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
        }
    }
}

private struct MenuMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct MenuRow: View {
    let title: String
    var trailing: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let trailing {
                    Image(systemName: trailing)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
