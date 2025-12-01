# F3 Debug System

## Overview

Press **F3** to toggle all debug displays on/off. This provides a unified way to show/hide debugging information during gameplay.

## What F3 Toggles

### 1. Performance Profiler (Left Side)
Shows:
- **FPS**: Frames per second
- **Frame Time**: Milliseconds per frame
- **Total Nodes**: All nodes in scene tree
- **Enemies**: Active enemy count
- **Particles**: Active particle count
- **Polygons**: Polygon2D count
- **Memory**: RAM usage

Location: Top-left corner

### 2. Chunk & Enemy Debug (Integrated in Profiler)
Shows:
- **Current Chunk**: Grid coordinates (e.g., "-1,0") with X position
- **Distance to Edges**: West/East edge distances (⚠️ if < 1000px)
- **Loaded Chunks**: List of currently loaded chunks
- **Enemies Per Chunk**: Count vs target (e.g., "[-1,0]: 58/60")
- **Total Enemies**: Sum of all active enemies

Location: Integrated in the left-side profiler display

### 3. Player Sprite Debugging
Shows:
- Player hitboxes
- Movement vectors
- Attack ranges
- Other player-specific debug visuals

### 4. Enemy Debugging
Shows:
- Enemy AI states
- Attack ranges
- Pathfinding
- Other enemy-specific debug visuals

## How It Works

### Constants Autoload (Debug System)

The `Constants.gd` autoload handles debug toggling (merged from DebugConfig):

```gdscript
# In Constants.gd
signal debug_display_toggled(visible: bool)

func _input(event: InputEvent) -> void:
    # Only allow in editor or debug builds
    if not (OS.has_feature("editor") or OS.is_debug_build()):
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
        toggle_debug_display()

func toggle_debug_display() -> void:
    debug_display_visible = !debug_display_visible
    debug_display_toggled.emit(debug_display_visible)
```

### Systems Connect to Signal

Each debug system connects to the `debug_display_toggled` signal:

```gdscript
# In PerformanceProfiler.gd
func _ready() -> void:
    visible = false  # Hidden by default
    if Constants:
        Constants.debug_display_toggled.connect(_on_debug_toggled)

func _on_debug_toggled(is_visible: bool) -> void:
    visible = is_visible
```

```gdscript
# In ChunkBasedPropSystem.gd
func _ready() -> void:
    create_debug_label()  # Creates but hides by default
    if Constants:
        Constants.debug_display_toggled.connect(_on_debug_toggled)

func _on_debug_toggled(is_visible: bool) -> void:
    if debug_canvas:
        debug_canvas.visible = is_visible
```

## Default State

**All debug displays are HIDDEN by default**

- Game starts with clean UI
- Press F3 to reveal debug info
- Press F3 again to hide

## Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ FPS: 60 (16.6 ms/frame)                                          │
│ ━━━━━━━━━━━━━━━━━━━━━━                                           │
│ SCENE:                                                           │
│   Total Nodes: 1800                                              │
│   Enemies: 118                                                   │
│   Campfires: 1                                                   │
│ ━━━━━━━━━━━━━━━━━━━━━━                                           │
│ RENDERING:                                                       │
│   Sprites: 450                                                   │
│   Polygons: 320                                                  │
│   Particles: 80 (active)                                         │
│   Lights: 12                                                     │
│ ━━━━━━━━━━━━━━━━━━━━━━                                           │
│ MEMORY:                                                          │
│   Usage: 128.5 MB                                                │
│ ━━━━━━━━━━━━━━━━━━━━━━                                           │
│ CHUNKS:                                                          │
│   Current: [-1,0] X=-2000                                        │
│   West Edge: 1000px                                              │
│   East Edge: 2000px                                              │
│   Loaded: [-1,0, 0,0]                                           │
│ ━━━━━━━━━━━━━━━━━━━━━━                                           │
│ ENEMIES PER CHUNK:                                               │
│   [-1,0]: 58/60                                                  │
│   [0,0]: 60/60                                                   │
│   Total: 118 enemies                                             │
│ ━━━━━━━━━━━━━━━━━━━━━━                                           │
│ Press F3 to toggle                                               │
└──────────────────────────────────────────────────────────────────┘
```

## Benefits

### For Development
- Quick toggle to check performance
- See chunk loading in real-time
- Monitor memory usage
- Debug specific systems as needed

### For Players
- Clean UI by default (no clutter)
- Optional performance monitoring
- Easy to disable when not needed

### For Debugging
- All debug info in one keypress
- Consistent toggle behavior
- No need to hunt through settings

## Adding New Debug Systems

To add a new system to F3 toggle:

1. **Create your debug display** (hidden by default)
```gdscript
func _ready() -> void:
    my_debug_ui = create_debug_ui()
    my_debug_ui.visible = false
```

2. **Connect to Constants debug signal**
```gdscript
    if Constants:
        Constants.debug_display_toggled.connect(_on_debug_toggled)
```

3. **Handle toggle**
```gdscript
func _on_debug_toggled(is_visible: bool) -> void:
    my_debug_ui.visible = is_visible
```

That's it! Your system now toggles with F3.

## Production Builds

For production/release builds:

1. **F3 is automatically disabled** in release builds
   - The `_input()` handler checks `OS.has_feature("editor") or OS.is_debug_build()`
   - Only works in editor or debug exports

2. **Option**: Disable debug entirely
   ```gdscript
   # In Constants.gd
   @export var ENABLE_DEBUG: bool = false
   ```

3. **Option**: Keep but hide
   - Leave F3 toggle functional for bug reports
   - Players can enable if they want performance stats

## Visual Debug Overlays

When F3 is enabled, the PerformanceProfiler also draws:
- **Chunk boundary lines**: Vertical magenta lines at each chunk edge
- **Chunk labels**: "Chunk X,0" labels at the top of each boundary

These help visualize chunk boundaries while testing.

## Files

- `scripts/constants.gd` - Central F3 toggle handler (debug system merged into Constants)
- `scripts/debug/PerformanceProfiler.gd` - Performance stats, chunk info, enemy counts, visual overlays
- `docs/F3_DEBUG_SYSTEM.md` - This documentation
