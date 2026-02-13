# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec for bundling EchoPanel Python backend.

This creates a standalone executable that includes:
- FastAPI/uvicorn server
- faster-whisper for ASR
- All Python dependencies
"""

import sys
from pathlib import Path

# Project paths - use absolute paths
# When run via python -m PyInstaller, the cwd is the project root
project_root = Path.cwd()
server_dir = project_root / "server"
venv_dir = project_root / ".venv"

# Analysis configuration
a = Analysis(
    [str(server_dir / "main.py")],
    pathex=[
        str(server_dir),
        str(project_root),
        str(venv_dir / "lib" / f"python{sys.version_info.major}.{sys.version_info.minor}" / "site-packages"),
    ],
    binaries=[],
    datas=[
        # Include any data files from server directory
        (str(server_dir / "config"), "server/config"),
    ],
    hiddenimports=[
        # FastAPI/Starlette
        "fastapi",
        "starlette",
        "uvicorn",
        "uvicorn.logging",
        "uvicorn.loops",
        "uvicorn.loops.auto",
        "uvicorn.protocols",
        "uvicorn.protocols.http",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.websockets",
        "uvicorn.protocols.websockets.auto",
        
        # faster-whisper and dependencies
        "faster_whisper",
        "ctranslate2",
        "tokenizers",
        "huggingface_hub",
        
        # PyTorch (for faster-whisper)
        "torch",
        "torchaudio",
        
        # Audio processing
        "numpy",
        "scipy",
        "av",
        
        # WebSocket
        "websockets",
        "wsproto",
        
        # ASR providers
        "whisper",
        
        # Additional providers that might be used
        "pywhispercpp",
        
        # Server modules
        "server.api.ws_live_listener",
        "server.services.asr_providers",
        "server.services.asr_stream",
        "server.services.model_preloader",
        "server.services.diarization",
        "server.services.vad_filter",
        "server.services.analysis_stream",
        "server.services.ner_pipeline",
        "server.services.rag_store",
        "server.services.embedding_service",
        "server.services.degrade_ladder",
        "server.services.capability_detector",
        "server.services.provider_faster_whisper",
        "server.services.provider_whisper_cpp",
        "server.services.provider_voxtral_realtime",
        
        # Pydantic settings
        "pydantic",
        "pydantic_settings",
        
        # Logging
        "logging",
        "logging.handlers",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Exclude large unnecessary packages to reduce bundle size
        "matplotlib",
        "PIL",
        "Pillow",
        "tkinter",
        "PyQt5",
        "PyQt6",
        "PySide2",
        "PySide6",
        "wx",
        "wxPython",
        "ipython",
        "jupyter",
        "notebook",
        "pytest",
        "black",
        "flake8",
        "mypy",
        "pylint",
        "sphinx",
        "setuptools",
        "pip",
        "wheel",
        "twine",
        "build",
        "install",
        "develop",
        # Exclude test files
        "tests",
        "test",
        "_test",
        "__test",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    noarchive=False,
)

# Remove duplicate entries
pyz = PYZ(a.pure, a.zipped_data)

# Create the executable
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='echopanel-server',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,  # Keep console for debugging; change to False for GUI-only
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    # macOS specific
    bundle_identifier='com.echopanel.server',
)

# For macOS .app bundle (optional - we handle this separately)
# app = BUNDLE(
#     exe,
#     name='echopanel-server.app',
#     bundle_identifier='com.echopanel.server',
# )
