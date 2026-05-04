import Foundation

/// AI coding tools that Awake can detect. Each one has its own process /
/// session-file signature in the monitor; the user picks which ones to keep
/// awake for during onboarding (and edits the choice from More).
enum AgentTool: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case codex
    case cursor
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .opencode: return "OpenCode"
        }
    }

    /// Short label used in compact menu rows.
    var brandLabel: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .opencode: return "OpenCode"
        }
    }

    /// Detection for these tools is best-effort and can produce false
    /// positives — the UI surfaces a warning so users know to disable them
    /// if Awake misbehaves.
    var experimental: Bool {
        switch self {
        case .cursor: return true
        case .claude, .codex, .opencode: return false
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
