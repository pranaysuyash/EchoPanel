#!/usr/bin/env python3
"""
Generate EchoPanel macOS app icon using AI image generation.

Supports:
- OpenAI DALL-E 3
- Hugging Face Inference API (FLUX, Stable Diffusion)
- NanoBanana (if API key available)

Usage:
    python scripts/generate_app_icon_ai.py [--provider openai|hf|nanobanana]

Requirements:
- Set OPENAI_API_KEY in environment for DALL-E
- HF_TOKEN already set in .env for Hugging Face
"""

import argparse
import base64
import json
import os
import subprocess
import sys
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageFilter

PROJECT_ROOT = Path(__file__).parent.parent
ASSETS_DIR = PROJECT_ROOT / "assets"

# macOS icon sizes
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


def get_hf_token():
    """Get Hugging Face token from environment."""
    return os.getenv("HF_TOKEN") or os.getenv("ECHOPANEL_HF_TOKEN")


def get_openai_key():
    """Get OpenAI API key from environment."""
    return os.getenv("OPENAI_API_KEY")


def get_nanobanana_key():
    """Get NanoBanana API key from environment."""
    return os.getenv("NANOBANANA_API_KEY")


def generate_with_hf(prompt: str, model: str = "black-forest-labs/FLUX.1-schnell") -> Image.Image:
    """Generate image using Hugging Face Inference API."""
    import requests
    
    token = get_hf_token()
    if not token:
        raise ValueError("HF_TOKEN not found in environment")
    
    print(f"  🤗 Using Hugging Face: {model}")
    
    api_url = f"https://api-inference.huggingface.co/models/{model}"
    headers = {"Authorization": f"Bearer {token}"}
    
    payload = {
        "inputs": prompt,
        "parameters": {
            "width": 1024,
            "height": 1024,
            "num_inference_steps": 4,  # Fast generation for FLUX schnell
        }
    }
    
    response = requests.post(api_url, headers=headers, json=payload)
    
    if response.status_code == 200:
        image = Image.open(BytesIO(response.content))
        return image
    else:
        raise Exception(f"HF API error: {response.status_code} - {response.text}")


def generate_with_openai(prompt: str) -> Image.Image:
    """Generate image using OpenAI DALL-E 3."""
    import openai
    
    key = get_openai_key()
    if not key:
        raise ValueError("OPENAI_API_KEY not found in environment")
    
    print("  🤖 Using OpenAI DALL-E 3")
    
    client = openai.OpenAI(api_key=key)
    
    response = client.images.generate(
        model="dall-e-3",
        prompt=prompt,
        size="1024x1024",
        quality="standard",
        n=1,
    )
    
    # Download the image
    import requests
    image_url = response.data[0].url
    image_response = requests.get(image_url)
    image = Image.open(BytesIO(image_response.content))
    
    return image


def generate_with_nanobanana(prompt: str) -> Image.Image:
    """Generate image using NanoBanana API."""
    import requests
    
    key = get_nanobanana_key()
    if not key:
        raise ValueError("NANOBANANA_API_KEY not found in environment")
    
    print("  🍌 Using NanoBanana")
    
    # NanoBanana uses replicate-like API
    api_url = "https://api.nanobanana.dev/v1/predictions"
    headers = {
        "Authorization": f"Token {key}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "version": "latest",
        "input": {
            "prompt": prompt,
            "width": 1024,
            "height": 1024,
        }
    }
    
    response = requests.post(api_url, headers=headers, json=payload)
    
    if response.status_code == 200:
        result = response.json()
        # Poll for result
        prediction_id = result["id"]
        
        import time
        while True:
            status_response = requests.get(
                f"{api_url}/{prediction_id}",
                headers=headers
            )
            status = status_response.json()
            
            if status["status"] == "succeeded":
                image_url = status["output"][0]
                image_response = requests.get(image_url)
                return Image.open(BytesIO(image_response.content))
            elif status["status"] == "failed":
                raise Exception(f"Generation failed: {status.get('error')}")
            
            time.sleep(1)
    else:
        raise Exception(f"NanoBanana API error: {response.status_code}")


def create_macos_icon_prompt() -> str:
    """Create a detailed prompt for a professional macOS app icon."""
    return """Professional macOS app icon for "EchoPanel" - an AI meeting transcription app.

Design elements:
- Circular app icon with rounded corners (superellipse shape, not perfect circle)
- Glass morphism / Liquid Glass style (frosted glass effect, subtle transparency)
- Layered depth with floating elements
- Clean, modern aesthetic matching macOS design language

Visual concept:
- Abstract audio waveform visualization made of floating glass bars
- Or sound waves emanating from a central point
- Or a stylized "E" formed by audio frequency bars
- Floating glass panels suggesting multiple meeting participants

Color palette:
- Deep electric blue (#1f6feb) as primary
- White and light blue glass elements
- Subtle gradient backgrounds
- Metallic silver accents

Style:
- 3D rendered, photorealistic glass materials
- Soft lighting with subtle reflections
- Depth and dimensionality
- Clean, minimal, premium feel
- Similar quality to Apple's built-in app icons

Technical:
- Isolated on transparent background
- Square format with centered icon
- No text or lettering
- No hard edges, everything rounded and smooth
"""


