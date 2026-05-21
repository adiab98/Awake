import XCTest
@testable import Awake

final class LidGuardTests: XCTestCase {
    // MARK: - Username validator

    func testValidUsernamesAreAccepted() {
        XCTAssertTrue(LidGuard.isValidSudoUsername("ahmed"))
        XCTAssertTrue(LidGuard.isValidSudoUsername("alice_42"))
        XCTAssertTrue(LidGuard.isValidSudoUsername("Bob-Smith"))
        XCTAssertTrue(LidGuard.isValidSudoUsername("a"))
        XCTAssertTrue(LidGuard.isValidSudoUsername(String(repeating: "a", count: 64)))
        XCTAssertTrue(LidGuard.isValidSudoUsername("user.name"))
    }

    func testEmptyOrOversizedUsernamesAreRefused() {
        XCTAssertFalse(LidGuard.isValidSudoUsername(""))
        XCTAssertFalse(LidGuard.isValidSudoUsername(String(repeating: "a", count: 65)))
    }

    func testUsernamesWithShellMetacharactersAreRefused() {
        // Anything that could change the meaning of a sudoers line if naively spliced.
        let hostile = [
            "user space",
            "user\nALL=(ALL)",
            "user\tname",
            "user;rm -rf",
            "user\"quote",
            "user\\backslash",
            "user'quote",
            "user`bt`",
            "user$(cmd)",
            "user&bg",
            "user|pipe",
            "user>redir",
            "user<redir",
            "user#comment",
            "user!neg",
            "user%admin",
            "user(x)",
        ]
        for name in hostile {
            XCTAssertFalse(
                LidGuard.isValidSudoUsername(name),
                "Should refuse hostile username: \(name.debugDescription)"
            )
        }
    }

    // MARK: - Sudoers body

    func testSudoersContentSplicesUsernameAndPmsetCommands() {
        let body = LidGuard.sudoersContent(forUser: "alice")
        XCTAssertTrue(body.contains("alice ALL=(root:wheel) NOPASSWD: \(LidGuard.pmsetPath) -a disablesleep 0"))
        XCTAssertTrue(body.contains("alice ALL=(root:wheel) NOPASSWD: \(LidGuard.pmsetPath) -a disablesleep 1"))
        XCTAssertTrue(body.contains("alice ALL=(root:wheel) NOPASSWD: \(LidGuard.pmsetPath) -b lowpowermode 0"))
        XCTAssertTrue(body.contains("alice ALL=(root:wheel) NOPASSWD: \(LidGuard.pmsetPath) -b lowpowermode 1"))
        XCTAssertTrue(body.contains("alice ALL=(root:wheel) NOPASSWD: \(LidGuard.pmsetPath) -c lowpowermode 0"))
        XCTAssertTrue(body.contains("alice ALL=(root:wheel) NOPASSWD: \(LidGuard.pmsetPath) -c lowpowermode 1"))
    }

    func testSudoersContentEndsWithNewlineSoVisudoIsHappy() {
        let body = LidGuard.sudoersContent(forUser: "alice")
        XCTAssertTrue(body.hasSuffix("\n"), "sudoers files must end with a newline")
    }

    func testSudoersContentStaysAscii() {
        let body = LidGuard.sudoersContent(forUser: "alice")
        XCTAssertTrue(
            body.unicodeScalars.allSatisfy { $0.isASCII },
            "Comments should be ASCII to avoid locale/encoding edge cases"
        )
    }

