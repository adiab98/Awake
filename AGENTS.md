# Repository Rules

- After changing source code, run `SKIP_NOTARIZATION=1 INSTALL_TO_APPLICATIONS=1 ./build.sh` before ending the task. This rebuilds the app, refreshes the bundle, replaces `/Applications/Awake.app`, unregisters the local build artifact, and removes `build/Awake.app` so macOS only sees one Awake app.
