import XCTest
@testable import Awake

final class AgentMonitorTests: XCTestCase {
    // MARK: - process classifier

    func testDoesNotDetectClaudeDesktopShellAsAgent() {
        let command = "/Applications/Claude.app/Contents/MacOS/Claude"

        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.claudeDesktop]))
    }

    func testDetectsClaudeDesktopEmbeddedAgentWhenEnabled() {
        let command = "/Users/ahmed/Library/Application Support/Claude/claude-code/2.1.121/claude.app/Contents/MacOS/claude"

        let candidate = AgentMonitor.candidate(for: command, enabledTools: [.claudeDesktop])

        XCTAssertEqual(candidate?.kind, .claudeApp)
        XCTAssertEqual(candidate?.label, "claude desktop agent")
    }

    func testDoesNotDetectClaudeDesktopWhenOnlyCLIIsEnabled() {
        let command = "/Users/ahmed/Library/Application Support/Claude/claude-code-vm/2.1.121/claude"

        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.claude]))
    }

    func testDoesNotDetectClaudeDesktopHelperAsRootCandidate() {
        let command = "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=renderer"

        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.claudeDesktop]))
    }

    func testDoesNotDetectCodexDesktopShellAsAgent() {
        let command = "/Applications/Codex.app/Contents/MacOS/Codex"

        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.codexDesktop]))
    }

    func testDoesNotDetectCodexDesktopAppServerAsAgentTurnByItself() {
        let command = "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled"

        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.codexDesktop]))
        XCTAssertTrue(AgentMonitor.isCodexDesktopAppServerCommand(command))
    }

    func testDoesNotDetectCodexDesktopWhenOnlyCLIIsEnabled() {
        let command = "/Applications/Codex.app/Contents/MacOS/Codex"

        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.codex]))
    }

    func testDoesNotDetectCodexDesktopHelperAsRootCandidate() {
        let command = "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper --type=renderer"

        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.codexDesktop]))
        XCTAssertFalse(AgentMonitor.isCodexDesktopAgentWorkerCommand(command))
    }

    func testCodexDesktopWorkerClassificationSkipsOnlyUiProcesses() {
        XCTAssertTrue(AgentMonitor.isCodexDesktopAgentWorkerCommand(
            "npm exec xcodebuildmcp@latest mcp"
        ))
        XCTAssertTrue(AgentMonitor.isCodexDesktopAgentWorkerCommand(
            "/Applications/Codex.app/Contents/Resources/node_repl"
        ))
    }

    func testDetectsClaudeAndCodexCLIsSeparatelyFromDesktopApps() {
        XCTAssertEqual(
            AgentMonitor.candidate(for: "/opt/homebrew/bin/claude", enabledTools: [.claude])?.kind,
            .claudeCLI
        )
        XCTAssertEqual(
            AgentMonitor.candidate(for: "/opt/homebrew/bin/codex", enabledTools: [.codex])?.kind,
            .codexCLI
        )
    }

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
