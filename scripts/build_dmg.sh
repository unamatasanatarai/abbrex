#!/usr/bin/env bash

app_name="AbbrEx"

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

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/abbrex"
mkdir -p "$cache_dir"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to create cache directory ${cache_dir}" >&2
    exit 1
fi

build_dir="build"
app_bundle="${build_dir}/${app_name}.app"
dmg_name="AbbrEx-${version}.dmg"
dmg_path="${build_dir}/${dmg_name}"
tmp_dmg="${build_dir}/tmp_rw.dmg"

if [[ ! -d "$app_bundle" ]]; then
    printf '%s\n' "Application bundle not found. Triggering build..."
    ./scripts/build.sh
    if [[ $? -ne 0 ]]; then
        printf '%s\n' "Error: Application build failed" >&2
        exit 1
    fi
fi

if [[ ! -f "Resources/dmg_background.png" || ! -f "Resources/dmg_background@2x.png" ]]; then
    printf '%s\n' "Generating styled DMG background..."
    python3 scripts/generate_dmg_background.py
    if [[ $? -ne 0 ]]; then
        printf '%s\n' "Error: Failed to generate DMG background" >&2
        exit 1
    fi
fi

hdi_info_file="${cache_dir}/hdiutil_info.tmp"
hdiutil info >"$hdi_info_file" 2>/dev/null
if [[ -f "$hdi_info_file" ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ (/Volumes/${app_name}( [0-9]+)?)[[:space:]]*$ ]]; then
            hdiutil detach "${BASH_REMATCH[1]}" -force >/dev/null 2>&1
        fi
    done <"$hdi_info_file"
    rm -f "$hdi_info_file"
fi

printf '%s\n' "Creating styled DMG installer package..."
rm -rf "${build_dir}/dmg_root" "$tmp_dmg" "$dmg_path"
mkdir -p "${build_dir}/dmg_root/.background"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to create DMG staging directory" >&2
    exit 1
fi

cp "Resources/dmg_background.png" "${build_dir}/dmg_root/.background/background.png"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to copy background image" >&2
    exit 1
fi

if [[ -f "Resources/dmg_background@2x.png" ]]; then
    tiffutil -cathidpicheck "Resources/dmg_background.png" "Resources/dmg_background@2x.png" -out "${build_dir}/dmg_root/.background/background.tiff" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        cp "Resources/dmg_background.png" "${build_dir}/dmg_root/.background/background.tiff"
    fi
else
    cp "Resources/dmg_background.png" "${build_dir}/dmg_root/.background/background.tiff"
fi

cp -R "$app_bundle" "${build_dir}/dmg_root/"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to copy application bundle to DMG staging" >&2
    exit 1
fi

ln -s /Applications "${build_dir}/dmg_root/Applications"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to create /Applications symlink" >&2
    exit 1
fi

hdiutil create -volname "$app_name" -srcfolder "${build_dir}/dmg_root" -format UDRW -ov "$tmp_dmg" >/dev/null
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to create temporary disk image" >&2
    exit 1
fi

attach_file="${cache_dir}/hdiutil_attach.tmp"
hdiutil attach -readwrite -noverify -noautoopen "$tmp_dmg" >"$attach_file" 2>/dev/null
if [[ $? -ne 0 ]]; then
    rm -f "$attach_file"
    printf '%s\n' "Error: Failed to attach temporary disk image" >&2
    exit 1
fi

mount_point=""
while IFS= read -r line; do
    if [[ "$line" =~ (/Volumes/${app_name}( [0-9]+)?)[[:space:]]*$ ]]; then
        mount_point="${BASH_REMATCH[1]}"
        break
    fi
done <"$attach_file"
rm -f "$attach_file"

if [[ -z "$mount_point" || ! -d "$mount_point" ]]; then
    printf '%s\n' "Error: Failed to identify disk image mount point" >&2
    exit 1
fi

osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
    tell disk "$app_name"
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
hdiutil detach "$mount_point" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    hdiutil detach -force "$mount_point" >/dev/null 2>&1
fi

hdiutil convert "$tmp_dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg_path" >/dev/null
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to convert disk image to UDZO format" >&2
    exit 1
fi

rm -rf "${build_dir}/dmg_root" "$tmp_dmg"
printf '%s\n' "DMG created successfully at: ${dmg_path}"
