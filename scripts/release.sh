#!/bin/bash
set -e

APP_NAME="AbbrEx"
BUNDLE_ID="com.citizen.AbbreviationExpander"
VERSION="1.0.0"
BUILD_DIR="build"
DMG_NAME="AbbrEx-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
fi

if [ "$DRY_RUN" = true ]; then
    ./scripts/test.sh
    ./scripts/build_dmg.sh
    echo "=================================================================="
    echo "  RELEASE DRY RUN PREVIEW (No remote changes will be made)"
    echo "=================================================================="
    echo "  • Tag to create : v$VERSION"
    echo "  • DMG Package   : $DMG_PATH"
    echo "  • Target Bundle : $BUNDLE_ID"
    echo "  • Command line  : gh release create v$VERSION '$DMG_PATH' --title '$APP_NAME v$VERSION' --notes 'Release v$VERSION'"
    echo "=================================================================="
else
    ./scripts/test.sh
    ./scripts/build_dmg.sh
    echo "==> Tagging release v$VERSION..."
    git tag -a "v$VERSION" -m "Release $APP_NAME v$VERSION" || true
    git push origin "v$VERSION" || true
    echo "==> Publishing GitHub Release..."
    if command -v gh >/dev/null 2>&1; then
        gh release create "v$VERSION" "$DMG_PATH" --title "$APP_NAME v$VERSION" --notes "Official Release v$VERSION"
    else
        echo "Warning: GitHub CLI (gh) not found. Created DMG at $DMG_PATH and tag v$VERSION."
    fi
    echo "✅ Release process completed!"
fi
