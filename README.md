# HrefTo

A native macOS browser picker and URL router. Set HrefTo as your default browser and it routes links to the right browser based on rules you define — or shows a quick picker so you can choose.

## Features

- **Rule-based routing** — route URLs by domain, path, source app, modifier keys, or any combination using ordered rules with first-match-wins logic
- **Picker UI** — floating window near your cursor with keyboard shortcuts (Cmd+1-9) for fast selection
- **Quick rules** — check "Always for google.com" or "Always from Slack" in the picker to create rules on the spot
- **Browser profiles** — supports Chromium profiles (Chrome, Edge, Brave, Arc, Vivaldi)
- **NSPredicate engine** — conditions compile to NSPredicate for flexible matching, with a text editor for power users
- **Menu bar app** — lives in your menu bar, no dock icon by default
- **URL scheme API** — `hrefto://open`, `hrefto://pick`, `hrefto://toggle` for automation

## Requirements

- macOS 14 (Sonoma) or later
- [Task](https://taskfile.dev) (for building)

## Build & Run

```sh
task build   # compile and create app bundle
task run     # build + launch
task check   # type-check only (fast, no linking)
task clean   # remove build artifacts
```

The app bundle is output to `build/HrefTo.app`.

## Setup

1. Build and launch: `task run`
2. Click the menu bar icon and select "Set as Default Browser"
3. Open any link — HrefTo's picker appears
4. Choose a browser, optionally check "Always for this domain" to create a rule

## Configuration

Config is stored at `~/Library/Application Support/HrefTo/config.json`. You can edit it directly or use the Settings UI (menu bar icon > Open Settings).

### Rules

Rules are evaluated in order. Each rule has:
- **Conditions** (ALL/ANY/NONE match mode) against URL host, path, source app, modifier keys, etc.
- **Action**: open in a specific browser/profile, show picker, or open in frontmost browser

### Context variables available in rules

| Variable | Description |
|----------|-------------|
| `host` | Hostname (e.g. `docs.google.com`) |
| `path` | URL path |
| `url` | Full URL string |
| `sourceBundleId` | Bundle ID of the app that opened the link |
| `modifiers` | Modifier keys held (`shift option command control`) |
| `runningBrowserCount` | Number of enabled browsers currently running |
| `isLocalFile` | Whether URL is a local file |

## URL Scheme

| URL | Action |
|-----|--------|
| `hrefto://open?url=<URL>&browser=<bundleId>&profile=<id>` | Open URL in specific browser/profile |
| `hrefto://pick?url=<URL>` | Show picker for URL |
| `hrefto://toggle` | Toggle enabled/disabled |

## License

MIT
