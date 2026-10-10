#!/usr/bin/env python3
"""
Generates high-resolution sleek macOS application icons and crisp status bar template icons
for AbbrEx based directly on the vector paths defined in Resources/AppIcon.svg.
"""

import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

# Normalized vector coordinates derived directly from Resources/AppIcon.svg
# ViewBox: 11 94 668 476
# Path 1: M339 94 471 226V347L339 215 131 423H11Z
# Path 2: M679 241V362L471 570 339 438V317L471 449Z
cx_ref = 345.0
cy_ref = 332.0
w_ref = 668.0

norm_p1 = [
    ((339 - cx_ref) / w_ref, (94 - cy_ref) / w_ref),
    ((471 - cx_ref) / w_ref, (226 - cy_ref) / w_ref),
    ((471 - cx_ref) / w_ref, (347 - cy_ref) / w_ref),
    ((339 - cx_ref) / w_ref, (215 - cy_ref) / w_ref),
    ((131 - cx_ref) / w_ref, (423 - cy_ref) / w_ref),
    ((11 - cx_ref) / w_ref,  (423 - cy_ref) / w_ref),
]

norm_p2 = [
    ((679 - cx_ref) / w_ref, (241 - cy_ref) / w_ref),
    ((679 - cx_ref) / w_ref, (362 - cy_ref) / w_ref),
    ((471 - cx_ref) / w_ref, (570 - cy_ref) / w_ref),
    ((339 - cx_ref) / w_ref, (438 - cy_ref) / w_ref),
    ((339 - cx_ref) / w_ref, (317 - cy_ref) / w_ref),
    ((471 - cx_ref) / w_ref, (449 - cy_ref) / w_ref),
]

def draw_glyph(draw, cx, cy, width, color):
    poly1 = [(cx + x * width, cy + y * width) for x, y in norm_p1]
    poly2 = [(cx + x * width, cy + y * width) for x, y in norm_p2]
    draw.polygon(poly1, fill=color)
    draw.polygon(poly2, fill=color)

def generate_icons():
    resources_dir = "Resources"
    os.makedirs(resources_dir, exist_ok=True)

    # 1. Generate sleek macOS AppIcon (1024x1024 master, supersampled 4x = 4096x4096)
    ss = 4
    canvas_size = 1024 * ss
    master = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    tile_size = int(824 * ss)
    tile_margin = (canvas_size - tile_size) // 2
    tile_radius = int(185 * ss)

    # Multi-stage ambient and contact shadows
    amb_shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    amb_draw = ImageDraw.Draw(amb_shadow)
    amb_offset_y = int(32 * ss)
    amb_box = [
        tile_margin,
        tile_margin + amb_offset_y,
        tile_margin + tile_size,
        tile_margin + tile_size + amb_offset_y
    ]
    amb_draw.rounded_rectangle(amb_box, radius=tile_radius, fill=(0, 0, 0, 48))
    amb_shadow = amb_shadow.filter(ImageFilter.GaussianBlur(int(36 * ss)))
    master = Image.alpha_composite(master, amb_shadow)

    dir_shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    dir_draw = ImageDraw.Draw(dir_shadow)
    dir_offset_y = int(16 * ss)
    dir_box = [
        tile_margin,
        tile_margin + dir_offset_y,
        tile_margin + tile_size,
        tile_margin + tile_size + dir_offset_y
    ]
    dir_draw.rounded_rectangle(dir_box, radius=tile_radius, fill=(0, 0, 0, 56))
    dir_shadow = dir_shadow.filter(ImageFilter.GaussianBlur(int(16 * ss)))
    master = Image.alpha_composite(master, dir_shadow)

    # Sleek frosted platinum ceramic surface
    tile_img = Image.new("RGBA", (tile_size, tile_size))
    for y in range(tile_size):
        ratio = y / tile_size
        r = int(255 - ratio * 14)
        g = int(255 - ratio * 12)
        b = int(255 - ratio * 10)
        for x in range(tile_size):
            tile_img.putpixel((x, y), (r, g, b, 255))

    mask = Image.new("L", (canvas_size, canvas_size), 0)
    mask_draw = ImageDraw.Draw(mask)
    tile_box = [tile_margin, tile_margin, tile_margin + tile_size, tile_margin + tile_size]
    mask_draw.rounded_rectangle(tile_box, radius=tile_radius, fill=255)

    composite = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    composite.paste(tile_img, (tile_margin, tile_margin))
    master.paste(composite, (0, 0), mask)

    # Delicate inner metallic border
    border_draw = ImageDraw.Draw(master)
    border_draw.rounded_rectangle(
        tile_box,
        radius=tile_radius,
        outline=(226, 232, 240, 240),
        width=max(1, int(1.5 * ss))
    )

    # Sleek obsidian glyph with subtle depth
    glyph_w = int(512 * ss)
    cx = canvas_size // 2
    cy = canvas_size // 2

    # Glyph micro-shadow for tactile physical feel
    glyph_shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    gs_draw = ImageDraw.Draw(glyph_shadow)
    gs_offset_y = int(5 * ss)
    draw_glyph(gs_draw, cx, cy + gs_offset_y, glyph_w, (0, 0, 0, 48))
    glyph_shadow = glyph_shadow.filter(ImageFilter.GaussianBlur(int(6 * ss)))
    master = Image.alpha_composite(master, glyph_shadow)

    # Solid glyph fill
    glyph_draw = ImageDraw.Draw(master)
    draw_glyph(glyph_draw, cx, cy, glyph_w, (15, 23, 42, 255))

    app_icon_1024 = master.resize((1024, 1024), Image.Resampling.LANCZOS)
    app_icon_1024.save(os.path.join(resources_dir, "AppIcon.png"))
    print("✅ Created Resources/AppIcon.png")

    # 2. Multi-resolution Apple .icns bundle
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

    # 3. Crisp Status Bar Template Icons (18x18 @1x and 36x36 @2x)
    def render_crisp_statusbar(size, glyph_w):
        supersample = 16
        ss_size = size * supersample
        hires = Image.new("RGBA", (ss_size, ss_size), (0, 0, 0, 0))
        hdraw = ImageDraw.Draw(hires)
        
        draw_glyph(hdraw, ss_size / 2.0, ss_size / 2.0, glyph_w * supersample, (0, 0, 0, 255))
        
        downsampled = hires.resize((size, size), Image.Resampling.LANCZOS)
        # Punchy alpha curve for crisp rendering on macOS menu bar
        r, g, b, a = downsampled.split()
        a = a.point(lambda p: min(255, int(p * 1.12)) if p > 20 else 0)
        return Image.merge("RGBA", (r, g, b, a))

    sb_18 = render_crisp_statusbar(18, 15.5)
    sb_36 = render_crisp_statusbar(36, 31.0)

    sb_18.save(os.path.join(resources_dir, "status-bar-icon.png"))
    sb_18.save(os.path.join(resources_dir, "StatusBarIcon.png"))
    sb_36.save(os.path.join(resources_dir, "status-bar-icon@2x.png"))
    sb_36.save(os.path.join(resources_dir, "StatusBarIcon@2x.png"))
    print("✅ Created crisp Status Bar template icons (18x18 & 36x36)")

if __name__ == "__main__":
    generate_icons()
