#!/usr/bin/env python3
"""
Generate EchoPanel macOS app icon from brand SVG design.

Creates all required sizes for macOS .icns file:
- 16x16, 32x32, 128x128, 256x256, 512x512, 1024x1024
- @2x versions for Retina displays

Usage:
    python scripts/generate_app_icon.py
    
Output:
    assets/AppIcon.iconset/ - Folder with all icon sizes
    assets/AppIcon.icns - Final icon file for Xcode
"""

import os
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw

# Configuration
PROJECT_ROOT = Path(__file__).parent.parent
OUTPUT_DIR = PROJECT_ROOT / "assets" / "AppIcon.iconset"
ICNS_OUTPUT = PROJECT_ROOT / "assets" / "AppIcon.icns"

# Brand colors from landing page
BRAND_BLUE = "#1f6feb"  # From favicon
BACKGROUND_COLOR = "#1a1a2e"  # Dark blue background for contrast

# macOS icon sizes (1x and 2x)
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


def draw_rounded_rect(draw, xy, radius, fill):
    """Draw a rounded rectangle."""
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def create_icon(size: int) -> Image.Image:
    """
    Create the EchoPanel icon at the specified size.
    
    Design: Blue circle with three vertical bars (audio waveform style)
    Based on the favicon from the landing page.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Calculate dimensions
    padding = size // 8
    circle_radius = (size - 2 * padding) // 2
    center_x = size // 2
    center_y = size // 2
    
    # Draw circular background with brand blue
    circle_bbox = [
        center_x - circle_radius,
        center_y - circle_radius,
        center_x + circle_radius,
        center_y + circle_radius
    ]
    
    # Add subtle gradient effect by drawing main circle
    draw.ellipse(circle_bbox, fill=BRAND_BLUE)
    
    # Draw three vertical bars (audio waveform style)
    # Bar widths and heights vary to create waveform effect
    bar_width = max(2, size // 16)
    bar_gap = max(2, size // 12)
    
    # Bar heights (as percentage of circle diameter)
    bar_heights = [0.4, 0.7, 0.55]  # Short, tall, medium
    bar_colors = [
        (255, 255, 255, 230),  # Slightly transparent white
        (255, 255, 255, 255),  # Solid white
        (255, 255, 255, 230),  # Slightly transparent white
    ]
    
    total_bars_width = 3 * bar_width + 2 * bar_gap
    start_x = center_x - total_bars_width // 2
    
    for i, (height_pct, color) in enumerate(zip(bar_heights, bar_colors)):
        bar_height = int(circle_radius * 2 * height_pct * 0.6)  # Scale to fit in circle
        x = start_x + i * (bar_width + bar_gap)
        y = center_y - bar_height // 2
        
        # Draw bar with rounded top and bottom
        bar_bbox = [x, y, x + bar_width, y + bar_height]
        corner_radius = bar_width // 2
        draw.rounded_rectangle(bar_bbox, radius=corner_radius, fill=color)
    
    # Add subtle shadow/glow effect for depth (macOS style)
    # This is done by drawing a slightly larger circle behind
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_padding = 2
    shadow_bbox = [
        circle_bbox[0] + shadow_padding,
        circle_bbox[1] + shadow_padding,
        circle_bbox[2] + shadow_padding,
        circle_bbox[3] + shadow_padding
    ]
    shadow_draw.ellipse(shadow_bbox, fill=(0, 0, 0, 30))
    
    # Composite shadow under main image
    img = Image.alpha_composite(shadow, img)
    
    return img


def create_macos_iconset():
    """Create the .iconset folder with all required sizes."""
    print("🎨 Generating EchoPanel app icons...")
    
    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    # Generate each size
    for size, name in ICON_SIZES:
        icon = create_icon(size)
        filename = OUTPUT_DIR / f"icon_{name}.png"
        icon.save(filename, "PNG")
        print(f"  ✅ {name} ({size}x{size})")
    
    print(f"\n📁 Iconset created: {OUTPUT_DIR}")


def convert_to_icns():
    """Convert the iconset to .icns file using iconutil."""
    print("\n🔧 Converting to .icns format...")
    
    if not OUTPUT_DIR.exists():
        print("❌ Error: Iconset directory not found")
        return False
    
    # Remove existing .icns if present
    if ICNS_OUTPUT.exists():
        ICNS_OUTPUT.unlink()
    
    try:
        result = subprocess.run(
            ["iconutil", "-c", "icns", str(OUTPUT_DIR)],
            capture_output=True,
            text=True,
            check=True
        )
        
        # iconutil outputs to the parent directory with the same name
        temp_icns = OUTPUT_DIR.parent / "AppIcon.icns"
        if temp_icns.exists():
            # Move to final location
            temp_icns.rename(ICNS_OUTPUT)
            print(f"  ✅ Created: {ICNS_OUTPUT}")
            
            # Get file size
            size = ICNS_OUTPUT.stat().st_size
            print(f"  📊 Size: {size / 1024:.1f} KB")
            return True
            
    except subprocess.CalledProcessError as e:
        print(f"❌ iconutil failed: {e.stderr}")
        return False
    except FileNotFoundError:
        print("❌ iconutil not found (requires macOS)")
        return False
    
    return False


def verify_icon():
    """Verify the icon can be read and has the expected format."""
    if not ICNS_OUTPUT.exists():
        print("❌ Icon file not found")
        return False
    
    print("\n🔍 Verifying icon...")
    
    try:
        result = subprocess.run(
            ["sips", "-g", "all", str(ICNS_OUTPUT)],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Parse output for key info
        lines = result.stdout.strip().split("\n")
        for line in lines:
            if "dpiWidth" in line or "dpiHeight" in line:
                continue
            if any(x in line for x in ["pixelWidth", "pixelHeight", "format"]):
                print(f"  {line.strip()}")
        
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"⚠️  Could not verify icon: {e}")
        return False


def main():
    """Main entry point."""
    print("=" * 50)
    print("EchoPanel App Icon Generator")
    print("=" * 50)
    
    # Generate icons
    create_macos_iconset()
    
    # Convert to .icns
    if convert_to_icns():
        verify_icon()
        
        print("\n" + "=" * 50)
        print("✨ Icon generation complete!")
        print("=" * 50)
        print(f"\n📦 Output: {ICNS_OUTPUT}")
        print("\nNext steps:")
        print("  1. Copy AppIcon.icns to your Xcode project")
        print("  2. Add to Assets.xcassets or use directly in Info.plist")
        print("  3. Build and sign your app")
    else:
        print("\n⚠️  Iconset created but .icns conversion failed")
        print(f"   You can manually convert with:")
        print(f"   iconutil -c icns {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
