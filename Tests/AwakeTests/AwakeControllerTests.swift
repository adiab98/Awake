import XCTest
@testable import Awake

@MainActor
final class AwakeControllerTests: XCTestCase {
    /// `@AppStorage` reads/writes the standard NSUserDefaults for the test process.
    /// Without resetting between tests, state leaks across cases and produces
    /// order-dependent failures.
    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in [
            "waitForAgents", "lidGuardEnabledV2", "preventDisplaySleep",
            "lastTimerMinutes", "hasOfferedLidSetup", "enabledAgentTools",
            "didMigrateDesktopAgentToolsV1", "lidLowPowerModeManagedV1",
            "lidLowPowerModeOriginalBatteryV1", "lidLowPowerModeOriginalChargerV1"
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    func testDefaultToolsIncludeDesktopAgentSources() {
        let controller = AwakeController(power: MockPowerManager(), lid: MockLidGuard(), startServices: false)

        XCTAssertTrue(controller.enabledTools.contains(.codexDesktop))
        XCTAssertTrue(controller.enabledTools.contains(.claudeDesktop))
    }

    func testExistingCliToolPreferencesMigrateMatchingDesktopSources() {
        AgentToolStore.save([.codex, .opencode])

        let controller = AwakeController(power: MockPowerManager(), lid: MockLidGuard(), startServices: false)

        XCTAssertTrue(controller.enabledTools.contains(.codex))
        XCTAssertTrue(controller.enabledTools.contains(.codexDesktop))
        XCTAssertTrue(controller.enabledTools.contains(.opencode))
        XCTAssertFalse(controller.enabledTools.contains(.claudeDesktop))
        XCTAssertEqual(AgentToolStore.load() ?? [], controller.enabledTools)
    }

    func testTimerToggleStartsTimedAwakeSession() {
        let power = MockPowerManager()
        let controller = AwakeController(power: power, lid: MockLidGuard(), startServices: false)
        controller.userToggleLidGuard(on: false)
        controller.selectedDuration = .indefinite
        power.reset()

        controller.timerEnabled = true

        XCTAssertTrue(controller.manualActive)
        XCTAssertTrue(controller.isCaffeinated)
        XCTAssertNotNil(controller.manualEndDate)
        XCTAssertTrue(controller.timerEnabled)
        XCTAssertEqual(power.assertCount, 1)
    }

    func testTimerExpiryTurnsOffAwakeAndTimerAndReleasesPower() {
        let power = MockPowerManager()
        let controller = AwakeController(power: power, lid: MockLidGuard(), startServices: false)
        controller.userToggleLidGuard(on: false)
        controller.selectedDuration = .minutes(1)
        controller.startManual()
        power.reset()

        controller.timerExpired()

        XCTAssertFalse(controller.manualActive)
        XCTAssertFalse(controller.isCaffeinated)
        XCTAssertNil(controller.manualEndDate)
        XCTAssertFalse(controller.timerEnabled)
        XCTAssertEqual(controller.selectedDuration, .indefinite)
        XCTAssertEqual(power.releaseCount, 1)
    }

    func testDisablingToolClearsStaleLogActivityAndStickyHold() {
        let power = MockPowerManager()
        let controller = AwakeController(power: power, lid: MockLidGuard(), startServices: false)
        controller.waitForAgents = true
        power.reset()

        controller.handleLogActivity(.codex)
        XCTAssertTrue(controller.agentDriven)
        XCTAssertTrue(controller.logActiveSources.contains(.codex))

        controller.setTool(.codex, enabled: false)

        XCTAssertFalse(controller.logActiveSources.contains(.codex))
        XCTAssertFalse(controller.agentDriven)
        XCTAssertFalse(controller.isCaffeinated)
        XCTAssertEqual(power.releaseCount, 1)
    }

    func testLogOnlyActivityAppearsInBrandStatuses() {
        let controller = AwakeController(power: MockPowerManager(), lid: MockLidGuard(), startServices: false)

        controller.handleLogActivity(.codex)

        XCTAssertTrue(controller.detectedBrands.contains("Codex CLI"))
        XCTAssertTrue(controller.brandStatuses.contains { status in
            status.brand == "Codex CLI" && status.state == "in turn" && status.isActive
        })
    }

    func testDesktopLogActivityAppearsUnderDesktopBrand() {
        let controller = AwakeController(power: MockPowerManager(), lid: MockLidGuard(), startServices: false)
        controller.setTool(.codexDesktop, enabled: true)

        controller.handleLogActivity(.codexDesktop)

        XCTAssertTrue(controller.detectedBrands.contains("Codex Desktop"))
        XCTAssertTrue(controller.brandStatuses.contains { status in
            status.brand == "Codex Desktop" && status.state == "in turn" && status.isActive
        })
    }

    func testDesktopLogActivityExpiresAfterStickyWindow() {
        let power = MockPowerManager()
        let controller = AwakeController(power: power, lid: MockLidGuard(), startServices: false)
        controller.waitForAgents = true
        power.reset()

        let stale = Date().addingTimeInterval(
            -(max(AwakeController.desktopLogActivityHoldWindow, AwakeController.activityStickyHold) + 1)
        )
        controller.handleLogActivity(.codexDesktop, at: stale)

        XCTAssertFalse(controller.logActiveSources.contains(.codexDesktop))
        XCTAssertFalse(controller.agentDriven)
        XCTAssertFalse(controller.isCaffeinated)
        XCTAssertEqual(power.releaseCount, 1)
    }

    func testCliLogActivityKeepsLongerTranscriptHold() {
        let controller = AwakeController(power: MockPowerManager(), lid: MockLidGuard(), startServices: false)
        controller.waitForAgents = true

        let olderThanDesktopHold = Date().addingTimeInterval(
            -(AwakeController.desktopLogActivityHoldWindow + 1)
        )
        controller.handleLogActivity(.codex, at: olderThanDesktopHold)

        XCTAssertTrue(controller.logActiveSources.contains(.codex))
        XCTAssertTrue(controller.agentDriven)
        XCTAssertTrue(controller.isCaffeinated)
    }

    func testRestoreLidSleepDoesNotAskForPasswordWhenAlreadyNormal() async throws {
        let lid = MockLidGuard(currentlyDisabled: false, status: .installed)
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)
        controller.userToggleLidGuard(on: true)

        controller.userRestoreLidSleep()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(controller.lidGuardEnabled)
        XCTAssertFalse(controller.disablesleepActive)
        XCTAssertEqual(lid.setDisabledCalls, 0)
    }

