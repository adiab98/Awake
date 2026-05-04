# Mac App Store submission notes

## Why keep-awake apps can be accepted

The App Store-safe part of Awake is the same class of behavior as other
keep-awake utilities: it uses public power assertion APIs to prevent idle
system/display sleep while the user has opted in.

The risky part is different: the direct-download build can install a sudoers
rule and call `pmset -a disablesleep` for lid-close sleep. Mac App Store apps
must be sandboxed, self-contained, and cannot request root privileges or install
resources in shared system locations. The App Store build therefore compiles
that feature out.

Amphetamine uses a similar split. Its App Store listing says Power Protect is not
included directly and requires a separate download/installation. For Awake, the
App Store binary may link to documentation about the separate helper, but it
must not download, install, or run that helper from inside the App Store app.

## Browser handoff

Use this when continuing from Codex Desktop or any session with the Browser Use
tool available.

```text
Workspace: /Users/ahmed/Documents/Awake

Use Browser Use/in-app browser for App Store Connect and Apple Developer portal
tasks.

Goal: finish the App Store Connect/browser-side setup needed to upload Awake to
the Mac App Store.

Context:
- App name: Awake
- Bundle ID: com.diabdiab.awake
- Team ID: AR6D29J5FK
- Category: Utilities
- Version: 0.1
- Build: 1
- Local Xcode project exists: /Users/ahmed/Documents/Awake/Awake.xcodeproj
- Archive exists: /Users/ahmed/Documents/Awake/build/Awake-AppStore.xcarchive
- Export options: /Users/ahmed/Documents/Awake/ExportOptions-AppStore.plist
- Entitlements: /Users/ahmed/Documents/Awake/Awake-AppStore.entitlements
- App Store compliance work is already done: APP_STORE removes sudo, pmset,
  sudoers, administrator prompts, and closed-lid privileged behavior from the
  App Store binary.

Tasks:
1. Open Apple Developer / App Store Connect in the browser.
2. Confirm or create the macOS bundle identifier `com.diabdiab.awake` for team
   `AR6D29J5FK`.
3. Confirm or create an App Store Connect macOS app record:
   - Name: Awake
   - Bundle ID: com.diabdiab.awake
   - SKU: com.diabdiab.awake
   - Primary language: English
   - Category: Utilities
4. Do not misrepresent closed-lid behavior in metadata. The App Store version
   should say it keeps the Mac awake while agents/tasks run, not that it works
   with the lid closed.
5. Set up/download/install missing Mac App Store signing assets if needed:
   - Mac App Distribution/Application signing certificate
   - Mac Installer Distribution certificate
   - provisioning profile for `com.diabdiab.awake`
6. Export the existing archive:
   `xcodebuild -exportArchive -archivePath build/Awake-AppStore.xcarchive -exportPath build/AppStoreExport -exportOptionsPlist ExportOptions-AppStore.plist -allowProvisioningUpdates`
7. If export succeeds, upload the exported `.pkg` with Transporter, Xcode
   Organizer, `xcrun altool`, or `asc builds upload`.
8. Stop before any irreversible paid/submission action beyond creating the app
   record or uploading the build. Report exactly what was created/uploaded and
   any remaining blocker.

Important: do not revert local code changes. If the archive must be regenerated,
use the existing `Awake.xcodeproj` and preserve the APP_STORE compilation
condition.
```

## Listing copy

Short description:

```text
Keep your Mac awake while local AI coding agents are still working.
```

Full description:

```text
Awake is a menu bar utility for developers who run local AI coding tools and
long-running terminal tasks.

Start a timed session or let Awake watch supported local agent activity. While
work is still in progress, Awake keeps your Mac from going idle. When the work
stops, Awake releases its power assertion so macOS can return to normal energy
behavior.

Features:
- Menu bar controls for quick timed awake sessions
- Activity detection for Claude Code, Claude Desktop, Codex CLI, Codex Desktop, Cursor, and OpenCode
- Display sleep and system sleep controls using macOS power assertions
- Sandboxed App Store build with read-only agent session access and local worker-process signals
- No cloud account, no analytics, and no transcript upload

Closed-lid support is not included directly in the Mac App Store build. The app
links to information about a separate direct-download helper for users who choose
to install it outside the store.
```

Keywords:

