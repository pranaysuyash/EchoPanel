#!/usr/bin/env python3
"""
Convert Silero VAD ONNX model to Core ML format for macOS app bundling.
"""

import onnx_coreml
import numpy as np
from pathlib import Path

def convert_silero_vad():
    # Find the ONNX model
    venv_path = Path(".venv/lib/python3.11/site-packages/faster_whisper/assets/silero_vad.onnx")
    if not venv_path.exists():
        print(f"❌ ONNX model not found at {venv_path}")
        return False

    print(f"📁 Found ONNX model at: {venv_path}")

    # Convert to Core ML using onnx-coreml
    print("🔄 Converting to Core ML...")
    output_path = Path("macapp/MeetingListenerApp/Resources/silero_vad.mlmodel")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Use onnx-coreml to convert
    onnx_coreml.convert(
        model=str(venv_path),
        output_path=str(output_path),
        minimum_ios_deployment_target="15.0",  # iOS 15+ / macOS 12+
        minimum_macos_deployment_target="12.0"
    )

    print("✅ Conversion complete!")
    print(f"📊 Model saved at: {output_path}")
    return True

if __name__ == "__main__":
    success = convert_silero_vad()
    if success:
        print("\n🎉 Ready to bundle with macOS app!")
    else:
        print("\n❌ Conversion failed!")
        exit(1)