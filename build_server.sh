#!/bin/bash
# build_server.sh - Build dedicated server with UI autoloads removed

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "=== Building Dedicated Server ==="

# Backup original project.godot
cp project.godot project.godot.backup

# Use server-specific project file
cp project.server.godot project.godot

# Export the server build
echo "Exporting Linux Server..."
/usr/local/bin/godot --headless --export-release "Linux Server" builds/server/ashbane-server.x86_64

# Restore original project.godot
mv project.godot.backup project.godot

echo "=== Server build complete: builds/server/ashbane-server.x86_64 ==="
