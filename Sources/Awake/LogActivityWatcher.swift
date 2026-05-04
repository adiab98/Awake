import Foundation
import CoreServices
import os.log

private let watcherLog = Logger(subsystem: "com.diabdiab.awake", category: "log-watcher")

/// Watches the log/transcript directories that agents write to in real time.
/// Catches the gap between an agent process spawning and our process scan picking it up,
/// and also covers periods where the agent is awaiting an API response (no local CPU,
/// no child processes, but the streamed transcript is being appended to).
final class LogActivityWatcher {
    enum Source: String, Hashable {
        case claude, claudeDesktop, codex, codexDesktop, opencode
        var displayName: String {
            switch self {
            case .claude: return "Claude Code"
            case .claudeDesktop: return "Claude Desktop"
            case .codex: return "Codex CLI"
            case .codexDesktop: return "Codex Desktop"
            case .opencode: return "OpenCode"
            }
        }

        var tool: AgentTool {
            switch self {
            case .claude: return .claude
            case .claudeDesktop: return .claudeDesktop
            case .codex: return .codex
            case .codexDesktop: return .codexDesktop
            case .opencode: return .opencode
            }
        }
    }

    /// Called on a private queue every time a write/create is observed in a watched tree.
    var onActivity: ((Source) -> Void)?

    /// Sources whose events should fire `onActivity`. Other sources still
    /// trigger FSEvents but are dropped on dispatch — keeps the user's
    /// per-tool toggles authoritative without rebuilding the stream.
    private let enabledLock = NSLock()
    private var _enabledTools: Set<AgentTool> = Set(AgentTool.allCases)
    var enabledTools: Set<AgentTool> {
        get { enabledLock.lock(); defer { enabledLock.unlock() }; return _enabledTools }
        set { enabledLock.lock(); _enabledTools = newValue; enabledLock.unlock() }
    }

    private var stream: FSEventStreamRef?
    private struct Root {
        let path: String
        let sources: [Source]
    }

    private var roots: [Root] = []
    private let rootSpecs: [Root]
    private let queue = DispatchQueue(label: "awake.fsevents")
    private let rootsLock = NSLock()
    private var retryTimer: Timer?

    init() {
        // Only watch the *session transcript* directories — these are written when an
        // agent is actively in a turn. Avoid sibling dirs like ~/.codex/log, browser
        // storage, and app cache folders that would fire false positives.
        // Watch both common OpenCode locations; whichever exists is picked up by
        // refreshRoots (and the retry timer catches creation later).
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        rootSpecs = [
            Root(path: "\(home)/.claude/projects", sources: [.claude]),
            Root(
                path: "\(home)/Library/Application Support/Claude/claude-code-sessions",
                sources: [.claudeDesktop]
            ),
            Root(
                path: "\(home)/Library/Application Support/Claude/local-agent-mode-sessions",
                sources: [.claudeDesktop]
            ),
            Root(path: "\(home)/.codex/sessions", sources: [.codex, .codexDesktop]),
            Root(path: "\(home)/.local/share/opencode/sessions", sources: [.opencode]),
            Root(path: "\(home)/.config/opencode/sessions", sources: [.opencode]),
        ]
        refreshRoots()
    }

    deinit { stop() }

    func start() {
        refreshRoots()
        startRetryTimerIfNeeded()
        let currentRoots = rootsSnapshot()
        guard stream == nil, !currentRoots.isEmpty else {
            watcherLog.debug("start: nothing to watch (roots=\(currentRoots.count, privacy: .public))")
            return
        }
        watcherLog.debug("start: watching \(currentRoots.count, privacy: .public) roots")

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let paths = currentRoots.map(\.path) as CFArray
        // UseCFTypes makes the callback's `eventPaths` a CFArray<CFString> instead of char**.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
        )

        let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, count, eventPaths, _, _) in
                guard let info, count > 0 else { return }
                let watcher = Unmanaged<LogActivityWatcher>
                    .fromOpaque(info).takeUnretainedValue()
                // With UseCFTypes, eventPaths is a CFArrayRef of CFStringRef.
                let cfArray = Unmanaged<CFArray>
                    .fromOpaque(eventPaths)
                    .takeUnretainedValue()
                let nsArray = cfArray as NSArray
                for raw in nsArray {
                    if let p = raw as? String {
                        watcher.handleEvent(forPath: p)
                    }
                }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,            // latency seconds — coalesce bursts of writes
            flags
        )
        guard let s else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        stopStream()
    }

    private func stopStream() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    // MARK: - Private

    @discardableResult
    private func refreshRoots() -> Bool {
        let newRoots = rootSpecs.filter { spec in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: spec.path, isDirectory: &isDir)
                && isDir.boolValue
        }
        rootsLock.lock()
        let oldPaths = Set(roots.map(\.path))
        roots = newRoots
        let changed = oldPaths != Set(newRoots.map(\.path))
        rootsLock.unlock()
        return changed
    }

    private func startRetryTimerIfNeeded() {
        guard retryTimer == nil, rootsSnapshot().count < rootSpecs.count else { return }
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let changed = self.refreshRoots()
            guard changed else { return }
            self.stopStream()
            self.start()
            if self.rootsSnapshot().count == self.rootSpecs.count {
                timer.invalidate()
                self.retryTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        retryTimer = t
    }

    private func handleEvent(forPath p: String) {
        let enabled = enabledTools
        for root in rootsSnapshot() where p.hasPrefix(root.path) {
            let sources = root.sources.filter { enabled.contains($0.tool) }
            guard !sources.isEmpty else { return }
            for source in sources {
                watcherLog.debug("fsevent source=\(source.rawValue, privacy: .public) path=\(p, privacy: .public)")
                onActivity?(source)
            }
            return
        }
    }

    private func rootsSnapshot() -> [Root] {
        rootsLock.lock()
        let snapshot = roots
        rootsLock.unlock()
        return snapshot
    }
}
