# HrefTo - Design Document

A native macOS app that intercepts URL opens and routes them to the right browser based on configurable rules.

## Overview

HrefTo registers as the system default browser. When any app opens a URL, macOS hands it to HrefTo, which either:
1. Auto-routes to a browser based on matching rules, or
2. Shows a picker UI letting the user choose — with an option to create a rule on the spot.

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI (settings window, picker popup, rule editor)
- **Menu bar:** AppKit (NSStatusItem)
- **Rules engine:** NSPredicate (native Foundation framework)
- **Persistence:** JSON file (`~/Library/Application Support/HrefTo/config.json`)
- **Target:** macOS 14 (Sonoma)+
- **Build:** Xcode project (Swift Package Manager for any deps)

## Architecture

```
HrefTo.app
├── App entry point (menu bar app, no dock icon by default)
├── URL handler (receives URLs from macOS)
├── Browser detector (finds installed browsers + profiles)
├── Rule engine (evaluates NSPredicate rules in order)
├── Picker UI (floating SwiftUI window near cursor)
├── Quick Rule creator (inline from picker)
├── Settings UI (SwiftUI window with tabs)
└── URL scheme API (hrefto://)
```

---

## Core Components

### 1. Default Browser Registration

Info.plist declares handlers for `http`, `https` schemes and `public.html`/`public.xhtml` UTIs. On first launch, prompts the user to set HrefTo as default browser.

### 2. Browser Detection & Profiles

Discovers installed browsers via Launch Services (`LSCopyAllHandlersForURLScheme`). User can enable/disable/reorder browsers in settings.

**Profile support** for Chromium-based browsers (Chrome, Edge, Brave, Arc, Vivaldi) by reading `~/Library/Application Support/<Browser>/Local State` JSON for profile directories. Safari profiles via bookmark container detection.

Each browser entry:
```json
{
  "bundleId": "com.google.Chrome",
  "name": "Google Chrome",
  "path": "/Applications/Google Chrome.app",
  "enabled": true,
  "profiles": [
    { "id": "Default", "name": "Personal" },
    { "id": "Profile 1", "name": "Work" }
  ]
}
```

### 3. Rule Engine

Rules are evaluated **in order, first match wins**. The last rule is always the **default/fallback** rule (cannot be reordered above other rules).

#### Rule Structure

Each rule has:
- **Name** — human-readable label
- **Enabled** — toggle without deleting
- **Match mode** — ALL conditions must match, ANY condition matches, or NONE match
- **Conditions** — one or more criteria (see below)
- **Behaviour** — what to do when the rule matches (see below)

#### Condition Types

| Condition | Description | Example |
|-----------|-------------|---------|
| **URL** | Match against full URL, host, path, or query | `host ENDSWITH "google.com"` |
| **Source App** | Bundle ID or path of the app that opened the link | `sourceBundleId == "com.tinyspeck.slackmacgap"` |
| **Modifier Keys** | Keys held when the link was clicked | `modifiers CONTAINS "shift"` |
| **Running Browsers** | Number of enabled browsers currently running | `runningBrowserCount > 1` |
| **Link Type** | Whether it's a web URL or a local HTML file | `isLocalFile == true` |

All conditions compile down to a single NSPredicate evaluated against a context dictionary.

#### Context Variables (available in predicates)

| Variable | Type | Description |
|----------|------|-------------|
| `url` | String | Full URL string |
| `scheme` | String | `http`, `https`, or `file` |
| `host` | String | Hostname (e.g., `docs.google.com`) |
| `path` | String | URL path component |
| `query` | String | Query string |
| `fragment` | String | Fragment/anchor |
| `sourceApp` | String | Bundle path of source app |
| `sourceBundleId` | String | Bundle ID of source app |
| `sourceName` | String | Display name of source app |
| `modifiers` | String | Space-separated modifier keys held: `shift option command control function` |
| `runningBrowserCount` | Int | Number of enabled browsers currently running |
| `isLocalFile` | Bool | Whether URL points to a local file |
| `isHandoff` | Bool | Whether URL came via Handoff |

#### Behaviour (what happens when rule matches)

| Behaviour | Description |
|-----------|-------------|
| **Open in browser** | Open URL in a specific browser (optionally a specific profile) |
| **Show picker (all)** | Show picker with all enabled browsers |
| **Show picker (running)** | Show picker with only currently-running browsers |
| **Open in frontmost** | Open in whichever enabled browser is currently active |

#### Example Rules

