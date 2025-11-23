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

### 2. Chunk Debug Display (Right Side)
Shows:
- **Current Chunk**: Grid coordinates (e.g., "-1,0")
- **Position in Chunk**: XY within 2000×2000 square
- **Distance to Edge**: Pixels to nearest chunk boundary
- **Loaded Chunks**: How many chunks in memory
- **Loading Chunks**: Background chunk generation count
- **Total World Chunks**: Full world grid size

Location: Top-right corner

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

### DebugConfig Autoload

The `DebugConfig.gd` autoload acts as the central hub:

```gdscript
# In DebugConfig.gd
signal debug_display_toggled(visible: bool)

func _input(event: InputEvent) -> void:
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
    if DebugConfig:
        DebugConfig.debug_display_toggled.connect(_on_debug_toggled)

func _on_debug_toggled(is_visible: bool) -> void:
    visible = is_visible
```

```gdscript
# In ChunkBasedPropSystem.gd
func _ready() -> void:
    create_debug_label()  # Creates but hides by default
    if DebugConfig:
        DebugConfig.debug_display_toggled.connect(_on_debug_toggled)

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
│ PERFORMANCE PROFILER              CHUNK DEBUG                    │
│ FPS: 60                           Current Chunk: -1,0            │
│ Frame Time: 16.6ms                Position in Chunk: (850, 1200) │
│ Total Nodes: 3450                 Distance to Edge: 350px        │
│ Enemies: 5                        Loaded Chunks: 6               │
│ Particles: 120                    Loading Chunks: 2              │
│ Polygons: 850                     Total World Chunks: 27 (9x3)  │
│ Memory: 256 MB                                                   │
│                                                                   │
│                          [Game View]                             │
│                                                                   │
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

2. **Connect to DebugConfig signal**
```gdscript
    if DebugConfig:
        DebugConfig.debug_display_toggled.connect(_on_debug_toggled)
```

3. **Handle toggle**
```gdscript
func _on_debug_toggled(is_visible: bool) -> void:
    my_debug_ui.visible = is_visible
```

That's it! Your system now toggles with F3.

## Production Builds

For production/release builds:

1. **Option 1**: Remove debug systems entirely
   - Comment out debug display creation
   - Saves memory and CPU

2. **Option 2**: Disable DebugConfig
   ```gdscript
   # In DebugConfig.gd
   @export var ENABLE_DEBUG: bool = false
   ```

3. **Option 3**: Keep but hide
   - Leave F3 toggle functional for bug reports
   - Players can enable if they want performance stats

## Files Modified

- `scripts/systems/DebugConfig.gd` - Central F3 toggle handler
- `scripts/debug/PerformanceProfiler.gd` - Now hidden by default, F3 toggle
- `scripts/systems/ChunkBasedPropSystem.gd` - Chunk debug on right side, F3 toggle
- `docs/F3_DEBUG_SYSTEM.md` - This documentation
