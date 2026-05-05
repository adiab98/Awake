import Foundation
import AppKit
import os.log

private let monitorLog = Logger(subsystem: "com.diabdiab.awake", category: "agent-monitor")

struct DetectedAgent: Identifiable, Hashable {
    enum Kind: String {
        case claudeApp, codexApp, claudeCLI, codexCLI
        case cursorApp, opencodeCLI

        var tool: AgentTool {
            switch self {
            case .claudeApp: return .claudeDesktop
            case .claudeCLI: return .claude
            case .codexApp: return .codexDesktop
            case .codexCLI: return .codex
            case .cursorApp: return .cursor
            case .opencodeCLI: return .opencode
            }
        }
    }
    let id: Int32
    let label: String
    let kind: Kind
    /// Cumulative CPU seconds of the parent only (parsed from `ps -o time`).
    let parentCpuSeconds: Double
    /// Recent CPU usage of the WHOLE process tree (parent + descendants), as a percent.
    /// `nil` until we have at least two samples.
    let treeCpuPercent: Double?
    /// True when the parent or any descendant is doing real work. Combines:
    ///   • Tree CPU above threshold (token streaming, tool execution, downloads)
    ///   • Open non-localhost TCP connection from the tree (API thinking, network I/O)
    /// We deliberately err on the side of "active" — a false positive holds sleep
    /// slightly too long; a false negative releases sleep mid-turn.
    let isActive: Bool
    /// True when the tree currently has at least one non-localhost ESTABLISHED TCP
    /// connection. Used to catch "agent is waiting on an API response with 0% CPU."
    let hasNetworkActivity: Bool
}

final class AgentMonitor {
    var onUpdate: (([DetectedAgent]) -> Void)?

    /// Threshold for total CPU% across the agent's process tree. The MCP-server idle
    /// floor sits around 2-5%; real in-turn work pushes well above this. Set lower
    /// for sensitivity; the sticky-hold window in the controller bridges quiet gaps.
    var cpuActivityThreshold: Double = 5.0

    /// Filter — only tools in this set produce detection results. Read on every
    /// scan so runtime toggles in More take effect immediately.
    private let enabledLock = NSLock()
    private var _enabledTools: Set<AgentTool> = Set(AgentTool.allCases)
    var enabledTools: Set<AgentTool> {
        get { enabledLock.lock(); defer { enabledLock.unlock() }; return _enabledTools }
        set { enabledLock.lock(); _enabledTools = newValue; enabledLock.unlock() }
    }

    private var timer: Timer?
    private let queue = DispatchQueue(label: "awake.agentmonitor")

    /// IP allowlist for the network-activity probe — only connections to one of
    /// these IPs count as "agent in turn." Resolved from a fixed list of AI
    /// API hostnames at startup and refreshed hourly to follow DNS rotation.
    /// Empty if the machine was offline at startup; the next refresh tick fills
    /// it in. CPU + transcript paths still work without this.
    private let apiHostsLock = NSLock()
    private var _apiHostIPs: Set<String> = []
    private var apiHostIPs: Set<String> {
        get { apiHostsLock.lock(); defer { apiHostsLock.unlock() }; return _apiHostIPs }
        set { apiHostsLock.lock(); _apiHostIPs = newValue; apiHostsLock.unlock() }
    }
    private static let apiHostnames = [
        "api.anthropic.com",
        "claude.ai",
        "api.openai.com",
        "chatgpt.com",
        "chat.openai.com",
        "api.cursor.sh",
        "api.cursor.com",
    ]
    private var hostRefreshTimer: Timer?

    /// Per-agent: total cumulative CPU seconds across the process tree at the previous poll.
    private var lastTreeCpuSample: [Int32: (taken: Date, totalCpu: Double)] = [:]

    private static let claudeRegex = try! NSRegularExpression(
        pattern: #"(^|[\s/])claude(?:\.[a-z]+)?(?:\s|$)"#,
        options: .caseInsensitive
    )
    private static let codexRegex = try! NSRegularExpression(
        pattern: #"(^|[\s/])codex(?:\.[a-z]+)?(?:\s|$)"#,
        options: .caseInsensitive
    )
    /// Cursor's helper Electron processes. We match the user-facing app
    /// binary path; "Cursor Helper" subprocesses share the same parent and
    /// get rolled into the descendant tree for CPU / network checks.
    private static let cursorRegex = try! NSRegularExpression(
        pattern: #"/Cursor\.app/Contents/MacOS/Cursor(?:\s|$)"#,
        options: []
    )
    private static let opencodeRegex = try! NSRegularExpression(
        pattern: #"(^|[\s/])opencode(?:[-_][a-z]+)?(?:\s|$)"#,
        options: .caseInsensitive
    )