```
Rule: "Work Google stuff"
  Conditions (ALL):
    - host ENDSWITH "google.com"
    - sourceBundleId == "com.tinyspeck.slackmacgap"
  Behaviour: Open in Chrome / Work profile

Rule: "Shift = always pick"
  Conditions (ANY):
    - modifiers CONTAINS "shift"
  Behaviour: Show picker (all)

Rule: "Zoom links"
  Conditions (ALL):
    - host ENDSWITH "zoom.us"
    - path BEGINSWITH "/j/"
  Behaviour: Open in zoom.us app

Rule: "Default"
  Conditions: (always matches)
  Behaviour: Open in Safari
```

### 4. Picker UI

A floating borderless SwiftUI window that appears **near the mouse cursor**. Design:

```
┌─────────────────────────────────────────┐
│  🔗 docs.google.com/spreadsheets/d/...  │
│  from: Slack                            │
├─────────────────────────────────────────┤
│  [Safari icon] Safari           ⌘1      │
│  [Chrome icon] Chrome (Work)    ⌘2      │
│  [Chrome icon] Chrome (Personal)⌘3      │
│  [Firefox icon] Firefox         ⌘4      │
├─────────────────────────────────────────┤
│  ☐ Always for this domain [from Slack]  │
│              [Create Rule...]            │
└─────────────────────────────────────────┘
```

Features:
- Shows URL (truncated) and source app name
- Browser icons with names and profile indicators
- Keyboard shortcuts ⌘1-⌘9 for quick selection
- Click or keyboard to select
- **"Always for this domain" checkbox** — creates a quick rule on selection
- **"Create Rule..." button** — opens full rule editor pre-filled with current context
- Dismisses on: selection, Escape, click outside, or after timeout (configurable)
- Remembers window position preference (near cursor vs center screen)

### 5. Quick Rule Creation (from Picker)

When the user checks "Always for this domain" and picks a browser, HrefTo automatically creates a rule:
- Name: `"domain.com → Chrome (Work)"`
- Condition: `host ENDSWITH "domain.com"` (uses registrable domain, not full host)
- Behaviour: Open in selected browser/profile

When source app context is available, offers an extended version:
- `"domain.com from Slack → Chrome (Work)"`
- Adds `sourceBundleId == "..."` condition

The "Create Rule..." button opens the full rule editor pre-populated with:
- Current URL → suggested host condition
- Current source app → suggested source condition
- Selected browser (if any) → suggested behaviour

### 6. Settings Window

Accessible from menu bar icon. Three tabs:

#### Browsers Tab
- List of detected browsers with icons
- Drag to reorder (order = picker display order)
- Enable/disable toggle per browser
- Expand to show profiles (with individual enable/disable)
- "Re-scan" button to re-detect browsers
- HrefTo excludes itself from the list

#### Rules Tab
- Ordered list of rules (drag to reorder)
- Default rule pinned at bottom (can edit behaviour, not conditions)
- Each rule shows: name, enabled toggle, summary of conditions, target browser
- Double-click or Edit button → opens rule editor sheet
- Add (+) / Remove (-) buttons
- Duplicate rule option

#### Rule Editor (sheet/modal)
- **Name** field
- **Match mode** picker: All / Any / None of the following
- **Conditions list** with +/- buttons:
  - Each row: [field dropdown] [operator dropdown] [value field]
  - Field: URL Host / URL Path / URL (full) / Source App / Modifier Keys / Running Browsers / Link Type / Handoff
  - Operator varies by field: is / is not / contains / begins with / ends with / matches (regex)
- **Behaviour** picker:
  - Open in: [browser dropdown] [profile dropdown]
  - Show picker: all / running only
  - Open in frontmost browser
- **NSPredicate preview** (read-only, shows the compiled predicate string for power users)
- **Test URL** field — paste a URL and see if this rule would match
- **Enabled** checkbox

#### General Tab
- Launch at login toggle (via `SMAppService`)
- Show in Dock toggle
- Picker appearance: near cursor / center screen
- Picker timeout (seconds, 0 = no timeout)
- "Set as Default Browser" button with status indicator
- Reset all settings

### 7. Menu Bar

Small link/arrow icon in the menu bar. Menu:
- **Enabled** (checkmark toggle — when disabled, passes URLs straight to fallback browser)
- ---
- Open Settings... (⌘,)
- Set as Default Browser
- ---
- About HrefTo
- Quit HrefTo (⌘Q)

### 8. URL Scheme API

`hrefto://` scheme for external automation:

| URL | Action |
|-----|--------|
| `hrefto://open?url=<URL>&browser=<bundleId>&profile=<id>` | Open URL in specific browser/profile |
| `hrefto://pick?url=<URL>` | Show picker for URL |
| `hrefto://toggle` | Toggle enabled/disabled |

---

