import Foundation

protocol PowerStatusReading: Sendable {
    func read() -> PowerStatus
}

struct PowerStatus: Equatable, Sendable {
    var sleepDisabled: Bool? = nil
    var lowPowerMode: Bool? = nil
    var systemSleepMinutes: Int? = nil
    var displaySleepMinutes: Int? = nil
    var preventUserIdleSystemSleep: Bool? = nil
    var preventUserIdleDisplaySleep: Bool? = nil
    var preventSystemSleep: Bool? = nil
    var error: String? = nil

    static let unknown = PowerStatus(error: "Power status has not loaded yet.")
}

struct PowerStatusReader: PowerStatusReading, Sendable {
    func read() -> PowerStatus {
        let pmset = Self.run("/usr/bin/pmset", ["-g"])
        let assertions = Self.run("/usr/bin/pmset", ["-g", "assertions"])

        guard pmset.output != nil || assertions.output != nil else {
            return PowerStatus(
                error: [pmset.error, assertions.error]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            )
        }

        var status = PowerStatus.parse(
            pmset: pmset.output ?? "",
            assertions: assertions.output ?? ""
        )
        if let error = pmset.error ?? assertions.error {
            status.error = error
        }
        return status
    }

    static func run(_ path: String, _ arguments: [String]) -> (output: String?, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return (nil, error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: outputData, encoding: .utf8)
        let stderr = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus == 0 {
            return (output, nil)
        }

        return (
            output?.isEmpty == false ? output : nil,
            stderr?.isEmpty == false
                ? stderr
                : "\(path) exited with status \(process.terminationStatus)"
        )
    }
}

extension PowerStatus {
    static func parse(pmset: String, assertions: String) -> PowerStatus {
        PowerStatus(
            sleepDisabled: boolValue(named: "SleepDisabled", in: pmset),
            lowPowerMode: boolValue(named: "lowpowermode", in: pmset),
            systemSleepMinutes: intValue(named: "sleep", in: pmset),
            displaySleepMinutes: intValue(named: "displaysleep", in: pmset),
            preventUserIdleSystemSleep: boolValue(
                named: "PreventUserIdleSystemSleep",
                in: assertions
            ),
            preventUserIdleDisplaySleep: boolValue(
                named: "PreventUserIdleDisplaySleep",
                in: assertions
            ),
            preventSystemSleep: boolValue(named: "PreventSystemSleep", in: assertions)
        )
    }

    private static func boolValue(named key: String, in text: String) -> Bool? {
        guard let value = intValue(named: key, in: text) else { return nil }
        return value != 0
    }

    private static func intValue(named key: String, in text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, parts[0].caseInsensitiveCompare(key) == .orderedSame else {
                continue
            }
            guard let value = Int(parts[1]) else { continue }
            return value
        }
        return nil
    }
}
