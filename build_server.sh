#!/bin/bash
# Server export script - swaps project file temporarily
set -e
cd /opt/ashbane-game/source

echo "🔧 Swapping to server project config..."
cp project.godot project.godot.client.bak
cp project.server.godot project.godot

echo "📦 Exporting server build..."
/usr/local/bin/godot45 --headless --export-release "Linux Server" /opt/ashbane-game/server/ashbane-server.x86_64

echo "🔄 Restoring client project config..."
mv project.godot.client.bak project.godot

echo "✅ Server exported successfully!"
