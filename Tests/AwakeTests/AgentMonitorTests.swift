import XCTest
@testable import Awake

final class AgentMonitorTests: XCTestCase {
    // MARK: - remoteIP parser

    func testParsesIPv4Endpoint() {
        let line = "node    1234 ahmed   34u  IPv4 0xabc      0t0  TCP 192.168.1.5:55432->17.253.144.10:443 (ESTABLISHED)"
        XCTAssertEqual(AgentMonitor.remoteIP(from: line), "17.253.144.10")
    }

    func testParsesBracketedIPv6Endpoint() {
        let line = "node    1234 ahmed   34u  IPv6 0xabc      0t0  TCP [fe80::1]:55432->[2606:4700:4400:0:0:0:6810:0]:443 (ESTABLISHED)"
        XCTAssertEqual(
            AgentMonitor.remoteIP(from: line),
            "2606:4700:4400:0:0:0:6810:0"
        )
    }

    func testUnwrapsIPv4MappedIPv6() {
        let line = "node    1234 ahmed   34u  IPv6 0xabc      0t0  TCP [::ffff:192.0.2.1]:55432->[::ffff:17.253.144.10]:443 (ESTABLISHED)"
        XCTAssertEqual(AgentMonitor.remoteIP(from: line), "17.253.144.10")
    }

    func testReturnsNilWhenNoArrow() {
        let line = "node    1234 ahmed   34u  IPv4 0xabc      0t0  TCP *:8080 (LISTEN)"
        XCTAssertNil(AgentMonitor.remoteIP(from: line))
    }

    func testReturnsNilOnUnportedFormatGracefully() {
        XCTAssertNil(AgentMonitor.remoteIP(from: ""))
        XCTAssertNil(AgentMonitor.remoteIP(from: "garbage"))
    }
}
