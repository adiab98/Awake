import XCTest
@testable import Awake

final class PowerStatusTests: XCTestCase {
    func testRunDrainsLargeOutputWithoutDeadlocking() {
        let finished = expectation(description: "command finished")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PowerStatusReader.run("/usr/bin/perl", [
                "-e",
                "print \"awake\\n\" x 200000"
            ])
            XCTAssertEqual(result.error, nil)
            XCTAssertTrue(result.output?.hasPrefix("awake\n") == true)
            finished.fulfill()
        }

        wait(for: [finished], timeout: 1)
    }

    func testParsesPmsetAndAssertionValues() {
        let pmset = """
         SleepDisabled\t\t1
         Sleep On Power Button 1
         sleep                1 (sleep prevented by Awake)
         displaysleep         2
         lowpowermode         1
        """
        let assertions = """
        Assertion status system-wide:
           PreventUserIdleDisplaySleep    0
           PreventSystemSleep             1
           PreventUserIdleSystemSleep     1
        """

        let status = PowerStatus.parse(pmset: pmset, assertions: assertions)

        XCTAssertEqual(status.sleepDisabled, true)
        XCTAssertEqual(status.lowPowerMode, true)
        XCTAssertEqual(status.systemSleepMinutes, 1)
        XCTAssertEqual(status.displaySleepMinutes, 2)
        XCTAssertEqual(status.preventUserIdleDisplaySleep, false)
        XCTAssertEqual(status.preventSystemSleep, true)
        XCTAssertEqual(status.preventUserIdleSystemSleep, true)
    }
}
