---
name: verify
description: Build, install, and launch Bloggo in the iOS simulator to observe changes at runtime
---

# Verify Bloggo in the simulator

## Build (xcode-select points at CommandLineTools — always prefix DEVELOPER_DIR)

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator build 2>&1 | tail -3
```

Expect `** BUILD SUCCEEDED **`. Don't grep the full log for "error" — clang command lines contain `-Werror` and drown the verdict.

## Install & launch

```bash
xcrun simctl boot <UDID>        # pick one from: xcrun simctl list devices available
open -a Simulator && sleep 15
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/fastblog-*/Build/Products/Debug-iphonesimulator/Bloggo.app
xcrun simctl launch booted com.fastblog.fastblog
xcrun simctl io booted screenshot /tmp/shot.png
```

## Gotchas

- Booted devices can revert to Shutdown between shell invocations in sandboxed sessions — re-check `xcrun simctl list devices | grep Booted` before each simctl call.
- `simctl privacy booted grant photos com.fastblog.fastblog` pre-grants photo access (only while booted).
- No tap tooling available on this machine: simctl has no tap subcommand, `idb`/`cliclick` not installed, and osascript is denied assistive access. Interactive flows (opening a blog, scrolling) need a human at the simulator, or grant Accessibility to the terminal in System Settings → Privacy & Security → Accessibility.
- Fresh installs land on onboarding with an empty library — flows that need an existing blog can't be reached without interaction.
- Reset the Highlights reveal seen-list: `xcrun simctl spawn booted defaults delete com.fastblog.fastblog bloggo.highlightsRevealSeen`, then relaunch the app.
