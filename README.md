# AbbrEx

<p align="center">
  <img src="Resources/AppIcon.png" width="120" height="120" alt="AbbrEx Icon" />
</p>

<p align="center">
  <strong>Native macOS abbreviation expansion engine with cursor-anchored candidate popouts and dynamic templating.</strong>
</p>

<p align="center">
  <a href="#key-features">Features</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#dynamic-templates">Templates</a> •
  <a href="#development">Development</a>
</p>

---

AbbrEx is a lightweight, zero-dependency menu bar application for macOS that turns short keystroke prefixes into full-length snippets, disclaimers, QA bug reports, and dynamic text templates across any application. 

Instead of silently replacing text or forcing modal dialogs, AbbrEx monitors keystrokes through an in-memory prefix tree, anchors a floating candidate popout directly to your active text cursor, and replaces text in-place the moment you trigger expansion.

---

## Why AbbrEx?

Writing repetitive text—legal notices, bug reproduction steps, markdown skeletons, or email signatures—slows down writing flow and leads to inconsistent communication.

* **Frictionless Typing**: Type short prefixes like `:sig`, `:disc`, or `qa-bug` anywhere in macOS without context switching.
* **Visual Confirmation**: A non-intrusive floating HUD shows matching expansions next to your cursor with keyboard navigation before committing.
* **Context-Aware Templating**: Auto-populate current dates, timestamps, and clipboard contents.
* **Native & Lightweight**: Built strictly in Swift, AppKit, and SwiftUI with zero external dependencies, running silently in your menu bar.

---

## Key Features

### Cursor-Anchored Candidate HUD
Detects the exact screen coordinates of your active text insertion point across macOS applications using Accessibility APIs. The floating popout dynamically sizes and anchors to your cursor, automatically flipping vertically or horizontally to avoid screen edges.

### O(k) Prefix Trie Engine
Keystrokes are buffered in real time against an in-memory prefix tree. Candidate lookups complete in under 0.2 milliseconds, ensuring typing remains responsive with no perceptible input lag.

### Dynamic Variable Templates
Templates evaluate on demand during expansion:
* `{{date}}` / `{{date:YYYY-MM-DD}}`: Formatted calendar dates
* `{{time}}`: Current system time
* `{{clipboard}}`: Current pasteboard contents

### Developer-Friendly Navigation
Navigate candidate lists with arrow keys or Vim/Emacs bindings (`Ctrl+j` / `Ctrl+k`, `Ctrl+n` / `Ctrl+p`). Commit expansions instantly using `Tab`, `Enter`, `Ctrl+l`, or a mouse click.

### Continuous Autosave & Library Management
Edit prefixes and expansions in a unified two-column library manager. All changes are saved automatically to persistent local storage (`~/Library/Application Support/AbbrEx/library.json`).

### Interactive Live Sandbox
Test abbreviation expansions and observe keystroke buffer states, trie lookup performance, and engine lifecycle transitions in real time without switching apps.

### Native Menu Bar Presence
Designed with an adaptive template status bar icon that automatically switches between dark and light appearances, plus non-intrusive permission warnings when Accessibility access is needed.

---

## How It Works

```text
1. Type a prefix           Type an abbreviation prefix (e.g. ":sig" or "qa-bug") in any macOS app.
        ↓
2. Cursor Popout Appears   A floating HUD appears next to your typing caret showing available matches.
        ↓
3. Navigate & Select       Navigate with Arrow keys or Ctrl+j/k, then press Tab, Enter, or Ctrl+l.
        ↓
4. In-Place Expansion      AbbrEx deletes the typed prefix and evaluates template variables.
```

---

## Dynamic Templates

AbbrEx supports embedded template variables directly within the expansion text editor:

| Variable | Description | Output Example |
| :--- | :--- | :--- |
| `{{date}}` | Formatted calendar date | `2026-10-09` |
| `{{date:YYYY/MM/DD}}` | Custom date formatting | `2026/10/09` |
| `{{time}}` | Current system time | `21:28` |
| `{{clipboard}}` | Injects current pasteboard text | Output of your latest copy action |

---

## Quick Start

### Prerequisites
* macOS 12.0 (Monterey) or later
* Xcode Command Line Tools (`xcode-select --install`)

### Build and Launch

Clone the repository and launch the app using `make`:

```bash
git clone git@github.com:unamatasanatarai/abbrex.git
cd abbrex
make run
```

To launch without rebuilding (preserving Accessibility TCC approval):

```bash
make launch
```

### Install to Applications

```bash
make install
```

This compiles `AbbrEx.app`, signs the binary, and installs it into `/Applications/AbbrEx.app`.

---

## Permissions

AbbrEx uses the macOS Accessibility API (`AXUIElement`) and `CGEventTap` to detect active caret screen positions and inject expanded text templates.

1. On first launch, macOS prompts for **Accessibility** permission.
2. If permissions are missing, AbbrEx displays a banner with a direct shortcut to **System Settings → Privacy & Security → Accessibility**.
3. Enable **AbbrEx** in the list to activate global expansion.

To reset permissions during testing:

```bash
make revoke
```

---

## Development & Testing

The project includes automated verification and build targets managed via the `Makefile`:

```bash
make test             # Run native Swift unit test suite
make build            # Compile and code-sign build/AbbrEx.app
make dmg              # Generate standalone macOS DMG installer
make release-dry-run  # Preview GitHub release tagging and packaging
make clean            # Remove build artifacts and reset permissions
```

### Architecture Overview

```text
Sources/AbbreviationExpander/
├── Core/
│   ├── Models.swift          # Expansion payload and engine state models
│   ├── Trie.swift            # O(k) prefix tree lookup structure
│   ├── StateMachine.swift    # Keystroke buffer lifecycle and state transitions
│   ├── TemplateEngine.swift  # Variable evaluation (date, time, clipboard)
│   ├── CaretTracker.swift    # Screen position detection via AXUIElement
│   ├── TextReplacer.swift    # Automated backspace deletion and text insertion
│   ├── LibraryStorage.swift  # Atomic JSON persistence (~/Library/Application Support/AbbrEx)
│   └── AppConfig.swift       # Overlay geometry and delay configuration
├── Services/
│   └── EventMonitor.swift    # Global CGEventTap keystroke interception
└── UI/
    ├── AppViewModel.swift    # Reactive state management and synchronization
    ├── OverlayPanel.swift    # Floating non-activating NSPanel window
    ├── CandidateListView.swift # Cursor-anchored candidate selection UI
    └── PreferencesView.swift # Library editor, sandbox, and permission management
```

---

## License

Copyright © 2026. All rights reserved.
