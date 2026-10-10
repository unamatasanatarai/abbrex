#!/bin/bash
set -e

APP_NAME="AbbrEx"
BUNDLE_ID="com.citizen.AbbreviationExpander"
BUILD_DIR="build"

DRY_RUN=false
TARGET_VERSION=""

for arg in "$@"; do
    case "$arg" in
    --dry-run)
        DRY_RUN=true
        ;;
    *)
        if [ -z "$TARGET_VERSION" ]; then
            TARGET_VERSION="$arg"
        fi
        ;;
    esac
done

# Read current version from VERSION file
if [ -f "VERSION" ]; then
    CURRENT_VERSION=$(tr -d '[:space:]' <VERSION)
elif [ -f "../VERSION" ]; then
    CURRENT_VERSION=$(tr -d '[:space:]' <../VERSION)
else
    CURRENT_VERSION="1.0.0"
fi
ORIGINAL_VERSION="$CURRENT_VERSION"

# Determine NEW_VERSION: manual override or auto-bump
if [ -n "$TARGET_VERSION" ]; then
    # Strip optional leading 'v'
    TARGET_VERSION="${TARGET_VERSION#v}"
    if ! [[ "$TARGET_VERSION" =~ ^[0-9]+(\.[0-9]+)* ]]; then
        echo "❌ Error: Invalid version format '$TARGET_VERSION'. Expected format like 1.1.0 or v1.1.0"
        exit 1
    fi
    NEW_VERSION="$TARGET_VERSION"

    # Fail-fast if requested tag already exists
    if git rev-parse "v$NEW_VERSION" >/dev/null 2>&1; then
        echo "❌ Error: Git tag 'v$NEW_VERSION' already exists locally!"
        echo "Please specify a higher version number."
        exit 1
    fi
    if git ls-remote --tags origin "refs/tags/v$NEW_VERSION" 2>/dev/null | grep -q "refs/tags/v$NEW_VERSION$"; then
        echo "❌ Error: Git tag 'v$NEW_VERSION' already exists on remote origin!"
        echo "Please specify a higher version number."
        exit 1
    fi
else
    # Auto-bump patch version: X.Y.Z -> X.Y.(Z+1)
    IFS='.' read -r major minor patch <<<"$CURRENT_VERSION"
    if [[ "$patch" =~ ^[0-9]+$ ]]; then
        patch=$((patch + 1))
        NEW_VERSION="${major}.${minor}.${patch}"
    else
        NEW_VERSION="${CURRENT_VERSION}.1"
    fi

    # Advance until we find a tag that does not already exist
    while git rev-parse "v$NEW_VERSION" >/dev/null 2>&1 || git ls-remote --tags origin "refs/tags/v$NEW_VERSION" 2>/dev/null | grep -q "refs/tags/v$NEW_VERSION$"; do
        patch=$((patch + 1))
        NEW_VERSION="${major}.${minor}.${patch}"
    done
fi

VERSION="$NEW_VERSION"
DMG_NAME="AbbrEx-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

if [ "$DRY_RUN" = true ]; then
    echo "==> [DRY RUN] Previewing release AbbrEx v$VERSION (bumped from v$CURRENT_VERSION)..."
    trap 'echo "$ORIGINAL_VERSION" > VERSION' EXIT
    echo "$VERSION" >VERSION
else
    echo "==> Releasing AbbrEx v$VERSION (bumped from v$CURRENT_VERSION)..."
    echo "$VERSION" >VERSION
fi

# Run test suite
echo "==> Executing test suite before release..."
./scripts/test.sh

if [ "$DRY_RUN" = false ]; then
    # Commit version bump to repository if changed
    if git diff --name-only | grep -q "^VERSION$"; then
        echo "==> Committing version bump to v$VERSION..."
        git add VERSION
        git commit -m "chore(release): bump version to v$VERSION"
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
        git push origin "$CURRENT_BRANCH"
    fi
fi

# Build DMG package
echo "==> Building DMG package for v$VERSION..."
./scripts/build_dmg.sh

# Fallback: If GITHUB_TOKEN environment variable is invalid, unset it to use the local keyring
if [ -n "$GITHUB_TOKEN" ]; then
    if ! gh auth status >/dev/null 2>&1; then
        unset GITHUB_TOKEN
    fi
fi

# Detect previous release tag
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v$CURRENT_VERSION")

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
    echo "=================================================================="
    echo "  RELEASE DRY RUN PREVIEW (No remote changes will be made)"
    echo "=================================================================="
    echo "  • Version to release : v$VERSION (bumped from v$CURRENT_VERSION)"
    echo "  • Tag to create      : v$VERSION"
    echo "  • DMG Package        : $DMG_PATH"
    echo "  • Target Bundle      : $BUNDLE_ID"
    echo "  • Release Notes      :"
    echo "------------------------------------------------------------------"
    echo "$RELEASE_NOTES"
    echo "------------------------------------------------------------------"
    echo "  • Command line       : gh release create v$VERSION '$DMG_PATH' --title '$APP_NAME v$VERSION' --notes <notes>"
    echo "=================================================================="
else
    echo "==> Tagging release v$VERSION..."
    git tag -a "v$VERSION" -m "Release $APP_NAME v$VERSION"
    git push origin "v$VERSION"
    echo "==> Publishing GitHub Release..."
    if command -v gh >/dev/null 2>&1; then
        gh release create "v$VERSION" "$DMG_PATH" --title "$APP_NAME v$VERSION" --notes "$RELEASE_NOTES"
    else
        echo "Warning: GitHub CLI (gh) not found. Created DMG at $DMG_PATH and tag v$VERSION."
    fi
    echo "✅ Release v$VERSION published successfully!"
fi