    func testRestoreLidSleepTurnsOffPreferenceAfterRestore() async throws {
        let lid = MockLidGuard(currentlyDisabled: true, status: .installed)
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)
        controller.userToggleLidGuard(on: true)

        controller.userRestoreLidSleep()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(controller.lidGuardEnabled)
        XCTAssertFalse(controller.disablesleepActive)
        XCTAssertEqual(lid.setDisabledCalls, 1)
        XCTAssertEqual(lid.lastSetValue, false)
    }

    func testToggleLidGuardOnRunsInstallWhenNotInstalled() async throws {
        let lid = MockLidGuard(status: .notInstalled)
        lid.installResult = .success(())
        lid.statusAfterInstall = .installed
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)

        controller.userToggleLidGuard(on: true)
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(lid.installCalls, 1)
        XCTAssertTrue(controller.lidGuardEnabled)
        XCTAssertEqual(controller.lidInstallStatus, .installed)
        XCTAssertNil(controller.lidSetupError)
    }

    func testToggleLidGuardOnSkipsInstallWhenAlreadyInstalled() async throws {
        let lid = MockLidGuard(status: .installed)
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)
        // Simulate the controller already learning about the installed state.
        try await Task.sleep(nanoseconds: 50_000_000)
        await Task.yield()

        controller.userToggleLidGuard(on: true)

        XCTAssertEqual(lid.installCalls, 0)
        XCTAssertTrue(controller.lidGuardEnabled)
    }

    func testLidGuardToggleEnablesLowPowerAndRestoresPreviousState() {
        let lid = MockLidGuard(
            status: .installed,
            lowPowerModeState: LowPowerModeState(batteryPower: false, chargerPower: false)
        )
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)

        controller.userToggleLidGuard(on: true)
        XCTAssertTrue(controller.lidGuardEnabled)
        XCTAssertEqual(lid.setLowPowerModeCalls, 1)
        XCTAssertEqual(lid.lastLowPowerModeState, .enabled)

        controller.userToggleLidGuard(on: false)
        XCTAssertFalse(controller.lidGuardEnabled)
        XCTAssertEqual(lid.setLowPowerModeCalls, 2)
        XCTAssertEqual(
            lid.lastLowPowerModeState,
            LowPowerModeState(batteryPower: false, chargerPower: false)
        )
    }

    func testLidGuardToggleLeavesLowPowerOnWhenItWasAlreadyOn() {
        let original = LowPowerModeState(batteryPower: true, chargerPower: true)
        let lid = MockLidGuard(status: .installed, lowPowerModeState: original)
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)

        controller.userToggleLidGuard(on: true)
        controller.userToggleLidGuard(on: false)

        XCTAssertEqual(lid.lastLowPowerModeState, original)
    }

    func testLowPowerFailurePreventsLidGuardEnable() {
        let lid = MockLidGuard(
            status: .installed,
            lowPowerModeState: LowPowerModeState(batteryPower: false, chargerPower: false)
        )
        lid.setLowPowerModeResult = false
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)

        controller.userToggleLidGuard(on: true)

        XCTAssertFalse(controller.lidGuardEnabled)
        XCTAssertEqual(controller.lidInstallStatus, .notInstalled)
        XCTAssertEqual(
            controller.lidSetupError,
            "Passwordless setup needs to be run again for Low Power Mode."
        )
    }

    func testInstallCancellationLeavesToggleOff() async throws {
        let lid = MockLidGuard(status: .notInstalled)
        lid.installResult = .failure(.userCancelled)
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)

        controller.userToggleLidGuard(on: true)
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(controller.lidGuardEnabled)
        XCTAssertEqual(controller.lidInstallStatus, .notInstalled)
        XCTAssertNil(controller.lidSetupError)
    }

    func testStaleLidGuardEnabledIsResetWhenSudoersMissing() {
        UserDefaults.standard.set(true, forKey: "lidGuardEnabledV2")
        let controller = AwakeController(
            power: MockPowerManager(),
            lid: MockLidGuard(status: .notInstalled),
            startServices: false
        )
        XCTAssertFalse(
            controller.lidGuardEnabled,
            "Migration should clear stale lidGuardEnabled when sudoers isn't installed"
        )
    }

    func testStaleLidGuardEnabledIsKeptWhenSudoersInstalled() {
        UserDefaults.standard.set(true, forKey: "lidGuardEnabledV2")
        let lid = MockLidGuard(
            status: .installed,
            lowPowerModeState: LowPowerModeState(batteryPower: false, chargerPower: false)
        )
        let controller = AwakeController(
            power: MockPowerManager(),
            lid: lid,
            startServices: false
        )
        XCTAssertTrue(controller.lidGuardEnabled)
        XCTAssertEqual(lid.setLowPowerModeCalls, 1)
        XCTAssertEqual(lid.lastLowPowerModeState, .enabled)
    }

    func testCaffeinatingDoesNotEngageLidWhenSudoersMissing() async throws {
        let lid = MockLidGuard(status: .notInstalled)
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)
        XCTAssertFalse(controller.lidGuardEnabled)

        // Simulate the user turning the main Awake toggle on. With sudoers
        // not installed, this must NOT trigger any setDisabled call (which
        // would chain into a password prompt in real builds).
        controller.startManual()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(
            lid.setDisabledCalls, 0,
            "Auto-engage must never run when the sudoers rule isn't installed"
        )
    }

    func testFailedSilentLidEngageResetsPasswordlessSetupState() async throws {
        let lid = MockLidGuard(status: .installed)
        lid.setDisabledResult = false
        let controller = AwakeController(
            power: MockPowerManager(),
            safety: MockPowerSafetyMonitor(),
            lid: lid,
            startServices: false
        )
        controller.userToggleLidGuard(on: true)
        XCTAssertTrue(controller.lidGuardEnabled)

        controller.startManual()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(lid.setDisabledCalls, 1)
        XCTAssertFalse(controller.lidGuardEnabled)
        XCTAssertEqual(controller.lidInstallStatus, .notInstalled)
        XCTAssertEqual(controller.lidSetupError, "Passwordless lid setup needs to be run again.")
    }

    func testLidGuardEngagesOnBatteryPowerWithLowPowerMode() async throws {
        let lid = MockLidGuard(status: .installed)
        let safety = MockPowerSafetyMonitor(isExternalPowerConnected: false)
        let controller = AwakeController(
            power: MockPowerManager(),
            safety: safety,
            lid: lid,
            startServices: false
        )
        controller.userToggleLidGuard(on: true)

        controller.startManual()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(controller.lidGuardEnabled)
        XCTAssertTrue(controller.disablesleepActive)
        XCTAssertEqual(lid.setDisabledCalls, 1)
        XCTAssertEqual(lid.lastSetValue, true)
        XCTAssertEqual(lid.setLowPowerModeCalls, 1)
        XCTAssertEqual(lid.lastLowPowerModeState, .enabled)
        XCTAssertNil(controller.lidSafetyMessage)
    }

    func testUnpluggingPowerKeepsLidGuardActive() async throws {
        let lid = MockLidGuard(status: .installed)
        let safety = MockPowerSafetyMonitor()
        let controller = AwakeController(
            power: MockPowerManager(),
            safety: safety,
            lid: lid,
            startServices: false
        )
        controller.userToggleLidGuard(on: true)
        controller.startManual()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(controller.disablesleepActive)

        safety.isExternalPowerConnected = false
        controller.handleSafetyStateChanged()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(controller.disablesleepActive)
        XCTAssertEqual(lid.setDisabledCalls, 1)
        XCTAssertEqual(lid.lastSetValue, true)
        XCTAssertNil(controller.lidSafetyMessage)
    }

    func testBatteryPowerDoesNotReleaseExistingLidOverride() async throws {
        let lid = MockLidGuard(currentlyDisabled: true, status: .installed)
        let safety = MockPowerSafetyMonitor(isExternalPowerConnected: false)
        let controller = AwakeController(
            power: MockPowerManager(),
            safety: safety,
            lid: lid,
            startServices: false
        )
        controller.userToggleLidGuard(on: true)

        controller.refreshForPresentation()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(controller.disablesleepActive)
        XCTAssertEqual(lid.setDisabledCalls, 0)
    }

    func testThermalPressureReleasesStaleLidOverrideEvenWhenPreferenceIsOff() async throws {
        let lid = MockLidGuard(currentlyDisabled: true, status: .installed)
        let safety = MockPowerSafetyMonitor(thermalState: .serious)
        let controller = AwakeController(
            power: MockPowerManager(),
            safety: safety,
            lid: lid,
            startServices: false
        )

        controller.refreshForPresentation()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(controller.lidGuardEnabled)
        XCTAssertFalse(controller.disablesleepActive)
        XCTAssertEqual(lid.setDisabledCalls, 1)
        XCTAssertEqual(lid.lastSetValue, false)
    }

    func testPowerStatusRefreshDoesNotStartOverlappingReads() async throws {
        let reader = BlockingPowerStatusReader()
        let controller = AwakeController(
            power: MockPowerManager(),
            powerStatusReader: reader,
            lid: MockLidGuard(),
            startServices: false
        )

        controller.refreshForPresentation()
        try await waitUntil { reader.readCount == 1 }

        controller.refreshForPresentation()
        controller.refreshForPresentation()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(reader.readCount, 1)

        reader.releaseNext()
        try await waitUntil { controller.powerStatus.sleepDisabled == true }

        controller.refreshForPresentation()
        try await waitUntil { reader.readCount == 2 }
        reader.releaseNext()
    }

    func testThermalPressureStopsAwakeAndRestoresLidSleep() async throws {
        let power = MockPowerManager()
        let lid = MockLidGuard(status: .installed)
        let safety = MockPowerSafetyMonitor()
        let controller = AwakeController(
            power: power,
            safety: safety,
            lid: lid,
            startServices: false
        )
        controller.userToggleLidGuard(on: true)
        controller.startManual()
        try await Task.sleep(nanoseconds: 100_000_000)
        power.reset()
        XCTAssertTrue(controller.isCaffeinated)
        XCTAssertTrue(controller.disablesleepActive)

        safety.thermalState = .serious
        controller.handleSafetyStateChanged()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(controller.manualActive)
        XCTAssertFalse(controller.isCaffeinated)
        XCTAssertFalse(controller.disablesleepActive)
        XCTAssertEqual(power.releaseCount, 1)
        XCTAssertEqual(lid.lastSetValue, false)
        XCTAssertEqual(controller.statusNotice, "Awake turned off because macOS reported high heat.")
    }

    func testRevokeUninstallsAndDisablesPreference() async throws {
        let lid = MockLidGuard(currentlyDisabled: true, status: .installed)
        lid.uninstallResult = .success(())
        lid.statusAfterUninstall = .notInstalled
        let controller = AwakeController(power: MockPowerManager(), lid: lid, startServices: false)
        controller.userToggleLidGuard(on: true)
        try await Task.sleep(nanoseconds: 50_000_000)

        controller.userRevokePasswordlessLid()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(lid.uninstallCalls, 1)
        XCTAssertEqual(controller.lidInstallStatus, .notInstalled)
        XCTAssertFalse(controller.lidGuardEnabled)
    }
}