    func testSudoersContentGrantsOnlyExactCommands() {
        let body = LidGuard.sudoersContent(forUser: "alice")
        let nopasswdLines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.contains("NOPASSWD:") }
        XCTAssertEqual(nopasswdLines.count, 6, "Rule must grant only the expected commands")
        for line in nopasswdLines {
            XCTAssertTrue(line.contains(LidGuard.pmsetPath))
            XCTAssertFalse(line.contains("*"), "No wildcards allowed in granted commands")
        }
    }

    func testSudoListingAcceptsExactPasswordlessPmsetCommands() {
        let listing = """
        Matching Defaults entries for alice on Mac:
            env_reset

        User alice may run the following commands on Mac:
            (ALL) ALL
            (root : wheel) NOPASSWD: /usr/bin/pmset -a disablesleep 0
            (root : wheel) NOPASSWD: /usr/bin/pmset -a disablesleep 1
            (root : wheel) NOPASSWD: /usr/bin/pmset -b lowpowermode 0
            (root : wheel) NOPASSWD: /usr/bin/pmset -b lowpowermode 1
            (root : wheel) NOPASSWD: /usr/bin/pmset -c lowpowermode 0
            (root : wheel) NOPASSWD: /usr/bin/pmset -c lowpowermode 1
        """

        XCTAssertTrue(LidGuard.sudoListShowsPasswordlessPmsetCommands(listing))
    }

    func testSudoListingRejectsPasswordProtectedBroadAccess() {
        let listing = """
        User alice may run the following commands on Mac:
            (ALL) ALL
        """

        XCTAssertFalse(LidGuard.sudoListShowsPasswordlessPmsetCommands(listing))
    }

    func testSudoListingRejectsMissingPmsetCommand() {
        let listing = """
        User alice may run the following commands on Mac:
            (root : wheel) NOPASSWD: /usr/bin/pmset -a disablesleep 0
            (root : wheel) NOPASSWD: /usr/bin/pmset -a disablesleep 1
        """

        XCTAssertFalse(LidGuard.sudoListShowsPasswordlessPmsetCommands(listing))
    }

    func testParseLowPowerModeStateReadsBatteryAndChargerValues() {
        let output = """
        Battery Power:
         Sleep On Power Button 1
         lowpowermode         0
        AC Power:
         Sleep On Power Button 1
         lowpowermode         1
        """

        XCTAssertEqual(
            LidGuard.parseLowPowerModeState(output),
            LowPowerModeState(batteryPower: false, chargerPower: true)
        )
    }

    func testLowPowerModeCommandsRestoreKnownProfilesOnly() {
        XCTAssertEqual(
            LidGuard.lowPowerModeCommands(
                for: LowPowerModeState(batteryPower: false, chargerPower: true)
            ),
            [
                ["-b", "lowpowermode", "0"],
                ["-c", "lowpowermode", "1"],
            ]
        )
        XCTAssertEqual(
            LidGuard.lowPowerModeCommands(
                for: LowPowerModeState(batteryPower: nil, chargerPower: false)
            ),
            [["-c", "lowpowermode", "0"]]
        )
    }

    /// Pipes the generated body through `visudo -c -f -` to confirm it parses.
    /// Skips on hosts where visudo isn't installed (CI runners without /usr/sbin).
    func testSudoersContentPassesVisudoCheck() throws {
        let visudo = LidGuard.visudoPath
        guard FileManager.default.isExecutableFile(atPath: visudo) else {
            throw XCTSkip("visudo not present at \(visudo)")
        }
        let body = LidGuard.sudoersContent(forUser: "alice")
        let tmp = NSTemporaryDirectory().appending("awake-sudoers-test-\(UUID().uuidString)")
        try body.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: visudo)
        p.arguments = ["-c", "-f", tmp]
        let out = Pipe(); p.standardOutput = out
        let err = Pipe(); p.standardError = err
        try p.run()
        _ = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        XCTAssertEqual(
            p.terminationStatus, 0,
            "visudo rejected our generated sudoers body: \(String(data: errData, encoding: .utf8) ?? "")"
        )
    }

    // MARK: - AppleScript escape

    func testAppleScriptEscapeQuotesAndBackslashes() {
        XCTAssertEqual(LidGuard.appleScriptEscape("plain text"), "plain text")
        XCTAssertEqual(LidGuard.appleScriptEscape("with \"quotes\""), #"with \"quotes\""#)
        XCTAssertEqual(LidGuard.appleScriptEscape(#"a\b"#), #"a\\b"#)
        // Backslashes escape first so quotes after escaping aren't double-mangled.
        XCTAssertEqual(LidGuard.appleScriptEscape(#"\""#), #"\\\""#)
    }
}
