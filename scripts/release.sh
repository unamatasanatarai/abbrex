#!/bin/bash
set -e

APP_NAME="AbbrEx"
BUNDLE_ID="com.citizen.AbbreviationExpander"
if [ -f "VERSION" ]; then
    VERSION=$(tr -d '[:space:]' <VERSION)
elif [ -f "../VERSION" ]; then
    VERSION=$(tr -d '[:space:]' <../VERSION)
else
    VERSION="1.0.2"
fi
BUILD_DIR="build"
DMG_NAME="AbbrEx-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
fi

# Fail-fast if tag already exists (before running tests or building DMG)
if [ "$DRY_RUN" = false ]; then
    if git rev-parse "v$VERSION" >/dev/null 2>&1; then
        echo "❌ Error: Git tag 'v$VERSION' already exists locally!"
        echo "Please bump the version in the VERSION file before running 'make release'."
        exit 1
    fi
    if git ls-remote --tags origin "refs/tags/v$VERSION" 2>/dev/null | grep -q "v$VERSION"; then
        echo "❌ Error: Git tag 'v$VERSION' already exists on remote origin!"
        echo "Please bump the version in the VERSION file before running 'make release'."
        exit 1
    fi
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

### 🚀 Highlights & Improvements
* **Razor-Sharp Status Bar Icon**: Dynamically rendered via CoreGraphics vector paths, eliminating Retina display scaling blur.
* **Enhanced Replacement & Security**: Thread-safe replacement flag, background keystroke simulation, and automatic gating for macOS secure input fields (passwords, PINs).
* **Snippet Organization**: Automatic alphabetical sorting by prefix throughout library storage, view models, and preferences search.
* **Updated Defaults & Bundling**: Streamlined default snippets bundled in \`Resources/default-snippets.json\`.

### 📝 Commits Since $PREV_TAG
$COMMIT_LOG

---
*Built with native Swift for macOS 12.0+.*
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
