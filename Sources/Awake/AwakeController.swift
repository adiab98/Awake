import SwiftUI
import AppKit
import Combine

@MainActor
final class AwakeController: ObservableObject {
    // Manual caffeination (the main "Awake" toggle).
    @Published private(set) var manualActive = false
    @Published private(set) var manualEndDate: Date?

    // Detected agents (scanner runs always; acting on them depends on waitForAgents).
    @Published private(set) var detectedAgents: [DetectedAgent] = []

    @Published var selectedDuration: Duration = .indefinite {
        didSet {
            guard selectedDuration != oldValue else { return }
            if manualActive {
                applySelectedDuration(restartTimer: true)
            }
        }
    }

    /// Bridges the menu's number field to selectedDuration. 0 → no timer.
    var timerMinutes: Int {
        get { selectedDuration.totalMinutes }
        set { selectedDuration = Duration.from(minutes: newValue) }
    }

    /// Last non-zero duration the user picked, so toggling Timer off→on restores it.
    @AppStorage("lastTimerMinutes") private var lastTimerMinutes: Int = 15

    /// Toggle-state binding for the Timer row.
    /// ON  → selectedDuration is the last-chosen duration (or 15 min default).
    /// OFF → selectedDuration is .indefinite; remembers the previous value for next ON.
    var timerEnabled: Bool {
        get { selectedDuration != .indefinite }
        set {
            if newValue {
                if selectedDuration == .indefinite {
                    selectedDuration = .minutes(max(1, lastTimerMinutes))
                }
                if !manualActive {
                    startManual()
                }
            } else {
                let mins = selectedDuration.totalMinutes
                if mins > 0 { lastTimerMinutes = mins }
                selectedDuration = .indefinite
            }
        }
    }

    // The agent-wait toggle. Default OFF so nothing surprising happens until the user
    // explicitly opts in.
    @AppStorage("waitForAgents") var waitForAgents: Bool = false {
        didSet {
            if waitForAgents { clearStatusNotice() }
            sync()
        }
    }
    /// Stored preference for the lid-close override. The UI never writes this
    /// directly — it goes through `userToggleLidGuard` so the install flow can
    /// gate the first ON.
    ///
    /// Backed by `@Published` (with manual UserDefaults persistence) rather
    /// than `@AppStorage`. `@AppStorage` in an `ObservableObject` class doesn't
    /// route through `objectWillChange`, which means SwiftUI bindings backed by
    /// it won't re-read after `objectWillChange.send()` — the Toggle in the
    /// menu would visually stay ON even after a cancelled install.
    @Published private(set) var lidGuardEnabled: Bool {
        didSet {
            UserDefaults.standard.set(lidGuardEnabled, forKey: Self.lidGuardKey)
            sync()
        }
    }
    private static let lidGuardKey = "lidGuardEnabledV2"

