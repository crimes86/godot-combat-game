#!/bin/bash
# Restore client project settings (run after pull if needed)
cd /opt/ashbane-game/source

if [ -f project.godot.client ]; then
    cp project.godot.client project.godot
    echo "✅ Restored client project.godot"
else
    echo "⚠️ project.godot.client not found - project.godot should already be client version"
fi