    func start(interval: TimeInterval = 3.0) {
        monitorLog.debug("start: interval=\(interval, privacy: .public)")
        timer?.invalidate()
        refreshAPIHostIPs()
        scan()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let h = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            self?.refreshAPIHostIPs()
        }
        RunLoop.main.add(h, forMode: .common)
        hostRefreshTimer = h
    }

    func stop() {
        timer?.invalidate(); timer = nil
        hostRefreshTimer?.invalidate(); hostRefreshTimer = nil
    }

    func scanNow() { scan() }

    private func scan() {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.detect()
            DispatchQueue.main.async { self.onUpdate?(result) }
        }
    }

    // MARK: - Detection

    /// Snapshot of every process: pid → (ppid, cumulative CPU seconds, command).
    private struct ProcInfo {
        let ppid: Int32
        let cpuSec: Double
        let cpuPercent: Double
        let command: String
    }

    private func detect() -> [DetectedAgent] {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let enabled = enabledTools

        // Single ps invocation gives us pid, ppid, cumulative CPU time, current CPU%, command for ALL
        // processes. We need the full table so we can build the descendant tree of each
        // detected agent and sum CPU across the whole tree.
        guard let psOut = capture("/bin/ps", ["-axww", "-o", "pid=,ppid=,time=,%cpu=,command="]) else {
            return []
        }

        var procs: [Int32: ProcInfo] = [:]
        var childrenOf: [Int32: [Int32]] = [:]
        var candidatePids: [(pid: Int32, label: String, kind: DetectedAgent.Kind)] = []
        var codexDesktopServerPids: [Int32] = []

        for line in psOut.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // pid ppid time %cpu command-with-spaces
            let parts = trimmed.split(
                maxSplits: 4,
                omittingEmptySubsequences: true,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard parts.count == 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpuSec = parsePsTime(String(parts[2])),
                  let cpuPercent = Double(String(parts[3])) else { continue }
            let cmd = String(parts[4])

            procs[pid] = ProcInfo(ppid: ppid, cpuSec: cpuSec, cpuPercent: cpuPercent, command: cmd)
            childrenOf[ppid, default: []].append(pid)

            // Identify candidates (skip self and Awake helpers)
            guard pid != selfPid else { continue }
            let cmdLower = cmd.lowercased()
            if cmdLower.contains("/awake") || cmdLower.contains("awake.app/contents") { continue }

            if enabled.contains(.codexDesktop),
               Self.isCodexDesktopAppServerCommand(cmd) {
                codexDesktopServerPids.append(pid)
            }
            if let candidate = Self.candidate(for: cmd, enabledTools: enabled) {
                candidatePids.append((pid, candidate.label, candidate.kind))
            }
        }

        // Dedupe by pid
        var seen = Set<Int32>()
        let unique = candidatePids.filter { seen.insert($0.pid).inserted }

        // Build results, summing CPU across the descendant tree of each candidate.
        let now = Date()
        var newSamples: [Int32: (Date, Double)] = [:]
        var results: [DetectedAgent] = []

        for c in unique {
            let tree = descendants(of: c.pid, in: childrenOf)
            let parentCpu = procs[c.pid]?.cpuSec ?? 0
            let treeCpu = tree.reduce(0.0) { sum, pid in sum + (procs[pid]?.cpuSec ?? 0) }
            let treeCurrentCpu = tree.reduce(0.0) { sum, pid in sum + (procs[pid]?.cpuPercent ?? 0) }
            newSamples[c.pid] = (now, treeCpu)

            var recentTreeCpu: Double? = nil
            if let prev = lastTreeCpuSample[c.pid] {
                let dt = now.timeIntervalSince(prev.taken)
                if dt > 0 {
                    let dCpu = treeCpu - prev.totalCpu
                    recentTreeCpu = max(0, (dCpu / dt) * 100.0)
                }
            }

            let cpuActive = (recentTreeCpu ?? treeCurrentCpu) >= cpuActivityThreshold
            let networkTree = tree.filter { !isMcpServer(procs[$0]?.command ?? "") }
            let networkActive = cpuActive ? false : hasNetworkActivity(treePids: networkTree)
            let active = cpuActive || networkActive
            results.append(DetectedAgent(
                id: c.pid,
                label: c.label,
                kind: c.kind,
                parentCpuSeconds: parentCpu,
                treeCpuPercent: recentTreeCpu,
                isActive: active,
                hasNetworkActivity: networkActive
            ))
        }

        for pid in codexDesktopServerPids {
            let tree = descendants(of: pid, in: childrenOf)
            let workerTree = tree.filter { workerPid in
                guard workerPid != pid else { return false }
                return Self.isCodexDesktopAgentWorkerCommand(procs[workerPid]?.command ?? "")
            }
            guard !workerTree.isEmpty else { continue }

            let workerCpu = workerTree.reduce(0.0) { sum, pid in sum + (procs[pid]?.cpuSec ?? 0) }
            let workerCurrentCpu = workerTree.reduce(0.0) { sum, pid in sum + (procs[pid]?.cpuPercent ?? 0) }
            newSamples[pid] = (now, workerCpu)

            var recentWorkerCpu: Double? = nil
            if let prev = lastTreeCpuSample[pid] {
                let dt = now.timeIntervalSince(prev.taken)
                if dt > 0 {
                    let dCpu = workerCpu - prev.totalCpu
                    recentWorkerCpu = max(0, (dCpu / dt) * 100.0)
                }
            }

            let cpuActive = (recentWorkerCpu ?? workerCurrentCpu) >= cpuActivityThreshold
            let networkTree = workerTree.filter { !isMcpServer(procs[$0]?.command ?? "") }
            let networkActive = cpuActive ? false : hasNetworkActivity(treePids: networkTree)
            let active = cpuActive || networkActive
            guard active else { continue }

            results.append(DetectedAgent(
                id: pid,
                label: "codex desktop agent",
                kind: .codexApp,
                parentCpuSeconds: procs[pid]?.cpuSec ?? 0,
                treeCpuPercent: recentWorkerCpu,
                isActive: true,
                hasNetworkActivity: networkActive
            ))
        }

        lastTreeCpuSample = newSamples

        let summary = results.isEmpty
            ? "(none)"
            : results.map {
                let cpu = $0.treeCpuPercent.map { String(format: "%.0f", $0) } ?? "?"
                let net = $0.hasNetworkActivity ? "+net" : ""
                return "\($0.label)#\($0.id)[tree=\(cpu)%\(net)]\($0.isActive ? "*" : "")"
            }.joined(separator: ", ")
        monitorLog.debug("scan: \(results.count, privacy: .public) — \(summary, privacy: .public)")

        return results
    }

    static func candidate(
        for command: String,
        enabledTools enabled: Set<AgentTool>
    ) -> (label: String, kind: DetectedAgent.Kind)? {
        let cmdLower = command.lowercased()
        if cmdLower.contains("/awake") || cmdLower.contains("awake.app/contents") {
            return nil
        }

        if Self.isClaudeDesktopAgentCommand(command) {
            return enabled.contains(.claudeDesktop)
                ? ("claude desktop agent", .claudeApp)
                : nil
        }
        if Self.isCodexDesktopAppServerCommand(command) {
            return nil
        }
        if cmdLower.contains(".app/contents/macos/claude")
            || cmdLower.contains(".app/contents/macos/codex")
            || cmdLower.contains(".app/contents/frameworks/") {
            return nil
        }

        let range = NSRange(command.startIndex..., in: command)
        if enabled.contains(.claude),
           claudeRegex.firstMatch(in: command, range: range) != nil {
            return ("claude code", .claudeCLI)
        }
        if enabled.contains(.codex),
           codexRegex.firstMatch(in: command, range: range) != nil {
            return ("codex cli", .codexCLI)
        }
        if enabled.contains(.opencode),
           opencodeRegex.firstMatch(in: command, range: range) != nil {
            return ("opencode cli", .opencodeCLI)
        }
        if enabled.contains(.cursor),
           cursorRegex.firstMatch(in: command, range: range) != nil {
            return ("cursor", .cursorApp)
        }
        return nil
    }

    static func isClaudeDesktopAgentCommand(_ command: String) -> Bool {
        let lc = command.lowercased()
        return lc.contains("/library/application support/claude/claude-code/")
            || lc.contains("/library/application support/claude/claude-code-vm/")
    }

    static func isCodexDesktopAppServerCommand(_ command: String) -> Bool {
        let lc = command.lowercased()
        return lc.contains("/codex.app/contents/resources/codex app-server")
    }

    static func isCodexDesktopAgentWorkerCommand(_ command: String) -> Bool {
        let lc = command.lowercased()
        if lc.contains("/codex.app/contents/frameworks/") { return false }
        if lc.contains("/codex.app/contents/macos/codex") { return false }
        if isCodexDesktopAppServerCommand(command) { return false }
        if lc.contains("chrome_crashpad_handler") { return false }
        return true
    }

    /// The Codex CLI and Codex Desktop currently share `~/.codex/sessions`.
    /// Use the live process tree to decide which owner(s) a transcript write can
    /// plausibly belong to, instead of crediting every write to both tools.
    static func codexActivityOwners(psOutput: String? = nil) -> Set<AgentTool> {
        let output = psOutput ?? captureOutput(
            "/bin/ps",
            ["-axww", "-o", "pid=,ppid=,command="]
        )
        guard let output else { return [] }

        let (commands, childrenOf) = parsePidPpidCommands(output)
        var owners = Set<AgentTool>()
        var appServerPids: [Int32] = []

        for (pid, command) in commands {
            if isCodexDesktopAppServerCommand(command) {
                appServerPids.append(pid)
                continue
            }
            if candidate(for: command, enabledTools: [.codex])?.kind == .codexCLI {
                owners.insert(.codex)
            }
        }

        for pid in appServerPids {
            let tree = descendants(of: pid, in: childrenOf)
            let hasAgentWorker = tree.contains { workerPid in
                guard workerPid != pid else { return false }
                return isCodexDesktopAgentWorkerCommand(commands[workerPid] ?? "")
            }
            if hasAgentWorker {
                owners.insert(.codexDesktop)
            }
        }

        return owners
    }

    /// Heuristic: is this command line an MCP server? They keep persistent connections
    /// to remote services (Slack, Upstash, GitHub, etc.) and would otherwise produce
    /// false positives in the network-activity check.
    private func isMcpServer(_ command: String) -> Bool {
        let lc = command.lowercased()
        if lc.contains("@modelcontextprotocol") { return true }
        if lc.contains("@upstash") { return true }
        if lc.contains("-mcp") { return true }
        if lc.contains("/mcp/") || lc.contains("mcp.js") || lc.contains("mcp/cli") { return true }
        // common pattern: "npm exec ...mcp..." or "node ... mcp ..."
        if (lc.contains("npm exec") || lc.contains("npx ") || lc.contains("node ") || lc.contains("uv ")) &&
           lc.contains("mcp") { return true }
        return false
    }

    /// Returns true if any pid in `treePids` has an established TCP connection
    /// to one of the AI API hosts in `apiHostIPs`. Catches "agent waiting on
    /// API response" — claude/codex sit at 0% CPU during model thinking but
    /// the HTTPS connection to api.anthropic.com / api.openai.com stays open.
    ///
    /// The allowlist is critical for Cursor: its UI keeps connections to
    /// settings/sync/telemetry endpoints open continuously, which would
    /// false-positive a naive "any non-localhost TCP" check.
    private func hasNetworkActivity(treePids: [Int32]) -> Bool {
        guard !treePids.isEmpty else { return false }
        let allowlist = apiHostIPs
        guard !allowlist.isEmpty else { return false }
        let pidArg = treePids.map(String.init).joined(separator: ",")
        // -i: network files, -nP: skip DNS/service lookups (fast),
        // -sTCP:ESTABLISHED: only currently-open connections, -p: filter to these pids.
        guard let out = capture("/usr/sbin/lsof",
            ["-i", "-nP", "-sTCP:ESTABLISHED", "-p", pidArg]) else { return false }
        for line in out.split(separator: "\n") {
            guard line.contains("ESTABLISHED") else { continue }
            guard let remote = Self.remoteIP(from: String(line)) else { continue }
            if allowlist.contains(remote) { return true }
        }
        return false
    }

    /// Extract the remote IP from an `lsof -nP` NAME column.
    /// Examples (whitespace separated):
    ///   ... TCP 192.168.1.5:55432->17.253.144.10:443 (ESTABLISHED)
    ///   ... TCP [fe80::1]:55432->[2606:4700::6810]:443 (ESTABLISHED)
    ///   ... TCP [::ffff:192.0.2.1]:55432->[::ffff:17.253.144.10]:443 (ESTABLISHED)
    /// Returns the remote IP as the canonical form: bare v4 for v4 / v4-in-v6,
    /// bare v6 (no brackets) otherwise.
    static func remoteIP(from line: String) -> String? {
        guard let arrow = line.range(of: "->") else { return nil }
        let after = line[arrow.upperBound...]
        // Take everything up to the first whitespace.
        let endpoint = after.split(whereSeparator: { $0 == " " || $0 == "\t" }).first
        guard var ep = endpoint.map(String.init) else { return nil }

        // Bracketed IPv6: "[addr]:port" — strip brackets and trailing :port.
        if ep.hasPrefix("[") {
            guard let close = ep.firstIndex(of: "]") else { return nil }
            ep = String(ep[ep.index(after: ep.startIndex)..<close])
            // Unwrap IPv4-mapped form "::ffff:1.2.3.4" → "1.2.3.4".
            if let mapped = ep.range(of: "::ffff:", options: .caseInsensitive) {
                return String(ep[mapped.upperBound...])
            }
            return ep
        }
        // Bare IPv4: "1.2.3.4:443" — strip :port.
        if let colon = ep.lastIndex(of: ":") {
            return String(ep[..<colon])
        }
        return nil
    }

    /// Resolve `apiHostnames` via getaddrinfo and refresh the allowlist.
    /// Runs on the monitor's background queue to avoid stalling the main
    /// thread on slow DNS. Failure to resolve a host is silently skipped —
    /// when offline, the allowlist may end up empty, which only disables
    /// the network signal (CPU and transcript paths still function).
    private func refreshAPIHostIPs() {
        queue.async { [weak self] in
            guard let self else { return }
            var ips = Set<String>()
            for host in Self.apiHostnames {
                ips.formUnion(Self.resolveHost(host))
            }
            self.apiHostIPs = ips
            monitorLog.debug("api host ips: \(ips.count, privacy: .public)")
        }
    }

    private static func resolveHost(_ host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let head = result else {
            return []
        }
        defer { freeaddrinfo(head) }
        var ips: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let node = cursor {
            if let addr = node.pointee.ai_addr {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let rc = getnameinfo(
                    addr, node.pointee.ai_addrlen,
                    &buf, socklen_t(buf.count),
                    nil, 0, NI_NUMERICHOST
                )
                if rc == 0 {
                    var ip = String(cString: buf)
                    // Canonicalize IPv4-mapped IPv6 ("::ffff:1.2.3.4") to plain v4
                    // so it matches the lsof output style for v4 endpoints.
                    if let mapped = ip.range(of: "::ffff:", options: .caseInsensitive) {
                        ip = String(ip[mapped.upperBound...])
                    }
                    ips.append(ip)
                }
            }
            cursor = node.pointee.ai_next
        }
        return ips
    }

    /// Returns [rootPid] + every transitive descendant.
    private func descendants(of root: Int32, in childrenOf: [Int32: [Int32]]) -> [Int32] {
        Self.descendants(of: root, in: childrenOf)
    }

    /// Returns [rootPid] + every transitive descendant.
    private static func descendants(of root: Int32, in childrenOf: [Int32: [Int32]]) -> [Int32] {
        var out: [Int32] = [root]
        var stack: [Int32] = [root]
        while let pid = stack.popLast() {
            if let kids = childrenOf[pid] {
                for kid in kids {
                    out.append(kid)
                    stack.append(kid)
                }
            }
        }
        return out
    }

    private static func parsePidPpidCommands(_ psOut: String) -> (
        commands: [Int32: String],
        childrenOf: [Int32: [Int32]]
    ) {
        var commands: [Int32: String] = [:]
        var childrenOf: [Int32: [Int32]] = [:]
        for line in psOut.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(
                maxSplits: 2,
                omittingEmptySubsequences: true,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { continue }
            commands[pid] = String(parts[2])
            childrenOf[ppid, default: []].append(pid)
        }
        return (commands, childrenOf)
    }

    // MARK: - Process helpers

    private static func captureOutput(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Run a binary and capture stdout. Drains stdout before waiting on exit so we don't
    /// deadlock when the child writes more than the pipe buffer (~64KB).
    private func capture(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Parse `ps -o time=` output. Formats: `MM:SS.ss`, `HH:MM:SS`, `D-HH:MM:SS`.
    private func parsePsTime(_ s: String) -> Double? {
        var working = s
        var days: Double = 0
        if let dash = working.firstIndex(of: "-") {
            days = Double(working[..<dash]) ?? 0
            working = String(working[working.index(after: dash)...])
        }
        let rawParts = working.split(separator: ":")
        let parts = rawParts.compactMap { Double($0) }
        guard parts.count == rawParts.count else { return nil }
        var seconds: Double = 0
        switch parts.count {
        case 3:
            let h = parts[0], m = parts[1], s = parts[2]
            seconds = h * 3600 + m * 60 + s
        case 2:
            seconds = parts[0] * 60 + parts[1]
        case 1:
            seconds = parts[0]
        default:
            return nil
        }
        return days * 86400 + seconds
    }
}
