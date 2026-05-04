# Awake

> **Note:** v0.1 is signed but notarization is pending Apple's queue.
> First launch: **right-click `Awake.app` → Open** to bypass Gatekeeper. A
> notarized v0.1.1 will ship as soon as Apple's submission clears.

A tiny macOS menu-bar app that keeps your Mac awake while AI coding agents
finish their turn — Claude Code, Codex, Cursor, OpenCode. Optionally keeps it
running with the lid closed.

Detects active agent sessions by watching their session transcripts and
CPU/network activity, then holds a power assertion so the Mac doesn't sleep
mid-turn. You can also caffeinate manually with a timer.

Requires macOS 14 (Sonoma) or later. Universal binary, Apple Silicon and
Intel.

## Install

Download the latest `Awake-0.1.zip` from
[Releases](../../releases/latest), unzip, and drag `Awake.app` into
`/Applications`.

It lives in the menu bar; there is no Dock icon.

## Features

- **Wait for AI agent turn** — keeps the Mac awake while Claude Code, Codex,
  Cursor, or OpenCode is in-turn (CPU active, transcript writing, or open API
  connection) and for a short sticky window after.
- **Manual caffeinate** with optional timer, 1 minute to 12 hours, or custom.
- **Keep display awake** — also blocks display sleep, not just system sleep.
- **Stay awake with lid closed** — toggles `pmset -a disablesleep`. See below.
- **Launch at login** — opt-in from the More window.

## Lid-close sleep and the one-time password

Toggling lid-close sleep changes a system-wide power setting (`pmset -a
disablesleep`), which macOS protects with admin authorization. Out of the box,
that means a password prompt every single time the toggle flips.

Awake offers a one-time setup: with your permission, it installs a narrowly
scoped sudoers rule at `/etc/sudoers.d/awake` that lets your user run exactly
two commands without a password:

```
<your-user> ALL=(root:wheel) NOPASSWD: /usr/bin/pmset -a disablesleep 0
<your-user> ALL=(root:wheel) NOPASSWD: /usr/bin/pmset -a disablesleep 1
```

No wildcards. No shell. No environment forwarding. The file is validated with
`visudo -c` before it is moved into place, so a botched install can never
break your existing sudo configuration.

After that, the toggle is silent — no password prompts, ever.

You can revoke at any time from **Awake → More → Revoke Passwordless Access**,
or manually:

```bash
sudo rm /etc/sudoers.d/awake
```

If you skip the setup, the lid toggle still works — every change just pops a
password prompt. You can do the one-time setup later from More.

## Uninstall

1. Open `Awake → More` and click **Revoke Passwordless Access** (if you set it
   up). This removes `/etc/sudoers.d/awake`.
2. In the same window, toggle **Launch Awake at login** off.
3. Quit Awake and delete `Awake.app` from `/Applications`.

Preferences are stored in `~/Library/Preferences/com.diabdiab.awake.plist` and
can be removed with `defaults delete com.diabdiab.awake`.

## Build from source

```bash
./build.sh
open build/Awake.app
```

The script produces a universal `build/Awake.app`. With a Developer ID
identity in your keychain it signs for distribution; otherwise it falls back
to ad-hoc signing for local use.

## Tests

```bash
swift test
```

29 tests, including a roundtrip that pipes the generated sudoers body through
`visudo -c` to confirm the format stays valid.

## License

MIT — see [LICENSE](LICENSE).
