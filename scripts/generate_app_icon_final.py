#!/usr/bin/env python3
"""
Generate EchoPanel macOS app icon - Final Premium Version

Features:
- Deep layered glass morphism
- Realistic 3D depth
- Premium macOS styling
- Professional lighting and shadows
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

PROJECT_ROOT = Path(__file__).parent.parent
ASSETS_DIR = PROJECT_ROOT / "assets"

# Premium color palette
DEEP_NAVY = (10, 25, 55)
ROYAL_BLUE = (25, 85, 180)
ELECTRIC_BLUE = (45, 125, 245)
SKY_BLUE = (120, 180, 255)
PURE_WHITE = (255, 255, 255)
SOFT_WHITE = (240, 248, 255)

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


def create_smooth_gradient(size: int) -> Image.Image:
    """Create a smooth multi-stop gradient background."""
    img = Image.new('RGB', (size, size))
    
    # Create radial gradient from center
    center = size // 2
    max_dist = center * math.sqrt(2)
    
    for y in range(size):
        for x in range(size):
            dist = math.sqrt((x - center)**2 + (y - center)**2)
            ratio = dist / max_dist
            
            # Multi-stop gradient
            if ratio < 0.3:
                # Center: bright electric blue
                r, g, b = ELECTRIC_BLUE
            elif ratio < 0.6:
                # Mid: royal blue
                blend = (ratio - 0.3) / 0.3
                r = int(ELECTRIC_BLUE[0] * (1-blend) + ROYAL_BLUE[0] * blend)
                g = int(ELECTRIC_BLUE[1] * (1-blend) + ROYAL_BLUE[1] * blend)
                b = int(ELECTRIC_BLUE[2] * (1-blend) + ROYAL_BLUE[2] * blend)
            else:
                # Edge: deep navy
                blend = min(1.0, (ratio - 0.6) / 0.4)
                r = int(ROYAL_BLUE[0] * (1-blend) + DEEP_NAVY[0] * blend)
                g = int(ROYAL_BLUE[1] * (1-blend) + DEEP_NAVY[1] * blend)
                b = int(ROYAL_BLUE[2] * (1-blend) + DEEP_NAVY[2] * blend)
            
            img.putpixel((x, y), (r, g, b))
    
    return img


def create_rounded_rect_mask(width: int, height: int, radius: int) -> Image.Image:
    """Create a rounded rectangle mask."""
    mask = Image.new('L', (width, height), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, width-1, height-1], radius=radius, fill=255)
    return mask


def create_glass_bar_v3(width: int, height: int, intensity: float = 1.0) -> Image.Image:
    """Create a premium glass bar with realistic effects."""
    # Create base image
    bar = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    
    radius = width // 2
    
    # Create gradient for glass body
    for y in range(height):
        # Calculate opacity based on position
        # Top: bright, middle: solid, bottom: slightly darker
        if y < height * 0.25:
            alpha = int(240 * intensity)
            color = PURE_WHITE
        elif y < height * 0.75:
            alpha = int(220 * intensity)
            color = SOFT_WHITE
        else:
            alpha = int(200 * intensity)
            color = (230, 240, 255)
        
        ImageDraw.Draw(bar).line(
            [(0, y), (width, y)],
            fill=(*color, alpha)
        )
    
    # Apply rounded mask
    mask = create_rounded_rect_mask(width, height, radius)
    bar.putalpha(mask)
    
    # Add top highlight (strong)
    highlight_height = max(2, int(height * 0.15))
    highlight = Image.new('RGBA', (width, highlight_height), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.rounded_rectangle(
        [0, 0, width-1, highlight_height-1],
        radius=radius,
        fill=(*PURE_WHITE, int(180 * intensity))
    )
    bar.paste(highlight, (0, 0), highlight)
    
    # Add subtle bottom reflection
    reflection_height = max(3, int(height * 0.1))
    reflection = Image.new('RGBA', (width, reflection_height), (0, 0, 0, 0))
    reflection_draw = ImageDraw.Draw(reflection)
    reflection_draw.rounded_rectangle(
        [0, 0, width-1, reflection_height-1],
        radius=radius,
        fill=(*SKY_BLUE, int(40 * intensity))
    )
    bar.paste(reflection, (0, height - reflection_height), reflection)
    
    return bar


def create_bar_shadow(width: int, height: int, blur: int = 15) -> Image.Image:
    """Create a soft shadow for a bar."""
    shadow = Image.new('RGBA', (width + 20, height + 20), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    radius = width // 2
    
    draw.rounded_rectangle(
        [8, 8, width + 8, height + 8],
        radius=radius,
        fill=(0, 0, 0, 80)
    )
    
    return shadow.filter(ImageFilter.GaussianBlur(radius=blur))


def create_waveform_v3(size: int) -> Image.Image:
    """Create three premium glass bars representing audio waveform."""
    waveform = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Bar heights and positions
    bars = [
        {"height": 0.32, "offset": -0.28, "opacity": 0.8},  # Left
        {"height": 0.58, "offset": 0.0, "opacity": 1.0},    # Center (main)
        {"height": 0.38, "offset": 0.28, "opacity": 0.8},   # Right
    ]
    
    bar_width = size // 8
    
    for bar_config in bars:
        bar_height = int(size * bar_config["height"] * 0.55)
        opacity = bar_config["opacity"]
        
        # Create bar and shadow
        bar = create_glass_bar_v3(bar_width, bar_height, opacity)
        shadow = create_bar_shadow(bar_width, bar_height)
        
        # Calculate position
        center_x = size // 2 + int(size * bar_config["offset"])
        center_y = size // 2
        x = center_x - bar_width // 2
        y = center_y - bar_height // 2
        
        # Paste shadow first
        waveform.paste(shadow, (x - 5, y + 5), shadow)
        # Then bar
        waveform.paste(bar, (x, y), bar)
    
    return waveform


def create_ambient_glow(size: int) -> Image.Image:
    """Create ambient glow effect behind waveform."""
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    
    center = size // 2
    # Soft glow around center
    for r in range(size // 5, size // 12, -3):
        alpha = int(25 * (r / (size // 5)))
        draw.ellipse(
            [center - r, center - r, center + r, center + r],
            outline=(*SKY_BLUE, alpha),
            width=3
        )
    
    return glow.filter(ImageFilter.GaussianBlur(radius=25))


def create_bokeh_dots(size: int) -> Image.Image:
    """Create soft bokeh-style floating dots."""
    dots = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(dots)
    
    # Strategic dot placement for visual balance
    dot_positions = [
        {"x": 0.16, "y": 0.20, "r": 0.028, "a": 0.20},
        {"x": 0.84, "y": 0.24, "r": 0.022, "a": 0.15},
        {"x": 0.20, "y": 0.78, "r": 0.032, "a": 0.18},
        {"x": 0.80, "y": 0.72, "r": 0.025, "a": 0.22},
        {"x": 0.12, "y": 0.50, "r": 0.018, "a": 0.12},
        {"x": 0.88, "y": 0.48, "r": 0.020, "a": 0.14},
    ]
    
    for dot in dot_positions:
        x = int(size * dot["x"])
        y = int(size * dot["y"])
        r = int(size * dot["r"])
        alpha = int(255 * dot["a"])
        
        draw.ellipse([x-r, y-r, x+r, y+r], fill=(*PURE_WHITE, alpha))
    
    return dots.filter(ImageFilter.GaussianBlur(radius=8))


def create_drop_shadow(size: int, offset: int = 25, blur: int = 50) -> Image.Image:
    """Create professional drop shadow."""
    shadow = Image.new('RGBA', (size + offset*2, size + offset*2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    
    corner = int(size * 0.22)
    draw.rounded_rectangle(
        [offset, offset, size + offset, size + offset],
        radius=corner,
        fill=(0, 0, 0, 90)
    )
    
    return shadow.filter(ImageFilter.GaussianBlur(radius=blur))


def create_icon_final() -> Image.Image:
    """Create the final 1024x1024 icon."""
    size = 1024
    
    print("  🎨 Creating gradient background...")
    bg = create_smooth_gradient(size)
    base = bg.convert('RGBA')
    
    print("  ✨ Adding ambient glow...")
    glow = create_ambient_glow(size)
    base = Image.alpha_composite(base, glow)
    
    print("  🎵 Creating glass waveform...")
    waveform = create_waveform_v3(size)
    
    print("  🔵 Adding bokeh elements...")
    dots = create_bokeh_dots(size)
    
    print("  🖼️  Compositing final image...")
    # Combine layers
    icon = base
    icon = Image.alpha_composite(icon, waveform)
    icon = Image.alpha_composite(icon, dots)
    
    # Add outer shadow
    shadow = create_drop_shadow(size)
    final_size = size + 50
    final = Image.new('RGBA', (final_size, final_size), (0, 0, 0, 0))
    final.paste(shadow, (0, 0))
    final.paste(icon, (25, 25))
    
    # Enhance
    enhancer = ImageEnhance.Contrast(final)
    final = enhancer.enhance(1.05)
    enhancer = ImageEnhance.Sharpness(final)
    final = enhancer.enhance(1.1)
    
    return final


def create_iconset(source: Image.Image) -> Path:
    """Create all required icon sizes."""
    print("📐 Generating icon sizes...")
    
    iconset_dir = ASSETS_DIR / "AppIcon.iconset"
    iconset_dir.mkdir(parents=True, exist_ok=True)
    
    for size, name in ICON_SIZES:
        icon = source.copy()
        # Center crop if needed
        w, h = icon.size
        if w != h:
            min_dim = min(w, h)
            left = (w - min_dim) // 2
            top = (h - min_dim) // 2
            icon = icon.crop((left, top, left + min_dim, top + min_dim))
        
        icon = icon.resize((size, size), Image.Resampling.LANCZOS)
        filename = iconset_dir / f"icon_{name}.png"
        icon.save(filename, "PNG")
        print(f"  ✅ {name}")
    
    return iconset_dir


def convert_to_icns(iconset_dir: Path) -> Path:
    """Convert iconset to .icns file."""
    print("🔧 Converting to .icns format...")
    
    icns_path = ASSETS_DIR / "AppIcon.icns"
    
    try:
        import subprocess
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir)],
            capture_output=True,
            check=True
        )
        
        temp = iconset_dir.parent / "AppIcon.icns"
        if temp.exists():
            temp.rename(icns_path)
            print(f"  ✅ {icns_path}")
            return icns_path
    except Exception as e:
        print(f"  ⚠️  Error: {e}")
    
    return None


def main():
    print("=" * 60)
    print("EchoPanel App Icon Generator")
    print("Final Premium Version")
    print("=" * 60)
    
    ASSETS_DIR.mkdir(exist_ok=True)
    
    print("\n🎨 Creating master icon...")
    master = create_icon_final()
    
    # Ensure 1024x1024
    if master.size != (1024, 1024):
        w, h = master.size
        left = (w - 1024) // 2
        top = (h - 1024) // 2
        master = master.crop((left, top, left + 1024, top + 1024))
    
    # Save master
    master_path = ASSETS_DIR / "app_icon_final_1024.png"
    master.save(master_path, "PNG")
    print(f"\n💾 Saved: {master_path}")
    
    # Generate iconset
    iconset_dir = create_iconset(master)
    icns_path = convert_to_icns(iconset_dir)
    
    print("\n" + "=" * 60)
    print("✨ Icon generation complete!")
    print("=" * 60)
    print(f"\n📦 Output: {master_path}")
    print(f"👁️  Preview: open {master_path}")


if __name__ == "__main__":
    main()
