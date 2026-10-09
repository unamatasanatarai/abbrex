#!/bin/bash
set -e

echo "=== Building AbbrEx Native macOS Application ==="

SDK_PATH=$(xcrun --show-sdk-path)
APP_NAME="AbbrEx"
BUNDLE_ID="com.citizen.AbbreviationExpander"
VERSION="1.0.0"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

if [ -d "Resources" ]; then
    cp -R Resources/* "$RESOURCES_DIR/"
fi

echo "1. Compiling Swift source files..."
swiftc -sdk "$SDK_PATH" \
    -O \
    Sources/AbbreviationExpander/Core/*.swift \
    Sources/AbbreviationExpander/UI/*.swift \
    Sources/AbbreviationExpander/Services/*.swift \
    Sources/AbbreviationExpander/Main.swift \
    -o "$MACOS_DIR/AbbrEx"

echo "2. Generating Info.plist..."
cat <<EOF >"$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AbbrEx</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

echo "3. Signing application binary..."
codesign --force --deep --sign - "$APP_DIR"

echo "✅ Build complete: $APP_DIR"
