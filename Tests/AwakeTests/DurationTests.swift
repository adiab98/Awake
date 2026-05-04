import XCTest
@testable import Awake

final class DurationTests: XCTestCase {
    func testIndefiniteHasNoTimerValue() {
        XCTAssertEqual(Duration.indefinite.totalMinutes, 0)
        XCTAssertNil(Duration.indefinite.seconds)
        XCTAssertEqual(Duration.indefinite.menuLabel, "No timer")
    }

    func testMinutesConvertToSeconds() {
        let duration = Duration.minutes(45)

        XCTAssertEqual(duration.totalMinutes, 45)
        XCTAssertEqual(duration.seconds, 2700)
        XCTAssertEqual(duration.menuLabel, "45 minutes")
    }

    func testHoursConvertToMinutesAndSeconds() {
        let duration = Duration.hours(4)

        XCTAssertEqual(duration.totalMinutes, 240)
        XCTAssertEqual(duration.seconds, 14400)
        XCTAssertEqual(duration.menuLabel, "4 hours")
    }

    func testInvalidMinuteInputMapsToIndefinite() {
        XCTAssertEqual(Duration.from(minutes: 0), .indefinite)
        XCTAssertEqual(Duration.from(minutes: -5), .indefinite)
    }
}
