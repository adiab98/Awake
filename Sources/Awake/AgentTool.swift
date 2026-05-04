import Foundation

/// AI coding tools that Awake can detect. Each one has its own process /
/// session-file signature in the monitor; the user picks which ones to keep
/// awake for during onboarding (and edits the choice from More).
enum AgentTool: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case claudeDesktop
    case codex
    case codexDesktop
    case cursor
    case opencode

    var id: String { rawValue }

    static var defaultEnabled: Set<AgentTool> {
        [.claude, .codex, .cursor, .opencode]
    }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .codex: return "Codex CLI"
        case .codexDesktop: return "Codex Desktop"
        case .cursor: return "Cursor"
        case .opencode: return "OpenCode"
        }
    }

    /// Short label used in compact menu rows.
    var brandLabel: String {
        switch self {
        case .claude: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .codex: return "Codex CLI"
        case .codexDesktop: return "Codex Desktop"
        case .cursor: return "Cursor"
        case .opencode: return "OpenCode"
        }
    }

    /// Detection for these tools is best-effort and can produce false
    /// positives — the UI surfaces a warning so users know to disable them
    /// if Awake misbehaves.
    var experimental: Bool {
        switch self {
        case .claudeDesktop, .codexDesktop, .cursor: return true
        case .claude, .codex, .opencode: return false
        }
    }

    var experimentalNote: String? {
        switch self {
        case .claudeDesktop, .codexDesktop:
            return "Desktop detection watches agent session activity inside the app, not the app merely being open. It is best-effort; turn off if Awake stays caffeinated while the app is idle."
        case .cursor:
            return "Cursor's UI can keep API connections open even when idle. Detection is best-effort; turn off if Awake stays caffeinated when you're not actively prompting."
        case .claude, .codex, .opencode:
            return nil
        }
    }
}

/// Defaults-backed Set<AgentTool>. Persists as a JSON-encoded array of raw
/// values so adding new cases later doesn't break the format.
enum AgentToolStore {
    static let key = "enabledAgentTools"

    static func load(defaults: UserDefaults = .standard) -> Set<AgentTool>? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let raws = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return Set(raws.compactMap(AgentTool.init(rawValue:)))
    }

    static func save(_ tools: Set<AgentTool>, defaults: UserDefaults = .standard) {
        let raws = tools.map(\.rawValue).sorted()
        guard let data = try? JSONEncoder().encode(raws) else { return }
        defaults.set(data, forKey: key)
    }
}