## URL Handling Flow

```
1. macOS sends URL to HrefTo
2. Capture context:
   a. Parse URL into components
   b. Identify source app (frontmost app via NSWorkspace)
   c. Capture modifier keys (via CGEvent / NSEvent.modifierFlags)
   d. Count running browsers
   e. Detect Handoff / local file
3. Build context dictionary for NSPredicate evaluation
4. Evaluate rules in order (skip disabled rules):
   a. Compile conditions into NSPredicate
   b. Evaluate against context
   c. First match → execute behaviour
5. If behaviour is "open in browser":
   a. Resolve browser app URL and profile args
   b. NSWorkspace.shared.open() with configuration
6. If behaviour is "show picker":
   a. Filter browser list (all vs running only)
   b. Show picker window at cursor position
   c. On selection → open URL in chosen browser
   d. If "always" checkbox checked → create quick rule
7. If no rule matched → execute default rule behaviour
```

---

## Config File

`~/Library/Application Support/HrefTo/config.json`:

```json
{
  "version": 1,
  "browsers": [
    {
      "bundleId": "com.apple.Safari",
      "name": "Safari",
      "enabled": true,
      "profiles": []
    },
    {
      "bundleId": "com.google.Chrome",
      "name": "Google Chrome",
      "enabled": true,
      "profiles": [
        { "id": "Default", "name": "Personal", "enabled": true },
        { "id": "Profile 1", "name": "Work", "enabled": true }
      ]
    }
  ],
  "rules": [
    {
      "id": "uuid-1",
      "name": "Google -> Chrome Work",
      "enabled": true,
      "matchMode": "all",
      "conditions": [
        { "field": "host", "operator": "endsWith", "value": "google.com" }
      ],
      "behaviour": {
        "type": "openInBrowser",
        "bundleId": "com.google.Chrome",
        "profileId": "Profile 1"
      }
    },
    {
      "id": "uuid-2",
      "name": "Shift = pick",
      "enabled": true,
      "matchMode": "any",
      "conditions": [
        { "field": "modifiers", "operator": "contains", "value": "shift" }
      ],
      "behaviour": {
        "type": "showPicker",
        "filter": "all"
      }
    },
    {
      "id": "default",
      "name": "Default",
      "enabled": true,
      "matchMode": "all",
      "conditions": [],
      "behaviour": {
        "type": "openInBrowser",
        "bundleId": "com.apple.Safari",
        "profileId": null
      }
    }
  ],
  "settings": {
    "launchAtLogin": false,
    "showInDock": false,
    "pickerPosition": "cursor",
    "pickerTimeoutSeconds": 0,
    "enabled": true
  }
}
```

---

## Project Structure

```
HrefTo/
├── HrefTo.xcodeproj
├── HrefTo/
│   ├── HrefToApp.swift              # App entry, menu bar, URL handling
│   ├── Info.plist                    # URL schemes, UTIs, browser registration
│   ├── HrefTo.entitlements          # App sandbox (if needed), network
│   ├── Models/
│   │   ├── Browser.swift            # Browser + profile model
│   │   ├── Rule.swift               # Rule, condition, behaviour models
│   │   └── AppConfig.swift          # Top-level config, persistence
│   ├── Services/
│   │   ├── BrowserDetector.swift    # Discover browsers + profiles
│   │   ├── RuleEngine.swift         # Compile conditions → NSPredicate, evaluate
│   │   ├── URLHandler.swift         # Receive URLs, build context, dispatch
│   │   └── ModifierKeyMonitor.swift # Track current modifier key state
│   ├── Views/
│   │   ├── PickerWindow.swift       # NSPanel host for picker (borderless, floating)
│   │   ├── PickerView.swift         # SwiftUI picker content
│   │   ├── SettingsView.swift       # TabView container
│   │   ├── BrowsersTab.swift       # Browser list management
│   │   ├── RulesTab.swift           # Rule list + reordering
│   │   ├── RuleEditorView.swift     # Full rule editor (sheet)
│   │   ├── QuickRuleSheet.swift     # Simplified rule from picker
│   │   └── GeneralTab.swift         # General settings
│   └── Assets.xcassets
├── DESIGN.md
└── README.md
```

---

## Key Implementation Details

### Registering as a browser (Info.plist)

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>Web URL</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>http</string>
      <string>https</string>
      <string>hrefto</string>
    </array>
  </dict>
</array>
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key>
    <string>HTML Document</string>
    <key>CFBundleTypeRole</key>
    <string>Viewer</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>public.html</string>
      <string>public.xhtml</string>
      <string>public.url</string>
    </array>
  </dict>
