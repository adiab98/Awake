import Foundation

enum LidInstallStatus: Equatable, Sendable {
    case notInstalled
    case installed
}

enum LidActionError: Error, Equatable {
    case userCancelled
    case unsupportedUsername(String)
    case temporaryFileFailed(String)
    case privilegedShellFailed(code: Int, message: String)
}

protocol LidGuarding: AnyObject, Sendable {
    func currentlyDisabled() -> Bool
    func installationStatus() -> LidInstallStatus
    func install() -> Result<Void, LidActionError>
    func uninstall() -> Result<Void, LidActionError>
    /// `allowPrompt: true` permits an admin-password fallback if the sudoers
    /// rule isn't installed. Auto-paths (sync, engage, release) MUST pass
    /// `false` so they never surprise the user with a prompt.
    @discardableResult
    func setDisabled(_ disabled: Bool, allowPrompt: Bool) -> Bool
}

#if APP_STORE
/// Mac App Store builds cannot request root privileges or install resources in
/// shared system locations. Keep the type available, but make lid-control a
/// no-op so the App Store binary contains no sudo/pmset/sudoers workflow.
final class LidGuard: LidGuarding, @unchecked Sendable {
    func currentlyDisabled() -> Bool { false }
    func installationStatus() -> LidInstallStatus { .notInstalled }

    func install() -> Result<Void, LidActionError> {
        .failure(.privilegedShellFailed(
            code: 1,
            message: "Lid-close sleep control is not available in the Mac App Store build."
        ))
    }

    func uninstall() -> Result<Void, LidActionError> { .success(()) }

    @discardableResult
    func setDisabled(_ disabled: Bool, allowPrompt: Bool = false) -> Bool { false }
}
#else
/// Manages `pmset -a disablesleep` (the lid-close sleep override) by installing a
/// narrowly-scoped sudoers rule on first use. After install, the toggle runs
/// `sudo -n /usr/bin/pmset -a disablesleep 0|1` with no password prompt.
///
/// The rule allows ONLY two exact commands:
///   * `/usr/bin/pmset -a disablesleep 0`
///   * `/usr/bin/pmset -a disablesleep 1`
/// No wildcards, no shell, no environment forwarding. The user can revoke at any
/// time via the "Revoke" button in Awake's More window, which deletes the
/// sudoers file.
final class LidGuard: LidGuarding, @unchecked Sendable {
    static let sudoersPath = "/etc/sudoers.d/awake"
    static let pmsetPath = "/usr/bin/pmset"
    static let sudoPath = "/usr/bin/sudo"
    static let visudoPath = "/usr/sbin/visudo"
    static let installPath = "/usr/bin/install"
    static let rmPath = "/bin/rm"