def process_for_macos(original: Image.Image) -> Image.Image:
    """Process the generated image into a proper macOS app icon."""
    print("  🎨 Processing for macOS...")
    
    # Ensure RGBA
    if original.mode != 'RGBA':
        original = original.convert('RGBA')
    
    # Create square canvas
    size = 1024
    output = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Resize and center the original
    original.thumbnail((size, size), Image.Resampling.LANCZOS)
    
    # Center it
    x = (size - original.width) // 2
    y = (size - original.height) // 2
    output.paste(original, (x, y))
    
    # Apply macOS icon mask (superellipse shape)
    mask = create_macos_mask(size)
    output.putalpha(mask)
    
    # Add subtle shadow for depth
    shadow = create_drop_shadow(output, size)
    
    # Composite
    final = Image.alpha_composite(shadow, output)
    
    return final


def create_macos_mask(size: int) -> Image.Image:
    """Create a macOS superellipse mask."""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    
    # macOS icon shape (superellipse approximation)
    # Use a large radius for rounded corners
    corner_radius = int(size * 0.22)  # macOS uses ~22% of size for corner radius
    
    draw.rounded_rectangle(
        [0, 0, size-1, size-1],
        radius=corner_radius,
        fill=255
    )
    
    return mask


def create_drop_shadow(image: Image.Image, size: int) -> Image.Image:
    """Create a subtle drop shadow."""
    # Create shadow layer
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Blurred black image for shadow
    shadow_mask = image.copy()
    # Fill with shadow color
    shadow_data = []
    for item in shadow_mask.getdata():
        if item[3] > 0:  # If pixel is not transparent
            shadow_data.append((0, 0, 0, 40))  # Subtle black shadow
        else:
            shadow_data.append((0, 0, 0, 0))
    
    shadow_mask.putdata(shadow_data)
    
    # Offset slightly
    offset = 8
    shadow.paste(shadow_mask, (offset, offset))
    
    # Blur
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=12))
    
    return shadow


def create_iconset(source: Image.Image):
    """Create all icon sizes from the source image."""
    print("📐 Generating icon sizes...")
    
    iconset_dir = ASSETS_DIR / "AppIcon-AI.iconset"
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
    
    icns_path = ASSETS_DIR / "AppIcon-AI.icns"
    
    try:
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir)],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Move to final location
        temp_icns = iconset_dir.parent / "AppIcon-AI.icns"
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
    parser = argparse.ArgumentParser(description="Generate EchoPanel app icon using AI")
    parser.add_argument(
        "--provider",
        choices=["openai", "hf", "nanobanana", "auto"],
        default="auto",
        help="Image generation provider (default: auto)"
    )
    parser.add_argument(
        "--hf-model",
        default="black-forest-labs/FLUX.1-schnell",
        help="Hugging Face model to use"
    )
    args = parser.parse_args()
    
    print("=" * 60)
    print("EchoPanel AI App Icon Generator")
    print("=" * 60)
    
    # Determine provider
    provider = args.provider
    if provider == "auto":
        if get_openai_key():
            provider = "openai"
        elif get_hf_token():
            provider = "hf"
        elif get_nanobanana_key():
            provider = "nanobanana"
        else:
            print("❌ No API keys found. Set OPENAI_API_KEY, HF_TOKEN, or NANOBANANA_API_KEY")
            sys.exit(1)
    
    # Check credentials
    if provider == "openai" and not get_openai_key():
        print("❌ OPENAI_API_KEY not found")
        sys.exit(1)
    elif provider == "hf" and not get_hf_token():
        print("❌ HF_TOKEN not found")
        sys.exit(1)
    elif provider == "nanobanana" and not get_nanobanana_key():
        print("❌ NANOBANANA_API_KEY not found")
        sys.exit(1)
    
    # Generate image
    print(f"\n🎨 Generating icon with {provider}...")
    prompt = create_macos_icon_prompt()
    
    try:
        if provider == "openai":
            generated = generate_with_openai(prompt)
        elif provider == "hf":
            generated = generate_with_hf(prompt, args.hf_model)
        elif provider == "nanobanana":
            generated = generate_with_nanobanana(prompt)
        
        # Process for macOS
        processed = process_for_macos(generated)
        
        # Save original for reference
        original_path = ASSETS_DIR / "app_icon_original_ai.png"
        generated.save(original_path)
        print(f"  💾 Saved original: {original_path}")
        
        # Create iconset
        iconset_dir = create_iconset(processed)
        
        # Convert to icns
        icns_path = convert_to_icns(iconset_dir)
        
        print("\n" + "=" * 60)
        print("✨ Icon generation complete!")
        print("=" * 60)
        
        if icns_path:
            print(f"\n📦 Output: {icns_path}")
            print(f"   Preview: open {ASSETS_DIR}/app_icon_original_ai.png")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    from PIL import ImageDraw
    main()