</array>
```

### Compiling rule conditions to NSPredicate

```swift
func compilePredicate(conditions: [Condition], matchMode: MatchMode) -> NSPredicate {
    let predicates = conditions.map { condition -> NSPredicate in
        switch condition.operator {
        case .endsWith:
            return NSPredicate(format: "%K ENDSWITH[cd] %@", condition.field, condition.value)
        case .beginsWith:
            return NSPredicate(format: "%K BEGINSWITH[cd] %@", condition.field, condition.value)
        case .contains:
            return NSPredicate(format: "%K CONTAINS[cd] %@", condition.field, condition.value)
        case .equals:
            return NSPredicate(format: "%K ==[cd] %@", condition.field, condition.value)
        case .notEquals:
            return NSPredicate(format: "%K !=[cd] %@", condition.field, condition.value)
        case .matches:
            return NSPredicate(format: "%K MATCHES %@", condition.field, condition.value)
        }
    }

    switch matchMode {
    case .all: return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    case .any: return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    case .none: return NSCompoundPredicate(notPredicateWithSubpredicate:
        NSCompoundPredicate(orPredicateWithSubpredicates: predicates))
    }
}
```

### Building evaluation context

```swift
func buildContext(url: URL, sourceApp: NSRunningApplication?, modifiers: NSEvent.ModifierFlags) -> [String: Any] {
    return [
        "url": url.absoluteString,
        "scheme": url.scheme ?? "",
        "host": url.host ?? "",
        "path": url.path,
        "query": url.query ?? "",
        "fragment": url.fragment ?? "",
        "sourceApp": sourceApp?.bundleURL?.path ?? "",
        "sourceBundleId": sourceApp?.bundleIdentifier ?? "",
        "sourceName": sourceApp?.localizedName ?? "",
        "modifiers": modifierString(modifiers),
        "runningBrowserCount": countRunningBrowsers(),
        "isLocalFile": url.isFileURL,
        "isHandoff": false // set by Handoff handler
    ]
}
```

### Opening URL in a specific browser with profile

```swift
func openURL(_ url: URL, in browser: Browser, profile: BrowserProfile?) {
    let config = NSWorkspace.OpenConfiguration()

    if let profile = profile, browser.isChromiumBased {
        // Chromium: --profile-directory='Profile 1'
        config.arguments = ["--profile-directory=\(profile.id)", url.absoluteString]
    }

    let browserURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleId)!
    NSWorkspace.shared.open([url], withApplicationAt: browserURL, configuration: config)
}
```

### Modifier key capture

```swift
// Capture at the moment the URL event arrives
let currentModifiers = NSEvent.modifierFlags
let modifierString = [
    currentModifiers.contains(.shift) ? "shift" : nil,
    currentModifiers.contains(.option) ? "option" : nil,
    currentModifiers.contains(.command) ? "command" : nil,
    currentModifiers.contains(.control) ? "control" : nil,
    currentModifiers.contains(.function) ? "function" : nil,
].compactMap { $0 }.joined(separator: " ")
```

### Picker window positioning

```swift
// Position near cursor using NSPanel
let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
panel.level = .floating
panel.isMovableByWindowBackground = false

let mouseLocation = NSEvent.mouseLocation
// Position above cursor, centered horizontally
panel.setFrameOrigin(NSPoint(
    x: mouseLocation.x - panel.frame.width / 2,
    y: mouseLocation.y + 10
))
```

---

## MVP Feature Checklist

### Must have (v1.0)
- [x] Register as default browser (http/https)
- [ ] Detect installed browsers
- [ ] Detect Chromium browser profiles
- [ ] Picker UI near cursor with keyboard shortcuts
- [ ] Rule engine with ordered rules + default fallback
- [ ] Conditions: URL host, path, source app, modifier keys, running browser count
- [ ] Behaviours: open in browser/profile, show picker (all/running), open in frontmost
- [ ] Quick rule creation from picker ("Always for this domain")
- [ ] Full rule editor in settings
- [ ] Menu bar icon with enable/disable toggle
- [ ] Settings: browsers tab, rules tab, general tab
- [ ] Launch at login
- [ ] Persist config to JSON
- [ ] URL scheme API (hrefto://open, hrefto://pick)

### Nice to have (v1.x)
- [ ] Handoff detection
- [ ] "Create Rule..." from picker opens full editor pre-filled
- [ ] Rule test/preview in editor (paste URL, see if matches)
- [ ] NSPredicate preview for power users
- [ ] Export/import config
- [ ] Keyboard shortcut to force-show picker (global hotkey)
- [ ] Safari profile support
- [ ] Picker remembers last-used browser per domain (frecency)
