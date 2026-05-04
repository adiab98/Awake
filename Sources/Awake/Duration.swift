import Foundation

enum Duration: Hashable, Identifiable {
    case indefinite
    case minutes(Int)
    case hours(Int)

    var id: String {
        switch self {
        case .indefinite: return "inf"
        case .minutes(let m): return "m\(m)"
        case .hours(let h): return "h\(h)"
        }
    }

    static var presets: [Duration] {
        [.indefinite,
         .minutes(1), .minutes(5),
         .minutes(15), .minutes(30), .minutes(45),
         .hours(1), .hours(4), .hours(8), .hours(12)]
    }

    /// Presets shown in the Timer dropdown — no `.indefinite` because the
    /// row's toggle handles on/off.
    static var timerPresets: [Duration] {
        [.minutes(1), .minutes(5),
         .minutes(15), .minutes(30), .minutes(45),
         .hours(1), .hours(4), .hours(8), .hours(12)]
    }

    var shortLabel: String {
        switch self {
        case .indefinite: return "∞"
        case .minutes(let m): return String(format: "%02d", m)
        case .hours(let h): return String(format: "%02d", h)
        }
    }

    var menuLabel: String {
        switch self {
        case .indefinite: return "No timer"
        case .minutes(let m): return "\(m) minute\(m == 1 ? "" : "s")"
        case .hours(let h): return "\(h) hour\(h == 1 ? "" : "s")"
        }
    }

    /// Total minutes (rounded). 0 for `.indefinite`.
    var totalMinutes: Int {
        switch self {
        case .indefinite: return 0
        case .minutes(let m): return m
        case .hours(let h): return h * 60
        }
    }

    static func from(minutes: Int) -> Duration {
        if minutes <= 0 { return .indefinite }
        return .minutes(minutes)
    }

    var seconds: TimeInterval? {
        switch self {
        case .indefinite: return nil
        case .minutes(let m): return TimeInterval(m * 60)
        case .hours(let h): return TimeInterval(h * 3600)
        }
    }
}
