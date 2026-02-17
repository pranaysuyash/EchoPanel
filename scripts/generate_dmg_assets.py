#!/usr/bin/env python3
"""
Generate DMG background and other marketing assets for EchoPanel.

Usage:
    python scripts/generate_dmg_assets.py
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(__file__).parent.parent
ASSETS_DIR = PROJECT_ROOT / "assets"

# Brand colors
BRAND_BLUE = "#1f6feb"
BACKGROUND_DARK = "#0d1117"
TEXT_WHITE = "#ffffff"


def create_dmg_background():
    """Create a sleek DMG background image."""
    print("🎨 Creating DMG background...")
    
    # DMG window size (800x500 as per create_dmg.sh)
    width, height = 800, 500
    img = Image.new("RGB", (width, height), BACKGROUND_DARK)
    draw = ImageDraw.Draw(img)
    
    # Add subtle gradient effect
    for y in range(height):
        # Create a subtle gradient from dark to slightly lighter
        ratio = y / height
        r = int(13 + ratio * 20)
        g = int(17 + ratio * 20)
        b = int(23 + ratio * 20)
        draw.line([(0, y), (width, y)], fill=(r, g, b))
    
    # Draw brand icon in center-top
    icon_size = 120
    icon_x = width // 2 - icon_size // 2
    icon_y = 80
    
    # Draw circular icon background
    circle_bbox = [
        icon_x, icon_y,
        icon_x + icon_size, icon_y + icon_size
    ]
    draw.ellipse(circle_bbox, fill=BRAND_BLUE)
    
    # Draw three bars (audio waveform)
    bar_width = 12
    bar_gap = 10
    bar_heights = [0.4, 0.7, 0.55]
    
    total_bars_width = 3 * bar_width + 2 * bar_gap
    start_x = icon_x + (icon_size - total_bars_width) // 2
    center_y = icon_y + icon_size // 2
    
    for i, height_pct in enumerate(bar_heights):
        bar_height = int(icon_size * height_pct * 0.6)
        x = start_x + i * (bar_width + bar_gap)
        y = center_y - bar_height // 2
        
        # Draw rounded rectangle for bar
        bar_bbox = [x, y, x + bar_width, y + bar_height]
        corner_radius = bar_width // 2
        draw.rounded_rectangle(bar_bbox, radius=corner_radius, fill=TEXT_WHITE)
    
    # Add app name
    try:
        # Try to use system font
        font_large = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 36)
        font_small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 18)
    except:
        font_large = ImageFont.load_default()
        font_small = font_large
    
    # App name
    app_name = "EchoPanel"
    bbox = draw.textbbox((0, 0), app_name, font=font_large)
    text_width = bbox[2] - bbox[0]
    text_x = (width - text_width) // 2
    text_y = icon_y + icon_size + 30
    draw.text((text_x, text_y), app_name, font=font_large, fill=TEXT_WHITE)
    
    # Tagline
    tagline = "AI meeting notes that stay present with you"
    bbox = draw.textbbox((0, 0), tagline, font=font_small)
    text_width = bbox[2] - bbox[0]
    text_x = (width - text_width) // 2
    text_y = text_y + 50
    draw.text((text_x, text_y), tagline, font=font_small, fill="#8b949e")
    
    # Instructions
    instructions = [
        "1. Drag EchoPanel to your Applications folder",
        "2. Open EchoPanel from Applications",
        "3. Grant permissions when prompted"
    ]
    
    inst_y = height - 120
    for instruction in instructions:
        bbox = draw.textbbox((0, 0), instruction, font=font_small)
        text_width = bbox[2] - bbox[0]
        text_x = (width - text_width) // 2
        draw.text((text_x, inst_y), instruction, font=font_small, fill="#8b949e")
        inst_y += 30
    
    # Save
    output_path = ASSETS_DIR / "dmg_background.png"
    img.save(output_path, "PNG")
    print(f"  ✅ Created: {output_path}")
    
    return output_path


def create_marketing_screenshot_template():
    """Create a template for marketing screenshots."""
    print("🎨 Creating marketing screenshot template...")
    
    # MacBook Pro 14" resolution
    width, height = 1512, 982
    img = Image.new("RGB", (width, height), BACKGROUND_DARK)
    draw = ImageDraw.Draw(img)
    
    # Add gradient
    for y in range(height):
        ratio = y / height
        r = int(13 + ratio * 10)
        g = int(17 + ratio * 10)
        b = int(23 + ratio * 10)
        draw.line([(0, y), (width, y)], fill=(r, g, b))
    
    # Add placeholder text
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 48)
    except:
        font = ImageFont.load_default()
    
    text = "Screenshot Placeholder"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    text_x = (width - text_width) // 2
    text_y = (height - text_height) // 2
    
    draw.text((text_x, text_y), text, font=font, fill="#8b949e")
    
    output_path = ASSETS_DIR / "screenshot_template.png"
    img.save(output_path, "PNG")
    print(f"  ✅ Created: {output_path}")
    
    return output_path


def main():
    """Generate all marketing assets."""
    print("=" * 50)
    print("EchoPanel Asset Generator")
    print("=" * 50)
    
    ASSETS_DIR.mkdir(exist_ok=True)
    
    create_dmg_background()
    create_marketing_screenshot_template()
    
    print("\n" + "=" * 50)
    print("✨ Asset generation complete!")
    print("=" * 50)
    print(f"\n📦 Assets in: {ASSETS_DIR}")


if __name__ == "__main__":
    main()
