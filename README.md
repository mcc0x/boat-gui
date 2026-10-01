<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Boat Deck icon">
</p>

<h1 align="center">Boat Deck</h1>

<p align="center">
  A native macOS app for managing <a href="https://boat.dev">boat.dev</a> cloud sandboxes:<br>
  launch and control VMs, drive coding agents, browse files, run commands, and manage environments,
  snapshots, webhooks and API keys without leaving your Mac.
</p>

---

## Features

| Area | What you can do |
| --- | --- |
| **Home** | Greeting, live counts (active sandboxes, credit, starts left, environments), recent sandboxes, fleet breakdown and an activity timeline of state changes. |
| **Sandboxes** | List or grid view with filters, search and sort. Create sandboxes with size, lifetime, environment, starting snapshot, env vars, setup script and an optional first agent prompt. Stop, resume, fork, extend, rename, snapshot or delete. |
| **Sandbox › Overview** | Live auto-stop countdown, billed usage, machine specs, SSH endpoint, Open URL, and every field the API returns. |
| **Sandbox › Agent** | Prompt Claude Code / Codex inside the sandbox, pick provider, model and effort, steer or interrupt a running turn, and follow the event log. If the agent isn't set up yet, it links you to the setup page. |
| **Sandbox › Terminal** | Run commands (streamed, wait-for-result, or detached) with history (↑/↓). |
| **Sandbox › Files** | Browse, view and edit text files, preview images, upload by drag and drop, download, rename and delete. |
| **Sandbox › Access** | Expose ports on public URLs, forward ports to localhost, open the browser desktop or noVNC, SSH in Terminal, and add SSH keys. |
| **Environments** | Access toggles, repositories, variables (with reveal), secret files, versions and upgrade. |
| **Snapshots** | Named snapshots (launch from, pull to the Mac, delete) and all snapshots with file trees. |
| **Webhooks / API keys** | Create, enable or disable, rotate and delete webhooks. Create scoped API keys (read-only, full sandbox, CI or admin), view 30-day usage, rotate and revoke. |
| **Account** | Balance, plan and trial state, concurrency, start rate limits, organizations and wallets, and zero data retention. |
| **Console** | Run any `boat` CLI command. Interactive ones (`ssh`, `login`) open in Terminal. |
| **Everywhere** | ⌘K command palette, a menu bar extra with quick actions, state-change notifications, light/dark/system themes, accent colours, and an optional glass/ambient look. |

The layout adapts to the window: the sidebar collapses to icons, columns reflow, inspector panes stack, and toolbars wrap, so content fits from about 720 pt wide up to full screen.

## Requirements

