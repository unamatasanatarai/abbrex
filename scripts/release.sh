#!/bin/bash
set -e

APP_NAME="AbbrEx"
BUNDLE_ID="com.citizen.AbbreviationExpander"
VERSION=$(grep 'public static let version' Sources/AbbreviationExpander/Core/AppConfig.swift | sed -E 's/.*"([^"]+)".*/\1/')
[ -z "$VERSION" ] && VERSION="1.0.1"
BUILD_DIR="build"
DMG_NAME="AbbrEx-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
fi

# Fallback: If GITHUB_TOKEN environment variable is invalid, unset it to use the local keyring
if [ -n "$GITHUB_TOKEN" ]; then
    if ! gh auth status >/dev/null 2>&1; then
        unset GITHUB_TOKEN
    fi
fi

# Detect previous release tag
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v1.0.0")

# Collect commit logs since previous tag
COMMIT_LOG=""
if [ -n "$PREV_TAG" ]; then
    COMMIT_LOG=$(git log "$PREV_TAG..HEAD" --pretty=format:"* %s (%h)" 2>/dev/null || true)
fi

# Build detailed release notes listing all changes since previous release
RELEASE_NOTES=$(
    cat <<EOF
## AbbrEx v$VERSION

### 🚀 Default Snippets Overhaul
* Replaced verbose boilerplate with clean, everyday essentials:
  * \`gg\` ➔ \`good game\`
  * \`:shrug\` ➔ \`¯\\_(ツ)_/¯\`
  * \`ty\` ➔ \`Thank you!\`
  * \`eus\` ➔ \`unamatasanatarai@gmail.com\`
  * \`:buu\` ➔ Homebrew cache cleanup & greedy upgrade command

### 🧪 Comprehensive Native Test Suite
* Added 16-suite native unit test coverage across the entire codebase:
  * **Core Suite**: Exhaustive Trie prefix tree indexing, dynamic template variable evaluation (\`{{date}}\`, \`{{time}}\`, \`{{clipboard}}\`), state machine lifecycle transitions, storage persistence & corruption recovery, caret screen coordinate boundary flipping, text replacer event flags.
  * **System Event Monitoring**: Keyboard keycode dispatch, modifier keys (\`⌘\`, \`⌥\`, \`⌃\`), arrow key navigation, Ctrl shortcuts (\`Ctrl+j/k/n/p/l\`), mouse click filtering.
  * **UI & ViewModels**: Candidate list popout, floating overlay panel geometry, ViewModel CRUD & JSON schema parsing, PreferencesView cancellation & undo restoration, AppKit custom controls.
  * **App Lifecycle**: AppDelegate menus, Preferences window single-instance enforcement, About dialog, double-tap \`⌘Q\` quit guard HUD.

### 🏗️ Codebase Modularization
* Extracted \`AppDelegate.swift\` from \`Main.swift\` for clean application lifecycle separation and testability.
* Single-entry \`@main struct AbbrExMain\` entry point with Whole-Module-Optimization support.

### 📖 Documentation & Distribution
* Overhauled \`README.md\` to remove internal architecture diagrams and highlight current features.
* Added direct links to download latest DMG release package.
* Added step-by-step DMG installation and macOS Accessibility permission setup guide.
* Updated license reference to GPL-2.0.

### 📝 Commits Since $PREV_TAG
$COMMIT_LOG
EOF
)

if [ "$DRY_RUN" = true ]; then
    ./scripts/test.sh
    ./scripts/build_dmg.sh
    echo "=================================================================="
    echo "  RELEASE DRY RUN PREVIEW (No remote changes will be made)"
    echo "=================================================================="
    echo "  • Tag to create : v$VERSION"
    echo "  • DMG Package   : $DMG_PATH"
    echo "  • Target Bundle : $BUNDLE_ID"
    echo "  • Release Notes :"
    echo "------------------------------------------------------------------"
    echo "$RELEASE_NOTES"
    echo "------------------------------------------------------------------"
    echo "  • Command line  : gh release create v$VERSION '$DMG_PATH' --title '$APP_NAME v$VERSION' --notes <notes>"
    echo "=================================================================="
else
    ./scripts/test.sh
    ./scripts/build_dmg.sh
    echo "==> Tagging release v$VERSION..."
    git tag -a "v$VERSION" -m "Release $APP_NAME v$VERSION" || true
    git push origin "v$VERSION" || true
    echo "==> Publishing GitHub Release..."
    if command -v gh >/dev/null 2>&1; then
        gh release create "v$VERSION" "$DMG_PATH" --title "$APP_NAME v$VERSION" --notes "$RELEASE_NOTES"
    else
        echo "Warning: GitHub CLI (gh) not found. Created DMG at $DMG_PATH and tag v$VERSION."
    fi
    echo "✅ Release process completed!"
fi
