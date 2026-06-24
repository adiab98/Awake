import XCTest
import CoreServices
import Darwin
@testable import Awake

final class AgentMonitorTests: XCTestCase {
    // MARK: - process classifier

    func testDoesNotDetectClaudeDesktopShellAsAgent() {
        let command = "/Applications/Claude.app/Contents/MacOS/Claude"

        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.claudeDesktop]))
    }

    func testDoesNotDetectClaudeDesktopEmbeddedAgentProcessAsTurn() {
        let command = "/Users/ahmed/Library/Application Support/Claude/claude-code/2.1.121/claude.app/Contents/MacOS/claude"

        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.claudeDesktop]))
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
        XCTAssertNil(AgentMonitor.candidate(for: command, enabledTools: [.codex]))
        XCTAssertTrue(AgentMonitor.isCodexDesktopAppServerCommand(command))
        XCTAssertTrue(AgentMonitor.isCodexDesktopAppServerCommand("codex app-server"))
        XCTAssertNil(AgentMonitor.candidate(for: "codex app-server", enabledTools: [.codex]))
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

    func testCodexDesktopWorkerClassificationSkipsPersistentSupportProcesses() {
        XCTAssertFalse(AgentMonitor.isCodexDesktopAgentWorkerCommand(
            "npm exec xcodebuildmcp@latest mcp"
        ))
        XCTAssertFalse(AgentMonitor.isCodexDesktopAgentWorkerCommand(
            "/Applications/Codex.app/Contents/Resources/node_repl"
        ))
        XCTAssertFalse(AgentMonitor.isCodexDesktopAgentWorkerCommand(
            "/Applications/Codex.app/Contents/Resources/node --experimental-vm-modules /var/folders/tmp/kernel.js --session-id abc --working-dir /Users/ahmed/Documents/Awake"
        ))
        XCTAssertFalse(AgentMonitor.isCodexDesktopAgentWorkerCommand(
            "./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient mcp"
        ))
        XCTAssertFalse(AgentMonitor.isCodexDesktopAgentWorkerCommand(
            "npm exec mcp-remote https://www.lazyweb.com/mcp --transport http-first"
        ))
        XCTAssertFalse(AgentMonitor.isCodexDesktopAgentWorkerCommand(
            "node /Users/ahmed/Documents/production-tracker/scripts/mcp-server.ts"
        ))
        XCTAssertTrue(AgentMonitor.isCodexDesktopAgentWorkerCommand(
            "/bin/zsh -lc swift test"
        ))
    }

    func testCodexActivityOwnersDoNotTreatOpenDesktopAppAsAgentActivity() {
        let ps = """
          100     1   0.0 /Applications/Codex.app/Contents/MacOS/Codex
          101   100   0.0 /Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled
          102   100   0.0 /Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper --type=renderer
        """

        XCTAssertFalse(AgentMonitor.codexActivityOwners(psOutput: ps).contains(.codexDesktop))
        XCTAssertFalse(AgentMonitor.codexActivityOwners(psOutput: ps).contains(.codex))
    }

    func testCodexActivityOwnersDetectDesktopWorkerUnderAppServer() {
        let ps = """
          100     1   0.0 /Applications/Codex.app/Contents/MacOS/Codex
          101   100   0.0 /Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled
          102   101   0.0 /bin/zsh -lc swift test
        """

        XCTAssertEqual(AgentMonitor.codexActivityOwners(psOutput: ps), [.codexDesktop])
    }

    func testCodexActivityOwnersIgnoreIdleDesktopSupportProcesses() {
        let ps = """
          100     1   0.0 /Applications/Codex.app/Contents/MacOS/Codex
          101   100   0.0 /Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled
          102   101   0.0 /Applications/Codex.app/Contents/Resources/node_repl
          103   101   0.0 npm exec xcodebuildmcp@latest mcp
          104   101   0.0 npm exec @upstash/context7-mcp
        """

        XCTAssertFalse(AgentMonitor.codexActivityOwners(psOutput: ps).contains(.codexDesktop))
    }

    func testCodexActivityOwnersUseBusyDesktopAppServerForTranscriptAttribution() {
        let ps = """
          100     1   0.0 /Applications/Codex.app/Contents/MacOS/Codex
          101   100   7.5 /Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled
          102   101   0.0 /Applications/Codex.app/Contents/Resources/node_repl
          103   101   0.0 npm exec xcodebuildmcp@latest mcp
        """

        XCTAssertEqual(AgentMonitor.codexActivityOwners(psOutput: ps), [.codexDesktop])
    }

    func testCodexActivityOwnersIgnoreDesktopPersistentChildren() {
        let ps = """
          100     1   0.0 /Applications/Codex.app/Contents/MacOS/Codex
          101   100   0.0 /Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled
          102   101   0.0 /Applications/Codex.app/Contents/Resources/node_repl
          103   102   0.0 /Applications/Codex.app/Contents/Resources/node --experimental-vm-modules /var/folders/tmp/kernel.js --session-id abc --working-dir /Users/ahmed/Documents/Awake
          104   101   1.2 ./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient mcp
        """

        XCTAssertFalse(AgentMonitor.codexActivityOwners(psOutput: ps).contains(.codexDesktop))
    }

    func testCodexActivityOwnersDetectCliSeparatelyFromDesktop() {
        let ps = """
          100     1   0.0 /Applications/Codex.app/Contents/MacOS/Codex
          101   100   0.0 /Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled
          102   101   0.0 /Applications/Codex.app/Contents/Resources/node_repl
          103   101   0.0 /bin/zsh -lc swift test
          200     1   3.0 /opt/homebrew/bin/codex
        """

        XCTAssertEqual(AgentMonitor.codexActivityOwners(psOutput: ps), [.codex, .codexDesktop])
    }

    func testCodexActivityOwnersIgnoreIdleCliSessionProcess() {
        let ps = """
          200     1   0.0 /opt/homebrew/bin/codex resume 019df43a-e67e-7f70-a879-7c75e2db2928
          201   200   0.0 npm exec @upstash/context7-mcp
        """

        XCTAssertFalse(AgentMonitor.codexActivityOwners(psOutput: ps).contains(.codex))
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

    // MARK: - transcript watcher filters

    func testTranscriptActivityPathIgnoresDirectories() {
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)

        XCTAssertFalse(LogActivityWatcher.isTranscriptActivityPath(
            "/Users/ahmed/.codex/sessions/2026/05/05",
            flags: flags
        ))
    }

    func testTranscriptActivityPathAcceptsJsonTranscriptsOnly() {
        XCTAssertTrue(LogActivityWatcher.isTranscriptActivityPath(
            "/Users/ahmed/.codex/sessions/2026/05/05/rollout.jsonl"
        ))
        XCTAssertTrue(LogActivityWatcher.isClaudeDesktopTranscriptActivityPath(
            "/Users/ahmed/Library/Application Support/Claude/claude-code-sessions/local_123.json"
        ))
        XCTAssertFalse(LogActivityWatcher.isTranscriptActivityPath(
            "/Users/ahmed/.codex/sessions/2026/05/05"
        ))
        XCTAssertFalse(LogActivityWatcher.isTranscriptActivityPath(
            "/Users/ahmed/.codex/sessions/2026/05/05/.DS_Store"
        ))
    }

    func testClaudeDesktopTranscriptFilterIgnoresSessionMetadata() {
        XCTAssertFalse(LogActivityWatcher.isClaudeDesktopTranscriptActivityPath(
            "/Users/ahmed/Library/Application Support/Claude/claude-code-sessions/scheduled-tasks.json"
        ))
        XCTAssertFalse(LogActivityWatcher.isClaudeDesktopTranscriptActivityPath(
            "/Users/ahmed/Library/Application Support/Claude/local-agent-mode-sessions/local_123.json"
        ))
        XCTAssertFalse(LogActivityWatcher.isClaudeDesktopTranscriptActivityPath(
            "/Users/ahmed/Library/Application Support/Claude/local-agent-mode-sessions/audit.jsonl"
        ))
        XCTAssertFalse(LogActivityWatcher.isClaudeDesktopTranscriptActivityPath(
            "/Users/ahmed/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/manifest.json"
        ))
    }

    func testClaudeDesktopTranscriptFilterAcceptsLocalAgentProjectJsonl() {
        XCTAssertTrue(LogActivityWatcher.isClaudeDesktopTranscriptActivityPath(
            "/Users/ahmed/Library/Application Support/Claude/local-agent-mode-sessions/org/project/local_123/.claude/projects/-sessions-example/turn.jsonl"
        ))
    }

    // MARK: - remoteIP from socket info

    func testRemoteIPFromIPv4Socket() {
        var info = in_sockinfo()
        info.insi_vflag = UInt8(INI_IPV4)
        var addr = in_addr()
        XCTAssertEqual(inet_pton(AF_INET, "17.253.144.10", &addr), 1)
        info.insi_faddr.ina_46.i46a_addr4 = addr

        XCTAssertEqual(AgentMonitor.remoteIP(from: info), "17.253.144.10")
    }

    func testRemoteIPFromIPv6Socket() {
        var info = in_sockinfo()
        info.insi_vflag = UInt8(INI_IPV6)
        var addr = in6_addr()
        // Fully-specified address (no zero run) so the canonical form is exact.
        XCTAssertEqual(inet_pton(AF_INET6, "2606:4700:4400:1:2:3:6810:5", &addr), 1)
        info.insi_faddr.ina_6 = addr

        XCTAssertEqual(AgentMonitor.remoteIP(from: info), "2606:4700:4400:1:2:3:6810:5")
    }

    func testRemoteIPUnwrapsIPv4MappedIPv6Socket() {
        var info = in_sockinfo()
        info.insi_vflag = UInt8(INI_IPV6)
        var addr = in6_addr()
        XCTAssertEqual(inet_pton(AF_INET6, "::ffff:17.253.144.10", &addr), 1)
        info.insi_faddr.ina_6 = addr

        XCTAssertEqual(AgentMonitor.remoteIP(from: info), "17.253.144.10")
    }

    func testRemoteIPNilWhenNoAddressFamilyFlag() {
        let info = in_sockinfo()   // insi_vflag == 0 → neither IPv4 nor IPv6
        XCTAssertNil(AgentMonitor.remoteIP(from: info))
    }
}
