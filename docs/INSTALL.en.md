# Installing and removing Btoll

Supports Apple Silicon Macs running macOS 14.6 or later. Open `Btoll-1.1.0-arm64.pkg` and let the macOS installer install the app and independent fan service. Open Btoll in Applications. Enter administrator credentials only in the system installer.

The app is ad-hoc signed. The installer is unsigned and has not been notarized by Apple. If blocked, review it in Privacy & Security and choose Open Anyway. Do not disable Gatekeeper.

The Codex panel uses the current user's official Codex login, quota and local session metadata. Install and sign in to official Codex first. Missing data stays unavailable. Developer credentials, chats and monitoring snapshots are not included.

First launch deploys a per-user monitor and LaunchAgent with the bundled Node runtime. The destination Mac does not need Homebrew, Python or Xcode. Existing data, preferences and revoked permissions are preserved. Choose music and Bluetooth permissions according to your needs.

Fan control requires supported hardware with fans. Half speed, three-quarter speed, custom RPM and full speed respect hardware limits. Manual modes expire automatically. Avoid running another fan controller at the same time. Some models may provide only partial monitoring data.

Per-app traffic may take 20–30 seconds to establish a baseline, then updates about every 10 seconds. Disk process rates require two samples. macOS may restrict some process counters. Battery power is not total system power. The awake list uses current system power assertions.

## Switching languages

Open Settings → General → 语言 / Language. Choose English, 简体中文 or Follow system, then restart when prompted. Both languages use the same app and installer. Preferences and session data are preserved.

## Updating

Download the latest installer from this repository's Releases and install over the previous version. Upstream Atoll automatic updates are disabled. The internal compatibility identifier remains `local.bsstoll.mac`. Quit older bsstoll copies before updating; archive them as ZIP files rather than leaving duplicate apps installed.

## Removing

First set fan control to automatic and quit Btoll. Stop the current user's local monitor:

```sh
launchctl bootout "gui/$(id -u)/local.codex.atoll-status"
rm -f "$HOME/Library/LaunchAgents/local.codex.atoll-status.plist"
```

Delete Btoll from Applications. To remove the independent fan service, use these administrator commands:

```sh
sudo launchctl bootout system/local.bsstoll.fan-helper
sudo rm -f /Library/LaunchDaemons/local.bsstoll.fan-helper.plist
sudo rm -f /Library/PrivilegedHelperTools/local.bsstoll.fan-helper
```

The service restores automatic fan control when it exits normally. The 10-minute deadline also limits manual operation if the UI exits unexpectedly. Keep personal data under `~/Library/Application Support/AtollCodexBridge` unless you intentionally want to remove it.
