#!/usr/bin/env python3
"""
Generates high-resolution macOS application icons and status bar template icons
for AbbrEx based on the geometric chevron concept.
"""

import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

# Normalized vector coordinates for the interlocking opposing chevron glyph
# Center is (0, 0), width is 1.0, height is 0.872
norm_top = [
    (-0.12, -0.436),
    (-0.50, -0.056),
    (-0.50,  0.168),
    (-0.12, -0.212),
    ( 0.12,  0.028),
    ( 0.12, -0.196)
]
norm_bot = [(-x, -y) for x, y in norm_top]

def draw_glyph(draw, cx, cy, width, color):
    poly_top = [(cx + x * width, cy + y * width) for x, y in norm_top]
    poly_bot = [(cx + x * width, cy + y * width) for x, y in norm_bot]
    draw.polygon(poly_top, fill=color)
    draw.polygon(poly_bot, fill=color)

def generate_icons():
    resources_dir = "Resources"
    os.makedirs(resources_dir, exist_ok=True)

    # 1. Generate macOS AppIcon (1024x1024 with 4x supersampling = 4096x4096)
    ss = 4
    canvas_size = 1024 * ss
    master = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    tile_size = int(824 * ss)
    tile_margin = (canvas_size - tile_size) // 2
    tile_radius = int(185 * ss)

    # Ambient drop shadow beneath squircle tile
    shadow_offset_y = int(24 * ss)
    shadow_blur = int(28 * ss)

    shadow_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_box = [
        tile_margin,
        tile_margin + shadow_offset_y,
        tile_margin + tile_size,
        tile_margin + tile_size + shadow_offset_y
    ]
    shadow_draw.rounded_rectangle(shadow_box, radius=tile_radius, fill=(0, 0, 0, 75))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(shadow_blur))
    master = Image.alpha_composite(master, shadow_layer)

    # Tile surface with subtle vertical gradient
    tile_img = Image.new("RGBA", (tile_size, tile_size))
    for y in range(tile_size):
        ratio = y / tile_size
        r = int(255 - ratio * 12)
        g = int(255 - ratio * 11)
        b = int(255 - ratio * 9)
        for x in range(tile_size):
            tile_img.putpixel((x, y), (r, g, b, 255))

    mask = Image.new("L", (canvas_size, canvas_size), 0)
    mask_draw = ImageDraw.Draw(mask)
    tile_box = [tile_margin, tile_margin, tile_margin + tile_size, tile_margin + tile_size]
    mask_draw.rounded_rectangle(tile_box, radius=tile_radius, fill=255)

    composite = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    composite.paste(tile_img, (tile_margin, tile_margin))
    master.paste(composite, (0, 0), mask)

    # Inner rim border
    border_draw = ImageDraw.Draw(master)
    border_draw.rounded_rectangle(
        tile_box,
        radius=tile_radius,
        outline=(226, 232, 240, 255),
        width=max(1, int(1.5 * ss))
    )

    # Chevron glyph
    glyph_w = int(480 * ss)
    glyph_draw = ImageDraw.Draw(master)
    draw_glyph(glyph_draw, canvas_size // 2, canvas_size // 2, glyph_w, (17, 24, 39, 255))

    app_icon_1024 = master.resize((1024, 1024), Image.Resampling.LANCZOS)
    app_icon_1024.save(os.path.join(resources_dir, "AppIcon.png"))
    print("✅ Created Resources/AppIcon.png")

    # 2. Generate multi-resolution .icns bundle
    iconset_dir = "/tmp/AbbrEx_AppIcon.iconset"
    os.makedirs(iconset_dir, exist_ok=True)

    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for size, filename in sizes:
        resized = app_icon_1024.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename))

    icns_path = os.path.join(resources_dir, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
    print("✅ Created Resources/AppIcon.icns")

    # 3. Generate Status Bar Template Icons (18x18 @1x and 36x36 @2x)
    sb_supersample = 288
    sb_master = Image.new("RGBA", (sb_supersample, sb_supersample), (0, 0, 0, 0))
    sb_draw = ImageDraw.Draw(sb_master)
    # 22px glyph width in 36px viewport -> 22 * 8 = 176px at 288px
    sb_glyph_w = 176
    draw_glyph(sb_draw, sb_supersample // 2, sb_supersample // 2, sb_glyph_w, (0, 0, 0, 255))

    sb_36 = sb_master.resize((36, 36), Image.Resampling.LANCZOS)
    sb_18 = sb_master.resize((18, 18), Image.Resampling.LANCZOS)

    sb_36.save(os.path.join(resources_dir, "status-bar-icon@2x.png"))
    sb_36.save(os.path.join(resources_dir, "StatusBarIcon@2x.png"))
    sb_18.save(os.path.join(resources_dir, "status-bar-icon.png"))
    sb_18.save(os.path.join(resources_dir, "StatusBarIcon.png"))
    print("✅ Created Status Bar template icons (18x18 & 36x36)")

if __name__ == "__main__":
    generate_icons()