- **To run:** macOS 14 Sonoma or later, on Apple Silicon or Intel. Liquid Glass needs macOS 26; earlier systems use blur material.
- **To build:** Apple's **macOS 26+ SDK and Swift 6.2+**, supplied by Command Line Tools 26+ or Xcode 26+. Full Xcode is optional. The minimum runtime version is not the minimum build-tool version. Xcode 26.2 supports macOS 15.6 and later; check [Apple's toolchain requirements](https://developer.apple.com/xcode/system-requirements) for your chosen version.
- A boat.dev API key and account. Boat usage is billed by Boat under your account's plan.
- Optional: the [`boat` CLI](https://docs.boat.dev/cli-reference), used for SSH, port forwarding, snapshot pulls and some account administration.

Install Command Line Tools with `xcode-select --install`, then check `xcrun --sdk macosx --show-sdk-version`. It must report **26 or newer**. If macOS offers only an older version, install a compatible newer toolchain or build on a newer Mac. The build script checks the SDK before compiling.

CI builds and tests Apple Silicon and Intel using Xcode 26.2. Local Command Line Tools 27 / Swift 6.4 builds are also supported. The app has no third-party Swift dependencies.

## Build & install

```sh
git clone https://github.com/moneycaringcoder/boat-gui.git
cd boat-gui
./build.sh            # or: make
```

This compiles a release build for your Mac's architecture, writes `build/Boat Deck.app`, signs it ad-hoc, installs it to `~/Applications` and launches it. Compilation or signing errors stop the build before installation. The build path links to a local bundle under `~/Library/Caches/BoatDeck/Builds/` so cloud-synced folders cannot attach metadata that breaks its signature. You can also double-click **Build Boat Deck.command** in Finder.

| Command | Does |
| --- | --- |
| `make` / `./build.sh` | Build, install and launch |
| `make build` / `./build.sh --build-only` | Build and verify `build/Boat Deck.app`; no install or launch |
| `make install` / `./build.sh --no-open` | Build and install only |
| `make test` | Run offline regression checks and build-script checks; no account needed |
| `make watch` | Rebuild every time a `.rebuild` file appears (handy for remote or automated edits) |
| `make clean` | Remove build products |

No Apple developer account or paid signing certificate is needed to build and use your own copy. This repository provides source and local build scripts; it does not publish signed releases or run an updater. Gatekeeper can treat a downloaded binary differently from one you compile yourself.

While the repository is private, cloning requires GitHub access to it.

## First run

1. Paste a boat.dev API key into the welcome screen. Alternatively, use the in-app buttons to install the CLI, log in, and let it create a key.
2. The key is stored at `~/Library/Application Support/BoatDeck/credentials` (file mode `0600`, directory mode `0700`). Change it or sign out in **Settings › Account**. It is a local plaintext credential, so protect your macOS account and backups.
3. If you use CLI features, log in to the CLI separately. Boat Deck shows the CLI account before using it, and explicitly passes the selected server and wallet. The CLI may be signed in to a different account than your API key.

Sign-out cancels API requests, clears account data and terminal history, and removes the old Keychain credential if present. An empty credential file remains as a sign-out marker so an old Keychain or `BOAT_API_KEY` environment value cannot silently sign you back in. Signing out of Boat Deck does not sign out the separately managed CLI.

### Keyboard shortcuts

| Keys | Action |
| --- | --- |
| ⌘K | Command palette (search sandboxes, actions, pages) |
| ⌘N / ⇧⌘N | New sandbox / quick launch |
| ⌘1 … ⌘8 | Jump to Home, Sandboxes, Environments, Snapshots, Webhooks, API Keys, Account, Console |
| ⌘R | Refresh |
| ⌘\\ | Toggle sidebar |
| ⌘, | Settings |
| ⌘↩ | Send prompt / launch sandbox |

## Project layout

```
Package.swift            SwiftPM executable target (macOS 14+)
build.sh                 build → bundle → sign → install
Resources/               Info.plist and the 1024 px app icon
scripts/dev-watch.sh     rebuild-on-trigger dev loop
Sources/BoatDeck/
  App.swift              @main scenes (window, Settings, menu bar extra) and commands
  Store.swift            AppState: polling, actions, activity log, preferences
  API.swift              REST client (JSON/NDJSON), errors, paginated lists and disk downloads
  Trace.swift            bounded metadata-only diagnostics
  ProcessRunner.swift    subprocess deadlines, cancellation and bounded pipe reads
  EventPager.swift       event cursors, deduplication and updates
  LocalFiles.swift       bounded previews/uploads and atomic download saving
  System.swift           credential file, Keychain migration, boat CLI bridge, Terminal launcher
  JSON.swift             lenient JSON value + Record helpers
  Theme.swift            colours, glass, ambient background, preferences, VState
  Components.swift       buttons, chips, status dots, gauges, toasts, fields, dialogs
  Layout.swift           width-aware Page/PageHeader, flat sections, MetricStrip, FlowLayout
  Shell.swift            root view, sidebar
  HomeView.swift         dashboard
  SandboxesView.swift    list/grid, quick actions, new-sandbox sheet
  SandboxDetail.swift    detail header, tabs, overview, access, snapshots
  AgentView.swift        agent prompts and event log
  TerminalFiles.swift    exec terminal and file browser/editor
  EnvironmentsView.swift environments
  LibraryViews.swift     snapshots, webhooks, API keys
  AccountView.swift      account/billing and CLI console
  Overlays.swift         command palette, onboarding, menu bar UI
  SettingsView.swift     settings window
Tests/BoatDeckTests/      offline regression checks (plain Swift, no XCTest required)
.github/workflows/ci.yml  build and test only; no publishing
```

## Implementation notes

- **No SwiftUI macros.** On the macOS 27 SDK, `@State`, `@Namespace` and friends are macros whose plugins ship only with full Xcode. The code therefore uses `VState` (a small property wrapper backed by `@StateObject`) and typealiases, so it builds with the Command Line Tools alone.
- **No `.repeatForever` animations.** Continuous motion (status pulse, spinners, shimmer, waves) is computed from `TimelineView` time. A repeating animation started from an ObservableObject change can leak into everything else updated in the same transaction. Timelines pause while the window is inactive.
- **Quiet polling.** Sandbox state is polled on an interval (Settings › General). Published state is only reassigned when it actually changes, so idle refreshes don't redraw the UI.
- **Lenient decoding.** Responses are decoded into a dynamic `JSON` type and read with fallbacks, so new or renamed API fields don't break the app. Every detail view also shows the raw fields.
- **One write attempt.** Failed API writes and interrupted command streams are never replayed through another endpoint or credential. A lost response can mean the operation already happened; inspect its result before retrying manually.
- **Agent events** follow ascending cursors and drain all pages before polling again. The last page is revisited to catch updated streaming events.
- **Bounded output.** Terminal and console views keep recent output only. File previews are limited to 5 MB and uploads to 16 MB; downloads and artifact archives are saved through temporary files on disk. Use the CLI for larger uploads. Stopping a terminal stream stops watching; it does not guarantee that the remote command stops.

## Diagnostics

**Settings › Advanced › Log API traffic** writes only HTTP method, route template, status, elapsed time and byte count to `~/Library/Logs/BoatDeck/api-metadata.log`. It excludes headers, bodies, query values and resource identifiers. The log is private (`0600`), capped at 1 MiB, and disabled by default.

Older versions wrote response bodies to `api-trace.log`. Those old logs are no longer used and may contain secrets; remove them before sharing diagnostic files.

## Known limitations

- Agent prompting requires the provider (e.g. Codex or Claude Code) to be configured on boat.dev's Agents page. The app links there when the API reports it.
- Some API keys can't list conversations or the provider/model catalog. The app then falls back to default choices.
- Some account administration, including key rotation/revocation, requires the CLI's browser-authenticated session. API permission errors remain visible; the app never escalates them through a CLI fallback.
- The deployment target is macOS 14; CI currently exercises macOS 15 with SDK 26.2. Older-runtime behavior still benefits from manual testing.

## Contributing and license

Small fixes and improvements are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the checks to run. Boat Deck is an independent client, not an official Boat app.

[MIT license](LICENSE).
