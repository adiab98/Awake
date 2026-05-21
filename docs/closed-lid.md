# Closed-Lid Support

Awake's Mac App Store build keeps your Mac awake with public macOS power
assertions. Those APIs can prevent idle system sleep while a session is active,
but they do not override every hardware lid-close sleep path.

For users who choose closed-lid support, Awake uses the direct-download edition
outside the Mac App Store. The Mac App Store app only links to this explanation.
It does not download, install, or execute extra code.

## How Closed-Lid Support Works

The direct-download edition can install a narrow administrator-approved rule at:

```text
/etc/sudoers.d/awake
```

That rule allows only these exact commands:

```text
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -b lowpowermode 0
/usr/bin/pmset -b lowpowermode 1
/usr/bin/pmset -c lowpowermode 0
/usr/bin/pmset -c lowpowermode 1
```

Awake uses those commands to turn the lid-close sleep override on while an Awake
session is active on battery or charger power, then restore normal lid sleep
when the session ends. If macOS reports serious thermal pressure, Awake backs
off and restores normal lid sleep. Awake also turns Low Power Mode on while
closed-lid support is enabled, then restores the previous Low Power Mode state
when closed-lid support is disabled.
The rule does not grant a shell, wildcard command access, or broad root access.

## Install Path

Install closed-lid support only from an Awake release published by Ahmed Diab:

https://github.com/adiab98/Awake/releases

After installing the direct-download edition, open Awake and use the closed-lid
setup controls in the app. macOS may ask for an administrator password during
setup.

## Revoke Access

The direct-download edition includes a revoke control in Awake's More window.
You can also remove the installed rule manually:

```bash
sudo rm -f /etc/sudoers.d/awake
```

After revoking access, Awake will no longer be able to toggle the lid-close sleep
override without administrator approval.
