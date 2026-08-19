<p align="center">
  <img src="branding/logo-full.svg" width="140" alt="Remote Pi logo" />
</p>

<h1 align="center">Remote Pi (Enhanced Edition)</h1>

<p align="center">
  Enhanced multiplatform controller (Desktop & Mobile) for the <a href="https://github.com/earendil-works/pi">Pi coding agent</a>.
</p>

## Why this fork?

Remote Pi was originally created primarily as a mobile companion (iOS/Android) for a local Pi instance. 
This fork expands on that for developers running Pi on **remote VMs, cloud instances, or headless servers** and want to connect it from PC, along with other enhancements.

---

## Fork Enhancements

- **Context tracking in UI**: Counts prompt cache reads/writes (`cacheRead`) and output tokens so cache hits reflect true usage (e.g. 34.1% / 500k) and shows it in the UI.
- **Native Windows & Linux builds**: Standalone desktop runners with single-instance mutex and automatic recovery from stale Hive database locks.
- **Terminal session resume**: Formats the exact command (`cd "<folder>" && pi -c`) directly in session info with one-click copy to continue local/VM sessions in Pi CLI.

---

## Links

- **Official site** — <https://remote-pi.jacobmoura.work>
- **Package documentation** — <https://pi.dev/packages/remote-pi?name=remote-pi>
- **GitHub** — <https://github.com/shivanshPurple/remote_pi>

### Downloads & Supported Platforms

| Platform | Status |
|---|---|
| Windows (x64) | [Native `.exe` Runner](./app) |
| Linux (x64 / ARM64) | [Native Desktop Runner](./app) |
| Google Play (Android) | [Get it on Google Play](https://play.google.com/store/apps/details?id=work.jacobmoura.remotepi) |
| App Store (iOS) | [Download on the App Store](https://apps.apple.com/app/remote-pi-coding-agent/id6773499691) |
| APK (sideload, Android) | [GitHub Releases](https://github.com/shivanshPurple/remote_pi/releases) |

---

## What's in this repo

| Package | Stack | Role |
|---|---|---|
| [`app/`](./app) | Flutter (Windows / Linux / Android / iOS) | High-performance multiplatform client |
| [`pi-extension/`](./pi-extension) | Node + TypeScript | Pi extension exposing `/remote-pi` & relay connector |
| [`relay/`](./relay) | Rust + Tokio | Fast WebSocket routing & mesh state broker |
| [`cockpit/`](./cockpit) | Flutter (Desktop Cockpit) | Desktop power-user management interface |
| [`site/`](./site) | Next.js | Landing page & documentation |

---

## Architecture

```
Flutter App / Desktop ──wss──► Relay (Rust) ◄──wss── Pi Extension (Node)
                                                            │
                                                     Local Pi Process
                                                            │
                                                     UDS Broker (Local Mesh)
                                                            │
                                                     Other Agents on Machine
```

- **Pairing** via short-lived QR code; peers persisted in secure storage.
- **Ed25519 authentication** — the Relay handshake proves possession of the connection key; App↔Pi pairing is enforced by the endpoints.
- **TLS protects traffic in transit**.

---

## Getting started

Install the Pi extension in any project where Pi runs:

```bash
pi install npm:remote-pi
```

Then in the Pi chat, run:

```
/remote-pi
```

The setup wizard walks you through agent name, session name, and relay choice, then prints a QR code. Scan it with the Remote Pi mobile app or enter the pairing code in the desktop app.

### Resuming Sessions in Terminal

To resume any session directly in your terminal or VM:

```bash
cd "<path-to-folder>" && pi -c
```

Or open the interactive session selector:

```bash
cd "<path-to-folder>" && pi -r
```

---

## Development & Building

### Flutter App (Desktop & Mobile)
```bash
cd app
flutter pub get
flutter test
flutter build windows --release   # For Windows
flutter build linux --release     # For Linux
flutter build apk --release       # For Android
```

### Pi Extension
```bash
cd pi-extension
npm install
npm test
npm run build
```

---

## License

License is per-package — see each subproject's `LICENSE` file (`pi-extension` is MIT).
