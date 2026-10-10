#!/usr/bin/env bash

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/abbrex"
mkdir -p "$cache_dir"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to create cache directory ${cache_dir}" >&2
    exit 1
fi

sdk_file="${cache_dir}/sdk_path.tmp"
xcrun --show-sdk-path >"$sdk_file" 2>/dev/null
if [[ $? -ne 0 || ! -s "$sdk_file" ]]; then
    rm -f "$sdk_file"
    printf '%s\n' "Error: Failed to obtain SDK path from xcrun" >&2
    exit 1
fi

IFS= read -r sdk_path <"$sdk_file"
rm -f "$sdk_file"

app_name="AbbrEx"
bundle_id="com.citizen.AbbreviationExpander"

version=""
if [[ -f "VERSION" ]]; then
    IFS= read -r version <"VERSION"
elif [[ -f "../VERSION" ]]; then
    IFS= read -r version <"../VERSION"
fi
version="${version//[[:space:]]/}"
if [[ -z "$version" ]]; then
    version="1.0.2"
fi

build_dir="build"
app_dir="${build_dir}/${app_name}.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

mkdir -p "$macos_dir" "$resources_dir"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to create application bundle directories" >&2
    exit 1
fi

if [[ -d "Resources" ]]; then
    cp -R Resources/. "${resources_dir}/"
    if [[ $? -ne 0 ]]; then
        printf '%s\n' "Error: Failed to copy Resources" >&2
        exit 1
    fi
fi

if [[ -f "VERSION" ]]; then
    cp "VERSION" "${resources_dir}/VERSION"
    if [[ $? -ne 0 ]]; then
        printf '%s\n' "Error: Failed to copy VERSION file" >&2
        exit 1
    fi
fi

printf '%s\n' "Compiling Swift source files with Whole-Module-Optimization..."
swiftc -sdk "$sdk_path" \
    -O \
    -whole-module-optimization \
    -Xlinker -dead_strip \
    Sources/AbbreviationExpander/Core/*.swift \
    Sources/AbbreviationExpander/UI/*.swift \
    Sources/AbbreviationExpander/Services/*.swift \
    Sources/AbbreviationExpander/*.swift \
    -o "${macos_dir}/AbbrEx"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Swift compilation failed" >&2
    exit 1
fi

printf '%s\n' "Generating Info.plist..."
printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0">' \
    '<dict>' \
    '    <key>CFBundleExecutable</key>' \
    "    <string>${app_name}</string>" \
    '    <key>CFBundleIdentifier</key>' \
    "    <string>${bundle_id}</string>" \
    '    <key>CFBundleName</key>' \
    "    <string>${app_name}</string>" \
    '    <key>CFBundlePackageType</key>' \
    '    <string>APPL</string>' \
    '    <key>CFBundleShortVersionString</key>' \
    "    <string>${version}</string>" \
    '    <key>CFBundleVersion</key>' \
    '    <string>1</string>' \
    '    <key>CFBundleIconFile</key>' \
    '    <string>AppIcon.icns</string>' \
    '    <key>CFBundleIconName</key>' \
    '    <string>AppIcon</string>' \
    '    <key>LSMinimumSystemVersion</key>' \
    '    <string>12.0</string>' \
    '    <key>LSUIElement</key>' \
    '    <true/>' \
    '    <key>NSHighResolutionCapable</key>' \
    '    <true/>' \
    '    <key>NSHumanReadableCopyright</key>' \
    '    <string>Copyright © 2026. All rights reserved.</string>' \
    '</dict>' \
    '</plist>' >"${contents_dir}/Info.plist"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to write Info.plist" >&2
    exit 1
fi

printf '%s\n' "Signing application binary with stable designated requirement..."
codesign --force --deep --sign - --requirements "=designated => identifier \"${bundle_id}\"" "$app_dir"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Code signing failed" >&2
    exit 1
fi

printf '%s\n' "Refreshing macOS LaunchServices and Icon cache..."
touch "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$app_dir" >/dev/null 2>&1
qlmanage -r cache >/dev/null 2>&1

printf '%s\n' "Build complete: ${app_dir}"
