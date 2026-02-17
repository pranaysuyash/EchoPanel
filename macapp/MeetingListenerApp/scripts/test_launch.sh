#!/bin/bash

# EchoPanel Testing Launch Script
# Quick launch for manual testing sessions

set -e

echo "🚀 Launching EchoPanel for Testing..."
echo "================================"

# Build the app first
echo "📦 Building EchoPanel..."
cd "$(dirname "$0")/.."
swift build

# Launch the app
echo "🎯 Launching EchoPanel.app..."
if [ -d "dist/EchoPanel.app" ]; then
    open "dist/EchoPanel.app"
    echo "✅ EchoPanel launched!"
else
    echo "❌ EchoPanel.app not found. Building first..."
    swift run
fi

echo ""
echo "📊 Ready for manual testing!"
echo "Open Activity Monitor to track memory/CPU usage"
echo "================================"