```text
awake,keep awake,prevent sleep,developer,menu bar,coding,ai,agent,utility
```

Local metadata files:

```text
metadata/app-info/en-US.strings
metadata/version/0.1/en-US.strings
metadata/review-notes.md
```

Support and privacy pages:

```text
docs/support.md
docs/privacy.md
```

The support/privacy URLs in the metadata point to the GitHub `main` branch. Push
these files and verify the URLs are publicly accessible before entering them in
App Store Connect.

## Build

```bash
./build_appstore.sh
```

The script compiles with `-DAPP_STORE`, signs with `Awake-AppStore.entitlements`,
and strips the lid-close setup UI/code path from the App Store binary.

An Xcode project is also generated from `project.yml` for App Store export:

```bash
xcodegen --cache-path .build/xcodegen-cache
xcodebuild -project Awake.xcodeproj \
  -scheme Awake \
  -configuration Release \
  -destination generic/platform=macOS \
  -derivedDataPath build/DerivedData \
  -archivePath build/Awake-AppStore.xcarchive \
  -allowProvisioningUpdates \
  archive

xcodebuild -exportArchive \
  -archivePath build/Awake-AppStore.xcarchive \
  -exportPath build/AppStoreExport \
  -exportOptionsPlist ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

If export fails with `No signing certificate "Mac Installer Distribution"`
or `No profiles for 'com.diabdiab.awake'`, add the Apple Developer account in
Xcode or install the Mac App Store distribution certificate, installer
certificate, and provisioning profile.

After `asc` authentication is available, these are the relevant signing setup
checks/commands:

```bash
asc bundle-ids list --paginate
asc bundle-ids create --identifier "com.diabdiab.awake" --name "Awake" --platform MAC_OS

asc certificates list --certificate-type MAC_APP_DISTRIBUTION
asc certificates list --certificate-type MAC_INSTALLER_DISTRIBUTION

asc signing fetch \
  --bundle-id "com.diabdiab.awake" \
  --profile-type MAC_APP_STORE \
  --create-missing \
  --output "./signing"
```

If certificates must be created from the CLI, generate a CSR first and create
both Mac App Store certificate types:

```bash
asc certificates csr generate \
  --common-name "Awake Mac App Store" \
  --key-out "./signing/Awake-MAS.key" \
  --csr-out "./signing/Awake-MAS.csr"
asc certificates create --certificate-type MAC_APP_DISTRIBUTION --csr "./signing/Awake-MAS.csr"
asc certificates create --certificate-type MAC_INSTALLER_DISTRIBUTION --csr "./signing/Awake-MAS.csr"
```

For local checks, the script ad-hoc signs the app. For upload, provide:

```bash
export APP_STORE_SIGNING_IDENTITY="Apple Distribution: ..."
export APP_STORE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: ..."
export APP_STORE_PROVISIONING_PROFILE="/path/to/profile.provisionprofile"
./build_appstore.sh
```

## App Sandbox information

Temporary exception entitlement:

```text
com.apple.security.temporary-exception.files.home-relative-path.read-only
```

Values:

```text
/.claude/projects/
/Library/Application Support/Claude/claude-code-sessions/
/Library/Application Support/Claude/local-agent-mode-sessions/
/.codex/sessions/
/.local/share/opencode/sessions/
/.config/opencode/sessions/
```

Usage information for App Store Connect:

```text
Awake is a menu bar utility that keeps the Mac awake while the user-selected AI
coding tools are actively working. These read-only home-relative exceptions let
Awake observe write activity in the local transcript/session folders created by
Claude Code, Claude Desktop local agent mode, Codex CLI/Desktop sessions, and
OpenCode. Desktop detection does not treat the desktop app shell as activity;
it uses agent session writes and non-UI worker process signals. Awake does not
modify these folders or upload their contents; it only uses local activity
signals to hold and release macOS power assertions at the right time.
```

## Upload

After the App Store app record exists and the signed package is created:

```bash
asc builds upload \
  --app "APP_ID" \
  --pkg "build/AppStore/Awake-0.1-1-mas.pkg" \
  --version "0.1" \
  --build-number "1" \
  --wait
```

Use `--platform MAC_OS` for preflight/submission commands:

```bash
asc submit preflight --app "APP_ID" --version "0.1" --platform MAC_OS
```
