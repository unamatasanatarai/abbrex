#!/bin/bash
set -e

APP_NAME="AbbrEx"
VERSION="1.0.0"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="AbbrEx-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "==> Application bundle not found. Triggering build..."
    ./scripts/build.sh
fi

echo "==> Creating DMG installer package..."
rm -rf "$BUILD_DIR/dmg_root" "$DMG_PATH"
mkdir -p "$BUILD_DIR/dmg_root"
cp -R "$APP_BUNDLE" "$BUILD_DIR/dmg_root/"
ln -s /Applications "$BUILD_DIR/dmg_root/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD_DIR/dmg_root" -ov -format UDZO "$DMG_PATH"
rm -rf "$BUILD_DIR/dmg_root"

echo "✅ DMG created successfully at: $DMG_PATH"
