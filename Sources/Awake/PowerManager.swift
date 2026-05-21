import Foundation
import IOKit.ps
import IOKit.pwr_mgt

protocol PowerManaging: AnyObject {
    var lastError: String? { get }
    @discardableResult
    func assert(preventDisplaySleep: Bool) -> Bool
    @discardableResult
    func release() -> Bool
}

protocol PowerSafetyMonitoring: AnyObject {
    var isExternalPowerConnected: Bool { get }
    var thermalState: ProcessInfo.ThermalState { get }
}

final class PowerSafetyMonitor: PowerSafetyMonitoring {
    var isExternalPowerConnected: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?
                .takeRetainedValue() as? String else {
            return false
        }
        return source == kIOPSACPowerValue
    }

    var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }
}

final class PowerManager: PowerManaging {
    private var idleSystemAssertion: IOPMAssertionID = 0
    private var idleDisplayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var holding = false
    private(set) var lastError: String?

    @discardableResult
    func assert(preventDisplaySleep: Bool) -> Bool {
        lastError = nil
        if holding {
            // Adjust display assertion to match current setting
            if preventDisplaySleep && idleDisplayAssertion == 0 {
                let ok = createAssertion(
                    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    reason: "Awake - preventing display sleep",
                    &idleDisplayAssertion
                )
                return ok
            } else if !preventDisplaySleep && idleDisplayAssertion != 0 {
                let ok = releaseAssertion(idleDisplayAssertion, reason: "display sleep")
                idleDisplayAssertion = 0
                return ok
            }
            return true
        }

        let idleOK = createAssertion(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            reason: "Awake - preventing idle system sleep",
            &idleSystemAssertion
        )

        let systemOK = createAssertion(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            reason: "Awake - preventing forced system sleep",
            &systemAssertion
        )

        var displayOK = true
        if preventDisplaySleep {
            displayOK = createAssertion(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                reason: "Awake - preventing display sleep",
                &idleDisplayAssertion
            )
        }

        holding = idleSystemAssertion != 0 || systemAssertion != 0 || idleDisplayAssertion != 0
        return idleOK && systemOK && displayOK
    }

    @discardableResult
    func release() -> Bool {
        guard holding else { return true }
        var ok = true
        var errors: [String] = []
        if idleSystemAssertion != 0 {
            ok = releaseAssertion(idleSystemAssertion, reason: "idle system sleep", errors: &errors) && ok
            idleSystemAssertion = 0
        }
        if idleDisplayAssertion != 0 {
            ok = releaseAssertion(idleDisplayAssertion, reason: "display sleep", errors: &errors) && ok
            idleDisplayAssertion = 0
        }
        if systemAssertion != 0 {
            ok = releaseAssertion(systemAssertion, reason: "system sleep", errors: &errors) && ok
            systemAssertion = 0
        }
        if !errors.isEmpty {
            lastError = errors.joined(separator: "; ")
        }
        holding = false
        return ok
    }

    deinit { release() }

    private func createAssertion(_ type: CFString, reason: String, _ id: inout IOPMAssertionID) -> Bool {
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            id = 0
            lastError = "Power assertion failed: \(reason) (\(result))"
            return false
        }
        return true
    }

    private func releaseAssertion(_ id: IOPMAssertionID, reason: String) -> Bool {
        var errors: [String] = []
        return releaseAssertion(id, reason: reason, errors: &errors)
    }

    private func releaseAssertion(_ id: IOPMAssertionID, reason: String, errors: inout [String]) -> Bool {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else {
            let message = "Power assertion release failed: \(reason) (\(result))"
            lastError = message
            errors.append(message)
            return false
        }
        return true
    }
}
