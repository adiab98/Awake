# App Review Notes

Awake uses public macOS power assertion APIs to prevent idle system/display sleep
while the user has opted in through a menu bar control or local agent watcher.

The Mac App Store build is compiled with `APP_STORE`. That build removes the
direct-download edition's closed-lid override, sudo, pmset, sudoers, and
administrator-prompt paths from the App Store binary.

The App Store build includes a "Learn More" link explaining that closed-lid
support is a separate direct-download helper outside the Mac App Store. That
button opens a documentation page only. It does not download, install, or
execute additional code from the App Store app.

Temporary file access exception justification:

Awake is a menu bar utility that keeps the Mac awake while the user-selected AI
coding tools are actively working. These read-only home-relative exceptions let
Awake observe write activity in local transcript/session folders created by
Claude Code, Claude Desktop local agent mode, Codex CLI/Desktop sessions, and
OpenCode. Desktop detection does not treat the desktop app shell as activity;
it uses agent session writes and non-UI worker process signals. Awake does not
modify these folders or upload their contents; it only uses local activity
signals to hold and release macOS power assertions at the right time.

Privacy:

Awake does not collect user data. Transcript contents, prompts, source code, file
names, and usage analytics are not uploaded to the developer or any third party.

Encryption:

Awake does not use non-exempt encryption. `ITSAppUsesNonExemptEncryption` is set
to false.
