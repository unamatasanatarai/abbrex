# AbbrEx

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="AbbrEx Icon" />
</p>

<p align="center">
  <strong>Native macOS abbreviation & snippet expansion engine with cursor-anchored candidate popouts, dynamic templating, and zero-allocation performance.</strong>
</p>

<p align="center">
  <a href="https://github.com/unamatasanatarai/abbrex/releases/latest">
    <img src="https://img.shields.io/badge/Download-Latest_DMG-blue?style=for-the-badge&logo=apple" alt="Download Latest DMG" />
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-GPL_v2.0-green?style=for-the-badge" alt="License: GPL v2.0" />
  </a>
  <img src="https://img.shields.io/badge/macOS-12.0+-lightgrey?style=for-the-badge&logo=apple" alt="macOS 12.0+" />
</p>

<p align="center">
  <a href="#key-features">Features</a> •
  <a href="#download--installation">Download & Install</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#dynamic-templates">Templates</a> •
  <a href="#permissions">Permissions</a> •
  <a href="#development-and-building">Development</a> •
  <a href="#license">License</a>
</p>

---

AbbrEx is a lightweight, zero-dependency menu bar application for macOS that expands short keystroke abbreviations into full snippets, disclaimers, boilerplate templates, and dynamic text across any macOS application.

Instead of silently replacing text or forcing intrusive modal dialogs, AbbrEx monitors keystrokes through an in-memory prefix tree, anchors a floating candidate popout directly to your active text insertion caret, and replaces text in-place the moment you trigger expansion.

---

## Download & Installation

### Option 1: Install with DMG (Recommended)

1. **Download the DMG**:
   Get the latest release package directly from the [GitHub Releases page](https://github.com/unamatasanatarai/abbrex/releases/latest):
   👉 **[Download Latest AbbrEx DMG](https://github.com/unamatasanatarai/abbrex/releases/latest)**

2. **Mount and Install**:
   - Double-click the downloaded `AbbrEx-1.0.0.dmg` file to open it.
   - Drag **AbbrEx.app** into the **Applications** shortcut folder.

3. **Launch and Grant Accessibility**:
   - Launch **AbbrEx** from your Applications folder or Spotlight (`⌘ Space`).
   - On first launch, grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility). AbbrEx requires this permission to monitor abbreviation keystrokes and detect your typing caret position.

---

### Option 2: Build the DMG Locally

If you prefer building from source, you can generate your own standalone DMG installer using `make`:

```bash
git clone git@github.com:unamatasanatarai/abbrex.git
cd abbrex
make dmg
open build/AbbrEx-1.0.0.dmg
```

---

### Option 3: Quick Direct Install via Make

```bash
git clone git@github.com:unamatasanatarai/abbrex.git
cd abbrex
make install
```

This compiles `AbbrEx.app`, signs the binary, and installs it directly into `/Applications/AbbrEx.app`.

---

## Key Features

### 📍 Cursor-Anchored Candidate Popout (HUD)
Detects the exact screen coordinates of your active text insertion point across macOS applications using native Accessibility APIs (`AXUIElement`). The floating candidate list dynamically sizes and anchors to your cursor, automatically flipping vertically or horizontally to stay within visible screen bounds.

### ⚡ Sub-Millisecond O(k) Trie Engine
Keystrokes are buffered against an in-memory prefix tree with zero-allocation Unicode retrieval directly from `CGEvent`. Prefix lookups complete in under 0.2 milliseconds, ensuring native typing responsiveness with zero perceptible input lag.

### 🧩 Dynamic Template Variables
Templates evaluate dynamically on demand during expansion:
* `{{date}}` / `{{date:YYYY-MM-DD}}`: Current calendar dates with custom formatting
* `{{time}}`: Current system time
* `{{clipboard}}`: Current pasteboard contents

### ⌨️ Keyboard-Driven Navigation & Shortcuts
* Navigate candidate matches with **Arrow Up/Down** or Vim/Emacs keybindings (**`Ctrl+j` / `Ctrl+k`**, **`Ctrl+n` / `Ctrl+p`**).
* Commit expansions instantly with **`Tab`**, **`Enter`**, **`Ctrl+l`**, or a mouse click.
* Press **`Esc`** at any time to dismiss the candidate HUD without interrupting your typing flow.

### 🛠️ Intuitive Library Manager
* **Inlined Snippet Previews**: Browse snippets in a clean master-detail sidebar displaying both abbreviation prefix and content previews.
* **Instant Search Filter**: Quick search filter with instant **`Esc`** key clearing.
* **Fast Snippet Creation**: Hit **`+`** to create a new abbreviation. If empty, pressing **`Esc`** automatically cancels creation and returns the cursor directly to search.
* **Hover Deletion with Undo Protection**: Delete snippets on hover with an undo restore bar. Empty drafts are automatically pruned on click-away or cancellation without annoying undo prompts.
* **Non-Blocking Background Windowing**: Pressing **`⌘W`** closes the Preferences window while keeping the expander active in the background.

### 💾 Flexible JSON Import & Export
* Export and import your snippet library via the top menu bar (**File → Export / Import**) or the in-app options menu (`...`).
* Supports native AbbrEx JSON schemas, optional field schemas, and simple key-value dictionaries (`{ ":prefix": "expansion" }`) without requiring snippet IDs.
* Automatically strips empty drafts on export to keep your backups pristine.

### 🛡️ Safe Double-Tap `⌘Q` Protection
Prevents accidental app termination while typing with a double-tap shortcut guard. Pressing **`⌘Q`** once displays a floating HUD prompt (*"Press ⌘Q again to quit"*); pressing it again within 1.5 seconds confirms termination.

### 🌓 Native Menu Bar Integration
Features an adaptive template status bar icon that conforms to both macOS Dark Mode and Light Mode. Left-click opens Preferences; right-click reveals a quick action context menu.

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

AbbrEx supports embedded dynamic variables directly within expansion text:

| Variable | Description | Output Example |
| :--- | :--- | :--- |
| `{{date}}` | Formatted calendar date | `Oct 10, 2026` |
| `{{date:YYYY-MM-DD}}` | ISO 8601 date formatting | `2026-10-10` |
| `{{date:YYYY/MM/DD}}` | Custom slash date formatting | `2026/10/10` |
| `{{time}}` | Current 24-hour time | `11:05:30` |
| `{{clipboard}}` | Injects current pasteboard text | Output of your latest copy action |

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

## Development and Building

The project includes automated verification and build targets managed via the `Makefile`:

```bash
make test             # Run native Swift unit test suite
make build            # Compile and code-sign build/AbbrEx.app
make run              # Build and launch AbbrEx.app
make launch           # Launch AbbrEx.app without rebuilding (preserves TCC permissions)
make dmg              # Generate standalone macOS DMG installer package
make release-dry-run  # Preview GitHub release tagging and packaging
make clean            # Remove build artifacts and temporary binaries
```

---

## License

This project is licensed under the terms of the [GNU General Public License v2.0 (GPL-2.0)](LICENSE).
