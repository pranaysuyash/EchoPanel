#!/usr/bin/env python3
"""
Generate a professional macOS app icon for EchoPanel with glass morphism effects.

This creates a high-quality icon programmatically with:
- Glass morphism (frosted glass) effects
- 3D depth and layering
- macOS superellipse shape
- Professional gradients and shadows
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

PROJECT_ROOT = Path(__file__).parent.parent
ASSETS_DIR = PROJECT_ROOT / "assets"

# Brand colors
PRIMARY_BLUE = (31, 111, 235)  # #1f6feb
DARK_BLUE = (13, 35, 75)
LIGHT_BLUE = (88, 166, 255)
GLASS_WHITE = (255, 255, 255, 180)

# Icon sizes for macOS
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


def create_gradient(size: int, color1: tuple, color2: tuple, angle: float = 45) -> Image.Image:
    """Create a linear gradient image."""
    img = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(img)
    
    # Simple top-to-bottom gradient
    for y in range(size):
        ratio = y / size
        r = int(color1[0] * (1 - ratio) + color2[0] * ratio)
        g = int(color1[1] * (1 - ratio) + color2[1] * ratio)
        b = int(color1[2] * (1 - ratio) + color2[2] * ratio)
        draw.line([(0, y), (size, y)], fill=(r, g, b))
    
    return img


def create_radial_gradient(size: int, center_color: tuple, edge_color: tuple) -> Image.Image:
    """Create a radial gradient image."""
    img = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(img)
    center = size // 2
    max_dist = math.sqrt(2) * center
    
    for y in range(size):
        for x in range(0, size, 4):  # Step by 4 for speed
            dist = math.sqrt((x - center)**2 + (y - center)**2)
            ratio = min(1.0, dist / max_dist)
            r = int(center_color[0] * (1 - ratio) + edge_color[0] * ratio)
            g = int(center_color[1] * (1 - ratio) + edge_color[1] * ratio)
            b = int(center_color[2] * (1 - ratio) + edge_color[2] * ratio)
            draw.point([(x, y)], fill=(r, g, b))
            # Fill the next 3 pixels horizontally for speed
            for dx in range(1, 4):
                if x + dx < size:
                    draw.point([(x + dx, y)], fill=(r, g, b))
    
    return img


def create_superellipse_mask(size: int, radius_ratio: float = 0.22) -> Image.Image:
    """Create a macOS-style superellipse mask."""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    
    # macOS uses a superellipse (squircle) shape
    # We approximate with a heavily rounded rectangle
    corner_radius = int(size * radius_ratio)
    
    draw.rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=corner_radius,
        fill=255
    )
    
    return mask


def create_glass_bar(width: int, height: int, opacity: int = 200) -> Image.Image:
    """Create a glass morphism bar."""
    bar = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(bar)
    
    # Main glass body
    corner_radius = width // 2
    draw.rounded_rectangle(
        [0, 0, width - 1, height - 1],
        radius=corner_radius,
        fill=(255, 255, 255, opacity)
    )
    
    # Top highlight (glass reflection)
    highlight_height = height // 4
    highlight = Image.new('RGBA', (width, highlight_height), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.rounded_rectangle(
        [0, 0, width - 1, highlight_height - 1],
        radius=corner_radius,
        fill=(255, 255, 255, min(255, opacity + 40))
    )
    bar.paste(highlight, (0, 0))
    
    return bar


def create_glow(size: int, color: tuple, intensity: float = 0.3) -> Image.Image:
    """Create a glow effect."""
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    center = size // 2
    
    for r in range(center, 0, -2):
        alpha = int(255 * intensity * (r / center))
        draw.ellipse(
            [center - r, center - r, center + r, center + r],
            outline=(*color, alpha)
        )
    
    return glow.filter(ImageFilter.GaussianBlur(radius=20))


def create_icon_base(size: int) -> Image.Image:
    """Create the base icon with background."""
    # Create radial gradient background
    bg = create_radial_gradient(
        size,
        PRIMARY_BLUE,  # Center
        DARK_BLUE       # Edge
    )
    
    # Convert to RGBA
    base = bg.convert('RGBA')
    
    # Add subtle glow layer
    glow = create_glow(size, LIGHT_BLUE, 0.2)
    base = Image.alpha_composite(base, glow)
    
    return base


def create_audio_waveform(size: int) -> Image.Image:
    """Create glass morphism audio waveform bars."""
    waveform = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Define three bars with different heights (audio visualizer style)
    bar_configs = [
        {"height_ratio": 0.45, "opacity": 180, "offset": -0.25},  # Left
        {"height_ratio": 0.75, "opacity": 220, "offset": 0},       # Center (tallest)
        {"height_ratio": 0.55, "opacity": 180, "offset": 0.25},   # Right
    ]
    
    bar_width = size // 8
    bar_gap = size // 16
    total_width = 3 * bar_width + 2 * bar_gap
    start_x = (size - total_width) // 2
    center_y = size // 2
    
    for i, config in enumerate(bar_configs):
        bar_height = int(size * config["height_ratio"] * 0.6)
        x = start_x + i * (bar_width + bar_gap)
        y = center_y - bar_height // 2
        
        # Create glass bar
        bar = create_glass_bar(bar_width, bar_height, config["opacity"])
        
        # Add subtle shadow behind bar
        shadow = bar.copy()
        shadow_data = []
        for item in shadow.getdata():
            if item[3] > 0:
                shadow_data.append((0, 0, 0, 60))
            else:
                shadow_data.append((0, 0, 0, 0))
        shadow.putdata(shadow_data)
        shadow = shadow.filter(ImageFilter.GaussianBlur(radius=4))
        
        # Paste shadow then bar
        waveform.paste(shadow, (x + 4, y + 4), shadow)
        waveform.paste(bar, (x, y), bar)
    
    return waveform


def create_floating_particles(size: int) -> Image.Image:
    """Create subtle floating glass particles for depth."""
    particles = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(particles)
    
    # Add a few subtle floating circles
    particle_configs = [
        {"x": 0.2, "y": 0.25, "r": 0.04, "a": 60},
        {"x": 0.8, "y": 0.3, "r": 0.03, "a": 50},
        {"x": 0.75, "y": 0.7, "r": 0.05, "a": 40},
        {"x": 0.25, "y": 0.75, "r": 0.035, "a": 55},
    ]
    
    for p in particle_configs:
        x = int(size * p["x"])
        y = int(size * p["y"])
        r = int(size * p["r"])
        alpha = p["a"]
        
        draw.ellipse(
            [x - r, y - r, x + r, y + r],
            fill=(255, 255, 255, alpha)
        )
    
    return particles.filter(ImageFilter.GaussianBlur(radius=3))


def create_icon_1024() -> Image.Image:
    """Create the main 1024x1024 icon."""
    size = 1024
    
    print("  🎨 Creating base layer...")
    base = create_icon_base(size)
    
    print("  🎵 Creating audio waveform...")
    waveform = create_audio_waveform(size)
    
    print("  ✨ Adding floating particles...")
    particles = create_floating_particles(size)
    
    print("  🔲 Creating superellipse mask...")
    mask = create_superellipse_mask(size)
    
    print("  🌑 Creating shadow...")
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    corner_radius = int(size * 0.22)
    shadow_offset = 20
    shadow_draw.rounded_rectangle(
        [shadow_offset, shadow_offset, size - 1 + shadow_offset, size - 1 + shadow_offset],
        radius=corner_radius,
        fill=(0, 0, 0, 80)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=30))
    
    # Composite all layers
    print("  🖼️  Compositing layers...")
    
    # Start with shadow
    final = shadow
    
    # Add base with mask
    base.putalpha(mask)
    final = Image.alpha_composite(final, base)
    
    # Add waveform
    final = Image.alpha_composite(final, waveform)
    
    # Add particles
    final = Image.alpha_composite(final, particles)
    
    # Apply slight sharpening
    enhancer = ImageEnhance.Sharpness(final)
    final = enhancer.enhance(1.2)
    
    return final


def create_iconset(source: Image.Image) -> Path:
    """Create all icon sizes from the source image."""
    print("📐 Generating icon sizes...")
    
    iconset_dir = ASSETS_DIR / "AppIcon-Pro.iconset"
    iconset_dir.mkdir(parents=True, exist_ok=True)
    
    for size, name in ICON_SIZES:
        icon = source.copy()
        icon = icon.resize((size, size), Image.Resampling.LANCZOS)
        
        filename = iconset_dir / f"icon_{name}.png"
        icon.save(filename, "PNG")
        print(f"  ✅ {name} ({size}x{size})")
    
    return iconset_dir


def convert_to_icns(iconset_dir: Path) -> Path:
    """Convert iconset to .icns file."""
    print("🔧 Converting to .icns...")
    
    icns_path = ASSETS_DIR / "AppIcon-Pro.icns"
    
    try:
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir)],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Move to final location
        temp_icns = iconset_dir.parent / "AppIcon-Pro.icns"
        if temp_icns.exists():
            temp_icns.rename(icns_path)
            print(f"  ✅ Created: {icns_path}")
            print(f"  📊 Size: {icns_path.stat().st_size / 1024:.1f} KB")
            return icns_path
            
    except subprocess.CalledProcessError as e:
        print(f"  ⚠️  iconutil failed: {e}")
    except FileNotFoundError:
        print("  ⚠️  iconutil not found")
    
    return None


def main():
    """Generate the professional app icon."""
    print("=" * 60)
    print("EchoPanel Pro App Icon Generator")
    print("Glass Morphism Edition")
    print("=" * 60)
    
    ASSETS_DIR.mkdir(exist_ok=True)
    
    # Generate 1024x1024 master icon
    print("\n🎨 Creating master icon (1024x1024)...")
    master = create_icon_1024()
    
    # Save master
    master_path = ASSETS_DIR / "app_icon_pro_1024.png"
    master.save(master_path, "PNG")
    print(f"\n💾 Saved master: {master_path}")
    
    # Create iconset
    iconset_dir = create_iconset(master)
    
    # Convert to icns
    icns_path = convert_to_icns(iconset_dir)
    
    # Also save as main AppIcon.icns
    if icns_path:
        main_icns = ASSETS_DIR / "AppIcon.icns"
        import shutil
        shutil.copy(icns_path, main_icns)
        print(f"\n📌 Copied to main: {main_icns}")
    
    print("\n" + "=" * 60)
    print("✨ Icon generation complete!")
    print("=" * 60)
    print(f"\n📦 Outputs:")
    print(f"   Master PNG: {master_path}")
    print(f"   Iconset: {iconset_dir}")
    if icns_path:
        print(f"   ICNS: {icns_path}")
    print(f"\n👁️  Preview: open {master_path}")


if __name__ == "__main__":
    import subprocess
    main()