    /// Tracks whether we've offered the one-time install dialog. Set on
    /// dismissal regardless of the user's choice — we never re-pester.
    private static let hasOfferedLidSetupKey = "hasOfferedLidSetup"
    private var hasOfferedLidSetup: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasOfferedLidSetupKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasOfferedLidSetupKey) }
    }

    /// Same idea for the AI tool picker — show once, never re-prompt.
    private static let hasOfferedToolPickerKey = "hasOfferedToolPicker"
    private var hasOfferedToolPicker: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasOfferedToolPickerKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasOfferedToolPickerKey) }
    }

    /// Which AI tools detection runs for. Mutated by onboarding + More toggles;
    /// pushed down to AgentMonitor and LogActivityWatcher on every change.
    @Published private(set) var enabledTools: Set<AgentTool> {
        didSet {
            AgentToolStore.save(enabledTools)
            agents.enabledTools = enabledTools
            logWatcher.enabledTools = enabledTools
        }
    }

    func setTool(_ tool: AgentTool, enabled: Bool) {
        var next = enabledTools
        if enabled { next.insert(tool) } else { next.remove(tool) }
        enabledTools = next
    }
    @AppStorage("preventDisplaySleep") var preventDisplaySleep: Bool = false { didSet { sync() } }

    /// Reflects the actual current state of `pmset disablesleep`.
    @Published private(set) var disablesleepActive: Bool = false
    /// Whether the passwordless sudoers rule is active for the current user.
    @Published private(set) var lidInstallStatus: LidInstallStatus = .notInstalled
    @Published private(set) var powerAssertionError: String?
    @Published private(set) var statusNotice: String?
    /// Last error from an install/uninstall attempt, surfaced in More.
    @Published private(set) var lidSetupError: String?

    /// Most recent FSEvents write timestamp per agent source.
    @Published private(set) var lastLogActivity: [LogActivityWatcher.Source: Date] = [:]

    /// Sleep-decision hold window. Long, so we don't release sleep during quiet gaps
    /// in long-running tool execution (Bash downloads, WebFetch, etc.).
    static let logActivityHoldWindow: TimeInterval = 90

    /// UI "currently in turn" window. Short, so the menu reflects the user's actual
    /// perception of when a turn ended.
    static let inTurnDisplayWindow: TimeInterval = 6

    /// Sticky-hold for the sleep decision: any signal in this window keeps the Mac
    /// awake even if right-now signals are quiet.
    static let activityStickyHold: TimeInterval = 45

    /// Most recent moment we observed any activity (CPU or transcript). Used by the
    /// sticky-hold logic so brief signal drops don't release sleep mid-turn.
    @Published private(set) var lastActivityAt: Date?

    @Published var launchAtLogin: Bool = LoginItem.isEnabled {
        didSet {
            guard !updatingLaunchAtLoginFromSystem else { return }
            guard launchAtLogin != LoginItem.isEnabled else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }
    @Published var launchAtLoginNeedsApproval: Bool = LoginItem.requiresApproval
    @Published var launchAtLoginError: String?

    private let power: PowerManaging
    private let agents = AgentMonitor()
    private let lid: LidGuarding
    private let logWatcher = LogActivityWatcher()
    private var endTimer: Timer?
    private var tickTimer: Timer?
    private var stateRefreshTimer: Timer?
    private var statusNoticeTimer: Timer?
    private var updatingLaunchAtLoginFromSystem = false

    /// Reentrancy guard for any privileged lid action (install, uninstall, fallback
    /// admin prompt). Modal AppleScript dialogs run off the main thread; this flag
    /// keeps the UI from spawning a second prompt on top of an open one.
    @Published private(set) var lidActionInFlight = false

    /// True when WE engaged pmset disablesleep (vs. it being on for some external reason).
    /// Used to scope the auto-release: we only restore lid sleep that we set ourselves.
    private var weEngagedLidGuard = false

    init(
        power: PowerManaging = PowerManager(),
        lid: LidGuarding = LidGuard(),
        startServices: Bool = true
    ) {
        self.power = power
        self.lid = lid
        // Default: every tool enabled. Persisted choice (made in onboarding
        // or More) overrides; new tools added in future builds will appear
        // disabled for existing users until they opt in.
        self.enabledTools = AgentToolStore.load() ?? Set(AgentTool.allCases)
        // Seed install status synchronously. The probe is two `sudo -n -l` calls
        // (or a noop in the mock) — fast enough that paying the cost up-front beats
        // a brief UI flash showing "not installed" on real launches.
        let status = lid.installationStatus()
        self.lidInstallStatus = status
        // Migration: earlier app versions let `lidGuardEnabled` be true without
        // a sudoers rule. With the new model, auto-paths never prompt, so a
        // stale `true` would silently do nothing — and worse, the previous
        // build popped a password prompt on every Awake toggle. Reset it so
        // the user re-enables explicitly and gets the install flow.
        let stored = UserDefaults.standard.bool(forKey: Self.lidGuardKey)
        let initial = (status == .installed) ? stored : false
        self.lidGuardEnabled = initial
        // didSet doesn't fire on the first assignment, so persist explicitly
        // when migration corrected the stored value.
        if stored != initial {
            UserDefaults.standard.set(initial, forKey: Self.lidGuardKey)
        }
        guard startServices else { return }
        startBackgroundServices()
    }

    // MARK: - Derived state

    /// Active agents (filtered by CPU / child-process activity probe).
    var activeAgents: [DetectedAgent] {
        detectedAgents.filter { $0.isActive }
    }

    /// Agent sources whose transcript was written recently — used for sleep decisions
    /// (long window, conservative).
    var logActiveSources: [LogActivityWatcher.Source] {
        let cutoff = Date().addingTimeInterval(-Self.logActivityHoldWindow)
        return lastLogActivity.compactMap { src, t in t > cutoff ? src : nil }
    }

    /// Agent sources whose transcript was written in the very recent past — used for
    /// the menu's "in turn" badge so the UI clears within seconds of a turn ending.
    var inTurnLogSources: [LogActivityWatcher.Source] {
        let cutoff = Date().addingTimeInterval(-Self.inTurnDisplayWindow)
        return lastLogActivity.compactMap { src, t in t > cutoff ? src : nil }
    }

    /// Raw signal: at this exact instant, do we have CPU or recent transcript activity?
    var anyAgentRightNow: Bool { !activeAgents.isEmpty || !logActiveSources.isEmpty }

    /// Sticky version: true if raw signal fired within the sticky hold window.
    /// This prevents a brief gap between Bash tool_use and tool_result from releasing sleep.
    var anyAgentDetected: Bool {
        if anyAgentRightNow { return true }
        guard let last = lastActivityAt else { return false }
        return Date().timeIntervalSince(last) < Self.activityStickyHold
    }

    /// The agent-wait branch only fires when the user has opted in.
    var agentDriven: Bool { waitForAgents && anyAgentDetected }

    var isCaffeinated: Bool { manualActive || agentDriven }

    var menuBarIconName: String {
        isCaffeinated ? "cup.and.saucer.fill" : "cup.and.saucer"
    }

    /// Brand names of agents that are CURRENTLY in-turn — uses the short display
    /// window so the menu drops "in turn" within ~6s of a turn ending.
    var detectedBrands: [String] {
        var brands = Set<String>()
        for a in activeAgents {
            brands.insert(a.kind.tool.brandLabel)
        }
        for s in inTurnLogSources {
            brands.insert(s.displayName)
        }
        return brands.sorted()
    }

    /// Brand names of all detected agent sessions, regardless of whether they're
    /// currently in-turn. Lets the UI show "Claude session open" for honesty.
    var allSessionBrands: [String] {
        var brands = Set<String>()
        for a in detectedAgents {
            brands.insert(a.kind.tool.brandLabel)
        }
        return brands.sorted()
    }

    /// Per-brand status pairs for compact display: ("Claude", "in turn"), ("Codex", "idle").
    var brandStatuses: [(brand: String, state: String, isActive: Bool)] {
        let active = Set(detectedBrands)
        let all = allSessionBrands
        return all.map { brand in
            let isActive = active.contains(brand)
            return (brand, isActive ? "in turn" : "idle", isActive)
        }
    }

    /// One-line status under the Awake header. Lists every independent reason the Mac
    /// won't sleep — they OR together, so the Mac stays awake while ANY is true.
    var activeUntilText: String? {
        var reasons: [String] = []
        if manualActive {
            if let end = manualEndDate {
                let f = DateFormatter()
                f.timeStyle = .short
                reasons.append(f.string(from: end))
            } else {
                reasons.append("you turn it off")
            }
        }
        if agentDriven {
            let brands = detectedBrands
            if !brands.isEmpty {
                reasons.append("\(brands.joined(separator: " and ")) finishes")
            } else {
                reasons.append("current agent finishes")
            }
        }
        guard !reasons.isEmpty else { return nil }
        // Join with "or" — sleep waits for whichever takes longer; both contribute.
        let joined: String
        switch reasons.count {
        case 1: joined = reasons[0]
        case 2: joined = "\(reasons[0]) or \(reasons[1])"
        default:
            let head = reasons.dropLast().joined(separator: ", ")
            joined = "\(head), or \(reasons.last!)"
        }
        return "Mac won't sleep until \(joined)"
    }

    var lidPasswordlessReady: Bool { lidInstallStatus == .installed }

    // MARK: - Actions

    private func startBackgroundServices() {
        agents.enabledTools = enabledTools
        logWatcher.enabledTools = enabledTools
        agents.onUpdate = { [weak self] list in
            Task { @MainActor in self?.handleAgents(list) }
        }
        agents.start()

        logWatcher.onActivity = { [weak self] source in
            Task { @MainActor in
                guard let self else { return }
                let now = Date()
                self.lastLogActivity[source] = now
                self.lastActivityAt = now
                self.sync()
            }
        }
        logWatcher.start()

        refreshLidState()

        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.manualEndDate != nil
                    || self.waitForAgents
                    || self.isCaffeinated else { return }
                self.objectWillChange.send()
                self.sync()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t

        let stateTimer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshExternalState() }
        }
        RunLoop.main.add(stateTimer, forMode: .common)
        stateRefreshTimer = stateTimer

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prepareForTermination()
            }
        }

        // First-launch onboarding: offer lid-setup, then the AI tool picker.
        // Each is gated by its own UserDefaults flag so we never re-prompt.
        if !hasOfferedLidSetup || !hasOfferedToolPicker {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                Task { @MainActor in self?.showFirstRunSetupPrompt() }
            }
        }
    }

    private func showFirstRunSetupPrompt() {
        if !hasOfferedLidSetup {
            hasOfferedLidSetup = true
            if lidInstallStatus != .installed {
                runLidSetupAlert()
            }
        }
        if !hasOfferedToolPicker {
            hasOfferedToolPicker = true
            runToolPickerAlert()
        }
    }

    private func runLidSetupAlert() {
        let alert = NSAlert()
        alert.messageText = "Set up passwordless lid-close sleep?"
        alert.informativeText = """
        Awake can keep your Mac running with the lid closed, but macOS asks for your admin password every time the toggle changes.

        With a one-time setup, Awake installs a narrow rule at /etc/sudoers.d/awake so it can flip the lid-close override silently from then on. You can revoke access anytime from More.

        Skip this and you can do it later from More.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Set Up Now")
        alert.addButton(withTitle: "Maybe Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            userInstallPasswordlessLid()
        }
    }

    private func runToolPickerAlert() {
        let alert = NSAlert()
        alert.messageText = "Which AI coding tools do you use?"
        alert.informativeText = "Awake will keep your Mac awake while these tools are working. You can change this anytime in More."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Skip")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        var checkboxes: [(AgentTool, NSButton)] = []
        for tool in AgentTool.allCases {
            let btn = NSButton(checkboxWithTitle: tool.displayName, target: nil, action: nil)
            btn.state = enabledTools.contains(tool) ? .on : .off
            stack.addArrangedSubview(btn)
            checkboxes.append((tool, btn))
        }
        // Width tweak so all checkbox labels render comfortably.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 110))
        stack.frame = container.bounds
        container.addSubview(stack)
        alert.accessoryView = container

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        var next = Set<AgentTool>()
        for (tool, btn) in checkboxes where btn.state == .on {
            next.insert(tool)
        }
        enabledTools = next
    }

    /// User clicked the main "Awake" toggle. ON = engage manual. OFF = release manual,
    /// AND also turn off agent-wait so the user actually gets what they asked for
    /// (otherwise turning off would silently re-engage on the next agent activity).
    func userToggleAwake(on: Bool) {
        if on {
            startManual()
        } else {
            manualActive = false
            manualEndDate = nil
            endTimer?.invalidate(); endTimer = nil
            if waitForAgents {
                waitForAgents = false
                setStatusNotice("Agent waiting turned off.")
            } else {
                sync()
            }
        }
    }

    func startManual() {
        manualActive = true
        applySelectedDuration(restartTimer: true)
        sync()
    }

    func stopManual() {
        manualActive = false
        manualEndDate = nil
        endTimer?.invalidate(); endTimer = nil
        sync()
    }

    /// Trigger immediate state refreshes used when the menu or settings window opens.
    func refreshForPresentation() {
        agents.scanNow()
        refreshExternalState()
    }

    func requestQuit() {
        refreshLaunchAtLogin()
        let lidRef = lid
        DispatchQueue.global(qos: .utility).async {
            let cur = lidRef.currentlyDisabled()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.disablesleepActive != cur {
                    self.disablesleepActive = cur
                }
                if cur {
                    let alert = NSAlert()
                    alert.messageText = "Lid-close sleep is disabled"
                    alert.informativeText = "Restore lid sleep from More before quitting if you want your Mac to sleep normally when the lid closes."
                    alert.addButton(withTitle: "Quit Anyway")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() != .alertFirstButtonReturn { return }
                }
                NSApp.terminate(nil)
            }
        }
    }

    func clearStatusNotice() {
        statusNoticeTimer?.invalidate()
        statusNoticeTimer = nil
        statusNotice = nil
    }

    func clearLidSetupError() {
        lidSetupError = nil
    }

    private func applySelectedDuration(restartTimer: Bool) {
        if restartTimer { endTimer?.invalidate(); endTimer = nil }
        if let secs = selectedDuration.seconds {
            manualEndDate = Date().addingTimeInterval(secs)
            if restartTimer {
                let t = Timer(timeInterval: secs, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.timerExpired() }
                }
                RunLoop.main.add(t, forMode: .common)
                endTimer = t
            }
        } else {
            manualEndDate = nil
        }
    }

    func timerExpired() {
        let expiredDuration = selectedDuration.totalMinutes
        manualActive = false
        manualEndDate = nil
        endTimer = nil
        if expiredDuration > 0 {
            lastTimerMinutes = expiredDuration
        }
        selectedDuration = .indefinite
        sync()
    }

    private func handleAgents(_ list: [DetectedAgent]) {
        detectedAgents = list
        if anyAgentRightNow { lastActivityAt = Date() }
        sync()
    }

    // MARK: - Lid guard install / toggle

    /// User flipped the "Stay awake with lid closed" toggle. If passwordless setup
    /// hasn't been done yet, runs the one-time install first; on cancel/failure the
    /// toggle stays OFF and an error is surfaced.
    func userToggleLidGuard(on: Bool) {
        if on {
            if lidInstallStatus == .installed {
                lidGuardEnabled = true
                return
            }
            beginLidInstall(thenEnable: true)
        } else {
            lidGuardEnabled = false
        }
    }

    /// Triggered from the More window. Always tries the install regardless of
    /// current state; useful if the user previously revoked or the rule was wiped
    /// outside the app.
    func userInstallPasswordlessLid() {
        beginLidInstall(thenEnable: false)
    }

    /// Removes the sudoers rule. Disengages the lid override first if we engaged it,
    /// since we're about to lose the silent path for it.
    func userRevokePasswordlessLid() {
        guard !lidActionInFlight else { return }
        lidActionInFlight = true
        lidSetupError = nil
        if lidGuardEnabled { lidGuardEnabled = false }
        let lidRef = lid
        DispatchQueue.global(qos: .userInitiated).async {
            // Try to release the override first if it's currently active.
            // After uninstall the silent path is gone, so do it while we still
            // have it. allowPrompt:false keeps revoke from chaining into a
            // surprise prompt — if release fails, the state is just stale and
            // the user can use Restore Lid Sleep afterwards.
            let wasDisabled = lidRef.currentlyDisabled()
            if wasDisabled { _ = lidRef.setDisabled(false, allowPrompt: false) }
            let result = lidRef.uninstall()
            let status = lidRef.installationStatus()
            let nowDisabled = lidRef.currentlyDisabled()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lidActionInFlight = false
                self.lidInstallStatus = status
                self.disablesleepActive = nowDisabled
                if !nowDisabled { self.weEngagedLidGuard = false }
                switch result {
                case .success:
                    self.setStatusNotice("Passwordless access revoked.")
                case .failure(.userCancelled):
                    break
                case .failure(let err):
                    self.lidSetupError = Self.describe(err)
                }
            }
        }
    }

    private func beginLidInstall(thenEnable: Bool) {
        guard !lidActionInFlight else { return }
        lidActionInFlight = true
        lidSetupError = nil
        let lidRef = lid
        DispatchQueue.global(qos: .userInitiated).async {
            let result = lidRef.install()
            let status = lidRef.installationStatus()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lidActionInFlight = false
                self.lidInstallStatus = status
                switch result {
                case .success:
                    // installationStatus() is now file-existence based, so a
                    // successful install always flips status to .installed.
                    if thenEnable { self.lidGuardEnabled = true }
                    self.setStatusNotice("Passwordless lid sleep ready.")
                case .failure(.userCancelled):
                    // The Toggle binding visually flipped ON when the user
                    // tapped it. The install was cancelled so the underlying
                    // value is still false, but the Toggle is mid-animation
                    // and won't reset without a binding-source value event.
                    // Re-assigning `lidGuardEnabled = false` triggers
                    // @Published willSet → objectWillChange → SwiftUI
                    // re-reads → Toggle snaps back to OFF, and the next tap
                    // is interpreted as "turn ON" so the prompt re-appears.
                    self.lidGuardEnabled = false
                case .failure(let err):
                    self.lidSetupError = Self.describe(err)
                }
            }
        }
    }

    private static func describe(_ err: LidActionError) -> String {
        switch err {
        case .userCancelled:
            return "Setup canceled."
        case .unsupportedUsername(let u):
            return "Username '\(u)' contains characters Awake refuses to splice into a sudoers rule."
        case .temporaryFileFailed(let m):
            return "Could not stage the install file: \(m)"
        case .privilegedShellFailed(_, let m):
            return "Privileged step failed: \(m)"
        }
    }

    // MARK: - Sync power state

    private func sync() {
        if isCaffeinated {
            let ok = power.assert(preventDisplaySleep: preventDisplaySleep)
            powerAssertionError = ok ? nil : power.lastError
            if lidGuardEnabled {
                maybeEngageLidGuard()
            } else {
                maybeAutoReleaseLidGuard()
            }
        } else {
            let ok = power.release()
            powerAssertionError = ok ? nil : power.lastError
            maybeAutoReleaseLidGuard()
        }
    }

    private func prepareForTermination() {
        power.release()
    }

    private func refreshExternalState() {
        refreshLaunchAtLogin()
        refreshLidState()
    }

    private func refreshLidState() {
        let lidRef = lid
        DispatchQueue.global(qos: .utility).async {
            let cur = lidRef.currentlyDisabled()
            let status = lidRef.installationStatus()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.disablesleepActive != cur {
                    self.disablesleepActive = cur
                }
                if self.lidInstallStatus != status {
                    self.lidInstallStatus = status
                }
            }
        }
    }

    private func refreshLaunchAtLogin() {
        let enabled = LoginItem.isEnabled
        if launchAtLogin != enabled {
            updatingLaunchAtLoginFromSystem = true
            launchAtLogin = enabled
            updatingLaunchAtLoginFromSystem = false
        }
        launchAtLoginNeedsApproval = LoginItem.requiresApproval
        if !launchAtLoginNeedsApproval { launchAtLoginError = nil }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        let ok = LoginItem.setEnabled(enabled)
        refreshLaunchAtLogin()
        if launchAtLoginNeedsApproval { return }
        if !ok || launchAtLogin != enabled {
            launchAtLoginError = "Could not update Login Items."
        }
    }

    private func setStatusNotice(_ text: String) {
        statusNoticeTimer?.invalidate()
        statusNotice = text
        let timer = Timer(timeInterval: 10.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.clearStatusNotice() }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusNoticeTimer = timer
    }

    /// Auto-release the pmset override when nothing is keeping the Mac awake AND we
    /// were the ones who engaged it. Strictly silent — bails if sudoers isn't
    /// installed. The user can manually restore via the Restore Lid Sleep button.
    private func maybeAutoReleaseLidGuard() {
        guard disablesleepActive, weEngagedLidGuard, !lidActionInFlight else { return }
        guard lidInstallStatus == .installed else { return }

        lidActionInFlight = true
        let lidRef = lid
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = lidRef.setDisabled(false, allowPrompt: false)
            let current = ok ? false : lidRef.currentlyDisabled()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lidActionInFlight = false
                if ok {
                    self.disablesleepActive = false
                    self.weEngagedLidGuard = false
                } else {
                    self.disablesleepActive = current
                    self.setStatusNotice("Restore lid sleep from More.")
                }
            }
        }
    }

    /// Engage the override when the user has the lid feature on AND we're keeping
    /// the Mac awake. Strictly silent — bails if sudoers isn't installed. The
    /// user-toggle path triggers install before it ever gets here, so reaching
    /// the unguarded branch means external state changed (rule was revoked
    /// outside the app); we just don't engage and let the toggle reset.
    private func maybeEngageLidGuard() {
        guard isCaffeinated, lidGuardEnabled else { return }
        guard !disablesleepActive else { return }
        guard !lidActionInFlight else { return }
        guard lidInstallStatus == .installed else {
            lidGuardEnabled = false
            return
        }

        lidActionInFlight = true
        let lidRef = lid
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = lidRef.setDisabled(true, allowPrompt: false)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lidActionInFlight = false
                if ok {
                    self.disablesleepActive = true
                    self.weEngagedLidGuard = true
                }
            }
        }
    }

    /// Explicit "Restore Lid Sleep" emergency button. Allows the AppleScript
    /// fallback so the user can recover even if sudoers isn't installed yet.
    func userRestoreLidSleep() {
        guard !lidActionInFlight else { return }
        lidActionInFlight = true
        if lidGuardEnabled {
            lidGuardEnabled = false
        }
        let lidRef = lid
        DispatchQueue.global(qos: .userInitiated).async {
            let currentlyDisabled = lidRef.currentlyDisabled()
            guard currentlyDisabled else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.lidActionInFlight = false
                    self.disablesleepActive = false
                    self.weEngagedLidGuard = false
                    self.setStatusNotice("Lid sleep is already normal.")
                }
                return
            }

            let ok = lidRef.setDisabled(false, allowPrompt: true)
            let current = ok ? false : lidRef.currentlyDisabled()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lidActionInFlight = false
                if ok {
                    self.disablesleepActive = false
                    self.weEngagedLidGuard = false
                    self.setStatusNotice("Lid sleep restored.")
                } else {
                    self.disablesleepActive = current
                }
            }
        }
    }
}