private func waitUntil(
    timeout: TimeInterval = 1,
    _ condition: @escaping () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("Condition was not met before timeout")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

private final class MockPowerManager: PowerManaging {
    var lastError: String?
    private(set) var assertCount = 0
    private(set) var releaseCount = 0

    func assert(preventDisplaySleep: Bool) -> Bool {
        assertCount += 1
        return true
    }

    func release() -> Bool {
        releaseCount += 1
        return true
    }

    func reset() {
        assertCount = 0
        releaseCount = 0
        lastError = nil
    }
}

private final class MockPowerSafetyMonitor: PowerSafetyMonitoring {
    var isExternalPowerConnected: Bool
    var thermalState: ProcessInfo.ThermalState

    init(
        isExternalPowerConnected: Bool = true,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) {
        self.isExternalPowerConnected = isExternalPowerConnected
        self.thermalState = thermalState
    }
}

private final class MockLidGuard: LidGuarding, @unchecked Sendable {
    private let lock = NSLock()
    private var disabled: Bool
    private var status: LidInstallStatus
    private var lowPowerMode: LowPowerModeState?
    var statusAfterInstall: LidInstallStatus?
    var statusAfterUninstall: LidInstallStatus?
    var installResult: Result<Void, LidActionError> = .success(())
    var uninstallResult: Result<Void, LidActionError> = .success(())
    var setDisabledResult = true
    var setLowPowerModeResult = true
    private(set) var setDisabledCalls = 0
    private(set) var setLowPowerModeCalls = 0
    private(set) var installCalls = 0
    private(set) var uninstallCalls = 0
    private(set) var lastSetValue: Bool?
    private(set) var lastLowPowerModeState: LowPowerModeState?

    init(
        currentlyDisabled: Bool = false,
        status: LidInstallStatus = .installed,
        lowPowerModeState: LowPowerModeState? = .enabled
    ) {
        self.disabled = currentlyDisabled
        self.status = status
        self.lowPowerMode = lowPowerModeState
    }

    func currentlyDisabled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return disabled
    }

    func lowPowerModeState() -> LowPowerModeState? {
        lock.lock(); defer { lock.unlock() }
        return lowPowerMode
    }

    func installationStatus() -> LidInstallStatus {
        lock.lock(); defer { lock.unlock() }
        return status
    }

    func install() -> Result<Void, LidActionError> {
        lock.lock()
        installCalls += 1
        let result = installResult
        if case .success = result, let next = statusAfterInstall {
            status = next
        }
        lock.unlock()
        return result
    }

    func uninstall() -> Result<Void, LidActionError> {
        lock.lock()
        uninstallCalls += 1
        let result = uninstallResult
        if case .success = result, let next = statusAfterUninstall {
            status = next
        }
        lock.unlock()
        return result
    }

    func setDisabled(_ disabled: Bool, allowPrompt: Bool) -> Bool {
        lock.lock()
        setDisabledCalls += 1
        lastSetValue = disabled
        if setDisabledResult {
            self.disabled = disabled
        }
        lock.unlock()
        return setDisabledResult
    }

    func setLowPowerMode(_ state: LowPowerModeState, allowPrompt: Bool) -> Bool {
        lock.lock()
        setLowPowerModeCalls += 1
        lastLowPowerModeState = state
        if setLowPowerModeResult {
            lowPowerMode = state
        }
        lock.unlock()
        return setLowPowerModeResult
    }
}

private final class BlockingPowerStatusReader: PowerStatusReading, @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var reads = 0

    var readCount: Int {
        lock.lock(); defer { lock.unlock() }
        return reads
    }

    func read() -> PowerStatus {
        lock.lock()
        reads += 1
        lock.unlock()
        semaphore.wait()
        return PowerStatus(sleepDisabled: true)
    }

    func releaseNext() {
        semaphore.signal()
    }
}
