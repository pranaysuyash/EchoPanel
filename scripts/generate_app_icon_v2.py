#!/usr/bin/env python3
"""
Generate EchoPanel macOS app icon v2 - Premium Glass Design

Features:
- Layered glass panels with realistic depth
- Better gradients and lighting
- Professional macOS superellipse shape
- Enhanced shadows and highlights
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageChops

PROJECT_ROOT = Path(__file__).parent.parent
ASSETS_DIR = PROJECT_ROOT / "assets"

# Refined color palette
DEEP_BLUE = (15, 35, 75)
PRIMARY_BLUE = (31, 111, 235)
BRIGHT_BLUE = (59, 130, 246)
LIGHT_BLUE = (147, 197, 253)
GLASS_WHITE = (255, 255, 255)

ICON_SIZES = [
    (16, "16x16"),
    (32, "16x16@2x"),
    (32, "32x32"),
    (64, "32x32@2x"),
    (128, "128x128"),
    (256, "128x128@2x"),
    (256, "256x256"),
    (512, "256x256@2x"),
    (512, "512x512"),
    (1024, "512x512@2x"),
]


def create_radial_gradient(size: int, center_color: tuple, edge_color: tuple) -> Image.Image:
    """Create a smooth radial gradient."""
    img = Image.new('RGB', (size, size))
    
    # Create gradient using a simpler approach
    center = size // 2
    max_dist = center * 1.5
    
    for y in range(0, size, 2):
        for x in range(0, size, 2):
            dist = math.sqrt((x - center)**2 + (y - center)**2)
            ratio = min(1.0, dist / max_dist)
            
            r = int(center_color[0] * (1 - ratio) + edge_color[0] * ratio)
            g = int(center_color[1] * (1 - ratio) + edge_color[1] * ratio)
            b = int(center_color[2] * (1 - ratio) + edge_color[2] * ratio)
            
            # Draw 2x2 block
            for dy in range(2):
                for dx in range(2):
                    if y + dy < size and x + dx < size:
                        img.putpixel((x + dx, y + dy), (r, g, b))
    
    return img


def create_superellipse_mask(size: int, radius: float = 0.22) -> Image.Image:
    """Create macOS superellipse mask."""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    corner_radius = int(size * radius)
    draw.rounded_rectangle([0, 0, size-1, size-1], radius=corner_radius, fill=255)
    return mask


def create_glass_panel(width: int, height: int, intensity: float = 1.0) -> Image.Image:
    """Create a realistic glass panel with depth."""
    panel = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(panel)
    
    # Main glass body with gradient
    corner = width // 2
    
    # Create vertical gradient for glass
    for y in range(height):
        # Top is brighter (highlight), bottom is slightly darker
        if y < height * 0.3:
            alpha = int(200 * intensity)
        elif y < height * 0.7:
            alpha = int(180 * intensity)
        else:
            alpha = int(160 * intensity)
        
        draw.line([(0, y), (width, y)], fill=(*GLASS_WHITE, alpha))
    
    # Round the corners
    mask = Image.new('L', (width, height), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, width-1, height-1], radius=corner, fill=255)
    panel.putalpha(mask)
    
    # Add top highlight
    highlight = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_height = max(2, height // 5)
    highlight_draw.rounded_rectangle(
        [1, 1, width-2, highlight_height],
        radius=corner,
        fill=(*GLASS_WHITE, int(120 * intensity))
    )
    panel = Image.alpha_composite(panel, highlight)
    
    # Add subtle inner shadow at bottom
    shadow = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_height = max(3, height // 4)
    shadow_draw.rounded_rectangle(
        [0, height - shadow_height, width, height],
        radius=corner,
        fill=(0, 0, 0, int(30 * intensity))
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=3))
    panel = Image.alpha_composite(panel, shadow)
    
    return panel


def create_shadow_layer(size: int, offset: int = 20, blur: int = 40) -> Image.Image:
    """Create drop shadow for the icon."""
    shadow = Image.new('RGBA', (size + offset*2, size + offset*2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    
    corner_radius = int(size * 0.22)
    draw.rounded_rectangle(
        [offset, offset, size + offset, size + offset],
        radius=corner_radius,
        fill=(0, 0, 0, 100)
    )
    
    return shadow.filter(ImageFilter.GaussianBlur(radius=blur))


def create_waveform_bars(size: int) -> Image.Image:
    """Create three glass waveform bars."""
    bars_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Bar configurations: (height_ratio, x_offset, opacity)
    bars_config = [
        (0.35, -0.22, 0.85),  # Left
        (0.60, 0.0, 1.0),     # Center (tallest, brightest)
        (0.42, 0.22, 0.85),   # Right
    ]
    
    bar_width = size // 7
    gap = size // 14
    
    for height_ratio, x_offset, opacity in bars_config:
        bar_height = int(size * height_ratio * 0.5)
        
        # Create glass panel
        bar = create_glass_panel(bar_width, bar_height, intensity=opacity)
        
        # Calculate position
        center_x = size // 2 + int(size * x_offset) - bar_width // 2
        center_y = size // 2 - bar_height // 2
        
        # Create shadow for this bar
        bar_shadow = Image.new('RGBA', (bar_width + 10, bar_height + 10), (0, 0, 0, 0))
        bar_shadow_draw = ImageDraw.Draw(bar_shadow)
        bar_shadow_draw.rounded_rectangle(
            [5, 5, bar_width + 5, bar_height + 5],
            radius=bar_width // 2,
            fill=(0, 0, 0, 60)
        )
        bar_shadow = bar_shadow.filter(ImageFilter.GaussianBlur(radius=8))
        
        # Paste shadow then bar
        bars_img.paste(bar_shadow, (center_x - 2, center_y + 4), bar_shadow)
        bars_img.paste(bar, (center_x, center_y), bar)
    
    return bars_img


def create_glow_orb(size: int) -> Image.Image:
    """Create subtle background glow."""
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Create radial gradient glow
    center = size // 2
    max_radius = size // 3
    
    draw = ImageDraw.Draw(glow)
    for r in range(max_radius, 0, -2):
        alpha = int(30 * (r / max_radius))
        draw.ellipse(
            [center - r, center - r, center + r, center + r],
            outline=(*LIGHT_BLUE, alpha),
            width=2
        )
    
    return glow.filter(ImageFilter.GaussianBlur(radius=30))


def create_floating_dots(size: int) -> Image.Image:
    """Create subtle floating dots for depth."""
    dots = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(dots)
    
    dot_configs = [
        {"pos": (0.18, 0.22), "radius": 0.035, "alpha": 0.25},
        {"pos": (0.82, 0.28), "radius": 0.025, "alpha": 0.20},
        {"pos": (0.78, 0.72), "radius": 0.04, "alpha": 0.18},
        {"pos": (0.22, 0.75), "radius": 0.03, "alpha": 0.22},
    ]
    
    for config in dot_configs:
        x = int(size * config["pos"][0])
        y = int(size * config["pos"][1])
        r = int(size * config["radius"])
        alpha = int(255 * config["alpha"])
        
        draw.ellipse([x-r, y-r, x+r, y+r], fill=(*GLASS_WHITE, alpha))
    
    return dots.filter(ImageFilter.GaussianBlur(radius=6))


def create_icon_1024() -> Image.Image:
    """Create the main 1024x1024 icon with all effects."""
    size = 1024
    
    print("  🎨 Creating background gradient...")
    bg = create_radial_gradient(size, PRIMARY_BLUE, DEEP_BLUE)
    base = bg.convert('RGBA')
    
    print("  ✨ Adding ambient glow...")
    glow = create_glow_orb(size)
    base = Image.alpha_composite(base, glow)
    
    print("  🎵 Creating waveform bars...")
    waveform = create_waveform_bars(size)
    
    print("  🔵 Adding floating elements...")
    dots = create_floating_dots(size)
    
    print("  🔲 Applying mask and shadow...")
    mask = create_superellipse_mask(size)
    
    # Create shadow
    shadow = create_shadow_layer(size)
    
    # Composite everything
    print("  🖼️  Compositing layers...")
    
    # Start with shadow (smaller canvas)
    final_size = size + 80
    final = Image.new('RGBA', (final_size, final_size), (0, 0, 0, 0))
    
    # Paste shadow
    shadow_offset = 20
    final.paste(shadow, (0, 0))
    
    # Prepare icon content
    icon_content = base
    icon_content = Image.alpha_composite(icon_content, waveform)
    icon_content = Image.alpha_composite(icon_content, dots)
    
    # Apply mask
    icon_content.putalpha(mask)
    
    # Paste icon onto shadow
    final.paste(icon_content, (shadow_offset, shadow_offset))
    
    # Enhance
    enhancer = ImageEnhance.Sharpness(final)
    final = enhancer.enhance(1.1)
    
    # Convert to RGBA to ensure proper format
    final = final.convert('RGBA')
    
    return final


def create_iconset(source: Image.Image) -> Path:
    """Create all icon sizes."""
    print("📐 Generating icon sizes...")
    
    iconset_dir = ASSETS_DIR / "AppIcon-v2.iconset"
    iconset_dir.mkdir(parents=True, exist_ok=True)
    
    for size, name in ICON_SIZES:
        icon = source.copy()
        # Crop to square centered
        w, h = icon.size
        if w != h:
            min_dim = min(w, h)
            left = (w - min_dim) // 2
            top = (h - min_dim) // 2
            icon = icon.crop((left, top, left + min_dim, top + min_dim))
        
        icon = icon.resize((size, size), Image.Resampling.LANCZOS)
        filename = iconset_dir / f"icon_{name}.png"
        icon.save(filename, "PNG")
        print(f"  ✅ {name} ({size}x{size})")
    
    return iconset_dir


def convert_to_icns(iconset_dir: Path) -> Path:
    """Convert iconset to .icns."""
    print("🔧 Converting to .icns...")
    
    icns_path = ASSETS_DIR / "AppIcon-v2.icns"
    
    try:
        import subprocess
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir)],
            capture_output=True,
            check=True
        )
        
        temp_icns = iconset_dir.parent / "AppIcon-v2.icns"
        if temp_icns.exists():
            temp_icns.rename(icns_path)
            print(f"  ✅ Created: {icns_path}")
            return icns_path
    except Exception as e:
        print(f"  ⚠️  Error: {e}")
    
    return None


def main():
    print("=" * 60)
    print("EchoPanel App Icon Generator v2")
    print("Premium Glass Design")
    print("=" * 60)
    
    ASSETS_DIR.mkdir(exist_ok=True)
    
    print("\n🎨 Creating master icon (1024x1024)...")
    master = create_icon_1024()
    
    # Crop to exact 1024x1024 if needed
    if master.size != (1024, 1024):
        w, h = master.size
        left = (w - 1024) // 2
        top = (h - 1024) // 2
        master = master.crop((left, top, left + 1024, top + 1024))
    
    # Save master
    master_path = ASSETS_DIR / "app_icon_v2_1024.png"
    master.save(master_path, "PNG")
    print(f"\n💾 Saved: {master_path}")
    
    # Create iconset and icns
    iconset_dir = create_iconset(master)
    icns_path = convert_to_icns(iconset_dir)
    
    if icns_path:
        # Copy to main location
        import shutil
        shutil.copy(icns_path, ASSETS_DIR / "AppIcon.icns")
        print("\n📌 Updated main AppIcon.icns")
    
    print("\n" + "=" * 60)
    print("✨ Complete!")
    print("=" * 60)
    print(f"\n👁️  Preview: open {master_path}")


if __name__ == "__main__":
    main()