    /// Returns true if `pmset -g` reports SleepDisabled = 1.
    func currentlyDisabled() -> Bool {
        guard let out = runRead(Self.pmsetPath, ["-g"]) else { return false }
        for raw in out.split(separator: "\n") {
            let line = raw.lowercased()
            if line.contains("sleepdisabled") || line.contains("disablesleep") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if let last = parts.last, last == "1" { return true }
            }
        }
        return false
    }

    /// Detects whether the current user can run the protected pmset commands
    /// without a password prompt. File existence is only the first gate: the
    /// sudoers file can be stale, edited, or for another user, so we also inspect
    /// sudo's non-interactive privilege listing for the exact NOPASSWD commands.
    func installationStatus() -> LidInstallStatus {
        guard FileManager.default.fileExists(atPath: Self.sudoersPath) else {
            return .notInstalled
        }
        guard let listing = runRead(Self.sudoPath, ["-n", "-l"]) else {
            return .notInstalled
        }
        return Self.sudoListShowsPasswordlessPmsetCommands(listing)
            ? .installed
            : .notInstalled
    }

    /// One-time install: writes a sudoers rule allowing the current user to toggle
    /// `pmset -a disablesleep 0|1` without a password. Validates with `visudo -c`
    /// before the file is moved into `/etc/sudoers.d/`, so a botched write can
    /// never break the user's sudo configuration.
    func install() -> Result<Void, LidActionError> {
        let user = NSUserName()
        guard Self.isValidSudoUsername(user) else {
            return .failure(.unsupportedUsername(user))
        }

        let body = Self.sudoersContent(forUser: user)
        // UUIDs are alphanumeric + hyphens — no shell metacharacters, safe to splice.
        let tmp = NSTemporaryDirectory().appending("awake-sudoers-\(UUID().uuidString)")
        do {
            try body.write(toFile: tmp, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.temporaryFileFailed(error.localizedDescription))
        }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Privileged shell: validate, then atomically install with strict perms.
        // visudo refuses to apply a syntactically invalid file; if validation fails,
        // the install step never runs and /etc/sudoers.d is untouched.
        let shell = """
        \(Self.visudoPath) -c -f \(tmp) \
        && \(Self.installPath) -m 440 -o root -g wheel \(tmp) \(Self.sudoersPath)
        """
        return runPrivileged(
            shell: shell,
            prompt: "Awake needs your password once to enable passwordless lid-close sleep toggling."
        )
    }

    /// Removes the sudoers rule. Idempotent: succeeds if the file is already gone.
    func uninstall() -> Result<Void, LidActionError> {
        let shell = "\(Self.rmPath) -f \(Self.sudoersPath)"
        return runPrivileged(
            shell: shell,
            prompt: "Awake needs your password to revoke passwordless lid-close sleep toggling."
        )
    }

    /// Set the lid-close sleep override.
    ///
    /// With `allowPrompt: false` (the default) this is strictly silent — uses
    /// `sudo -n` and returns `false` if the sudoers rule isn't in place. This is
    /// what auto-paths (engage on caffeinate, release on uncaffeinate) call so
    /// they never surprise the user with a prompt.
    ///
    /// With `allowPrompt: true` it falls back to an `osascript` admin prompt
    /// when `sudo -n` is rejected. Reserved for explicit user actions like the
    /// emergency "Restore Lid Sleep" button.
    @discardableResult
    func setDisabled(_ disabled: Bool, allowPrompt: Bool = false) -> Bool {
        let value = disabled ? "1" : "0"

        if runQuiet(Self.sudoPath,
                    ["-n", Self.pmsetPath, "-a", "disablesleep", value]) == 0 {
            return true
        }

        guard allowPrompt else { return false }

        let prompt = disabled
            ? "Awake needs your password to keep the Mac running with the lid closed."
            : "Awake needs your password to restore default lid-close sleep."
        let shell = "\(Self.pmsetPath) -a disablesleep \(value)"
        switch runPrivileged(shell: shell, prompt: prompt) {
        case .success: return true
        case .failure: return false
        }
    }

    // MARK: - Helpers (internal for unit testing)

    /// Builds the sudoers file body. Comments are ASCII-only to avoid any chance
    /// of locale/encoding edge cases. Each command line lists one exact argv —
    /// visudo treats arguments literally unless `*` is used, so this rule grants
    /// exactly two invocations and nothing more (no shell, no wildcards, no env
    /// forwarding).
    static func sudoersContent(forUser user: String) -> String {
        return """
        # Awake.app - narrow rule allowing the user to toggle the lid-close sleep
        # override (pmset disablesleep) without a password prompt. Remove this file
        # (or use the Revoke button in Awake > More) to revert.
        \(user) ALL=(root:wheel) NOPASSWD: \(pmsetPath) -a disablesleep 0
        \(user) ALL=(root:wheel) NOPASSWD: \(pmsetPath) -a disablesleep 1

        """
    }

    /// Conservative POSIX-username allowlist. Real macOS short usernames are
    /// `[a-z_][a-z0-9_-]{0,30}`; we allow upper-case as well and cap length at 64.
    /// Anything outside this is refused so we never write hostile bytes to the
    /// sudoers file (visudo would catch it too, but failing early gives a better
    /// error message and avoids touching disk).
    static func isValidSudoUsername(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        return name.allSatisfy { allowed.contains($0) }
    }

    /// Backslash- and quote-escape for embedding into an AppleScript string literal.
    /// Used belt-and-braces — current callers pass only constants and UUIDs.
    static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func sudoListShowsPasswordlessPmsetCommands(_ listing: String) -> Bool {
        func hasRule(for value: String) -> Bool {
            let expected = "\(pmsetPath) -a disablesleep \(value)"
            return listing.split(separator: "\n").contains { rawLine in
                let normalized = rawLine
                    .split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .joined(separator: " ")
                guard let marker = normalized.range(
                    of: "NOPASSWD:",
                    options: [.caseInsensitive]
                ) else {
                    return false
                }
                let command = normalized[marker.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                return command == expected
            }
        }

        return hasRule(for: "0") && hasRule(for: "1")
    }

    private func runPrivileged(shell: String, prompt: String) -> Result<Void, LidActionError> {
        let escapedShell = Self.appleScriptEscape(shell)
        let escapedPrompt = Self.appleScriptEscape(prompt)
        let source = """
        do shell script "\(escapedShell)" with prompt "\(escapedPrompt)" with administrator privileges
        """
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&error)
        if let error {
            let code = (error["NSAppleScriptErrorNumber"] as? Int) ?? 0
            // -128 = user cancelled the authentication dialog.
            if code == -128 { return .failure(.userCancelled) }
            let message = (error["NSAppleScriptErrorMessage"] as? String) ?? "Unknown error"
            return .failure(.privilegedShellFailed(code: code, message: message))
        }
        return .success(())
    }

    private func runQuiet(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func runRead(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return nil }
        // Drain BEFORE waitUntilExit to avoid pipe-full deadlock.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
#endif
