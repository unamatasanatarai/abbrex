#!/bin/bash
set -e

APP_NAME="AbbrEx"
if [ -f "VERSION" ]; then
    VERSION=$(tr -d '[:space:]' <VERSION)
elif [ -f "../VERSION" ]; then
    VERSION=$(tr -d '[:space:]' <../VERSION)
else
    VERSION="1.0.2"
fi
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="AbbrEx-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
TMP_DMG="$BUILD_DIR/tmp_rw.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "==> Application bundle not found. Triggering build..."
    ./scripts/build.sh
fi

# Ensure background image exists
if [ ! -f "Resources/dmg_background.png" ] || [ ! -f "Resources/dmg_background@2x.png" ]; then
    echo "==> Generating styled DMG background..."
    python3 scripts/generate_dmg_background.py
fi

echo "==> Creating styled DMG installer package..."
rm -rf "$BUILD_DIR/dmg_root" "$TMP_DMG" "$DMG_PATH"
mkdir -p "$BUILD_DIR/dmg_root/.background"

# Copy background images (PNG & multi-resolution TIFF)
cp "Resources/dmg_background.png" "$BUILD_DIR/dmg_root/.background/background.png"
if [ -f "Resources/dmg_background@2x.png" ]; then
    tiffutil -cathidpicheck "Resources/dmg_background.png" "Resources/dmg_background@2x.png" -out "$BUILD_DIR/dmg_root/.background/background.tiff" 2>/dev/null || cp "Resources/dmg_background.png" "$BUILD_DIR/dmg_root/.background/background.tiff"
else
    cp "Resources/dmg_background.png" "$BUILD_DIR/dmg_root/.background/background.tiff"
fi

# Copy App bundle and Applications symlink
cp -R "$APP_BUNDLE" "$BUILD_DIR/dmg_root/"
ln -s /Applications "$BUILD_DIR/dmg_root/Applications"

# Create temporary read/write disk image
hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD_DIR/dmg_root" -format UDRW -ov "$TMP_DMG" >/dev/null

# Attach temporary disk image
ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")
MOUNT_POINT=$(echo "$ATTACH_OUTPUT" | grep "/Volumes/$APP_NAME" | awk '{print $NF}')

if [ -n "$MOUNT_POINT" ]; then
    # Configure Finder window styling, bounds, icon sizes and layout
    osascript <<APPLESCRIPT 2>/dev/null || true
    tell application "Finder"
        tell disk "$APP_NAME"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {400, 100, 1060, 520}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 128
            set background picture of theViewOptions to file ".background:background.tiff"
            set position of item "AbbrEx.app" of container window to {160, 205}
            set position of item "Applications" of container window to {500, 205}
            update without registering applications
            delay 1
            close
        end tell
    end tell
APPLESCRIPT

    sync
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || hdiutil detach -force "$MOUNT_POINT" >/dev/null 2>&1 || true
fi

# Convert to final compressed UDZO disk image
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" >/dev/null
rm -rf "$BUILD_DIR/dmg_root" "$TMP_DMG"

echo "✅ DMG created successfully at: $DMG_PATH"
