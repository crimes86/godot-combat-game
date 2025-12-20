# Minimap System Specification

> **Status**: Approved for implementation
> **Created**: 2024-12-17
> **Decisions**: Circular, hover-zoom, full map overlay, fog of war, detected enemies only

---

## Overview

A circular minimap in the upper-right corner showing player position, detected enemies, POIs, and explored terrain. Includes a full-screen map overlay for strategic viewing.

---

## 1. Design Decisions

| Question | Decision |
|----------|----------|
| Shape | **Circular** (classic RPG style) |
| Zoom Control | **Mouse wheel when hovering** over minimap |
| Full Map | **Yes** - Shows Zone 1 (3 origin chunks) + Zone 2 handoff |
| Fog of War | **Yes** - Unexplored areas hidden |
| Enemy Visibility | **Detected only** - Enemies that have aggro'd or been hit |

---

## 2. UI Layout

### Minimap (Always Visible)
```
┌─────────────────────────────────────────────────────────┐
│                                              ╭────╮     │
│                                              │ ◯  │     │  <- Circular minimap
│                                              │    │     │     200-256px diameter
│                                              ╰────╯     │
│                                          ┌──────────┐   │
│                                          │  QUEST   │   │
│           GAME WORLD                     │ TRACKER  │   │
│                                          │          │   │
│                                          └──────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Full Map Overlay (M key or click minimap)
```
┌─────────────────────────────────────────────────────────┐
│  ╔═══════════════════════════════════════════════════╗  │
│  ║                    ZONE 1 MAP                     ║  │
│  ║  ┌─────────┬─────────┬─────────┐                  ║  │
│  ║  │ Chunk-1 │ Chunk 0 │ Chunk 1 │ → Zone 2         ║  │
│  ║  │         │    ⚑    │         │                  ║  │
│  ║  │         │ (camp)  │         │                  ║  │
│  ║  └─────────┴─────────┴─────────┘                  ║  │
│  ║                                                   ║  │
│  ║  [Legend: ⚑ Campfire  ⚒ Forge  🌳 World Tree]    ║  │
│  ╚═══════════════════════════════════════════════════╝  │
└─────────────────────────────────────────────────────────┘
```

---

## 3. Minimap Specifications

### Dimensions & Position
```gdscript
const MINIMAP_DIAMETER = 220  # pixels
const MINIMAP_MARGIN = 15     # from screen edge
const MINIMAP_POSITION = Vector2(-MINIMAP_DIAMETER - MINIMAP_MARGIN, MINIMAP_MARGIN)  # Top-right anchor

# Position above quest tracker (QuestTracker starts at y=80)
# Minimap: y=15, height=220, ends at y=235
# Quest tracker: y=250 (with 15px gap)
```

### Visual Style (Ashbane Theme)
```gdscript
# Colors matching Ashbane medieval theme
const MINIMAP_BG = Color(0.06, 0.05, 0.04, 0.9)           # Dark parchment
const MINIMAP_BORDER = Color(0.45, 0.35, 0.25, 1.0)       # Bronze frame
const MINIMAP_BORDER_INNER = Color(0.3, 0.22, 0.15, 1.0)  # Dark bronze
const MINIMAP_GLOW = Color(0.7, 0.15, 0.1, 0.2)           # Subtle crimson glow

# Fog of war
const FOG_UNEXPLORED = Color(0.02, 0.02, 0.02, 0.95)      # Near black
const FOG_EXPLORED = Color(0.0, 0.0, 0.0, 0.0)            # Transparent
```

### Zoom Levels
```gdscript
const ZOOM_LEVELS = [
    {"radius": 6000.0,  "name": "Close"},    # ~0.75 chunk, combat focus
    {"radius": 12000.0, "name": "Normal"},   # ~1.5 chunks, default
    {"radius": 24000.0, "name": "Far"},      # ~3 chunks, strategic
]
var current_zoom_index = 1  # Start at Normal
```

---

## 4. Marker System

### Player Marker
```gdscript
# Always centered, rotates with player direction
const PLAYER_MARKER_SIZE = Vector2(14, 14)
const PLAYER_MARKER_COLOR = Color(1.0, 1.0, 1.0, 1.0)      # White
const PLAYER_MARKER_GLOW = Color(0.7, 0.15, 0.1, 0.6)      # Crimson glow

# Arrow/chevron shape pointing in movement direction
# Rotation: player.velocity.angle() or last_facing_direction
```

### Other Players (Multiplayer)
```gdscript
const OTHER_PLAYER_SIZE = Vector2(10, 10)
const OTHER_PLAYER_COLOR = Color(0.3, 0.8, 0.4, 1.0)       # Green (friendly)
const PARTY_MEMBER_COLOR = Color(0.3, 0.5, 0.9, 1.0)       # Blue (party)
```

### Detected Enemies
```gdscript
# Only show enemies that:
# 1. Have aggro'd on player (target_player != null)
# 2. Have been damaged by player (took damage recently)
# 3. Are within detection range AND player has line of sight

const ENEMY_MARKER_SIZE = Vector2(6, 6)
const ENEMY_COLORS = {
    "normal": Color(0.9, 0.2, 0.2, 0.9),      # Red
    "elite": Color(1.0, 0.5, 0.0, 0.9),       # Orange (guardians)
    "boss": Color(0.8, 0.0, 0.8, 0.9),        # Purple (future)
}

# Fade out enemies that lose detection after 5 seconds
const ENEMY_FADE_TIME = 5.0
```

### Points of Interest
```gdscript
const POI_MARKERS = {
    "campfire": {
        "icon": "res://assets/ui/minimap/icon_campfire.png",
        "color": Color(1.0, 0.6, 0.2, 1.0),   # Orange
        "size": Vector2(16, 16),
        "always_visible": true,               # Show even in fog
    },
    "forge": {
        "icon": "res://assets/ui/minimap/icon_forge.png",
        "color": Color(0.9, 0.75, 0.3, 1.0),  # Gold
        "size": Vector2(14, 14),
        "always_visible": true,
    },
    "vendor": {
        "icon": "res://assets/ui/minimap/icon_npc.png",
        "color": Color(0.9, 0.85, 0.4, 1.0),  # Yellow
        "size": Vector2(12, 12),
        "always_visible": true,
    },
    "world_tree": {
        "icon": "res://assets/ui/minimap/icon_tree.png",
        "color": Color(0.3, 0.8, 0.3, 1.0),   # Green
        "size": Vector2(18, 18),
        "always_visible": true,
    },
    "seed_plot_unclaimed": {
        "icon": "res://assets/ui/minimap/icon_seed_empty.png",
        "color": Color(0.5, 0.5, 0.5, 0.7),   # Gray
        "size": Vector2(12, 12),
        "always_visible": false,
    },
    "seed_plot_claimed": {
        "icon": "res://assets/ui/minimap/icon_seed_claimed.png",
        "color": null,                         # Use faction color
        "size": Vector2(14, 14),
        "always_visible": false,
    },
    "zone_exit": {
        "icon": "res://assets/ui/minimap/icon_exit.png",
        "color": Color(0.6, 0.4, 0.8, 1.0),   # Purple
        "size": Vector2(14, 14),
        "always_visible": true,
    },
    "ruins": {
        "icon": "res://assets/ui/minimap/icon_ruins.png",
        "color": Color(0.4, 0.7, 0.8, 0.8),   # Cyan
        "size": Vector2(10, 10),
        "always_visible": false,              # Only when explored
    },
}
```

### Hazards
```gdscript
const HAZARD_MARKERS = {
    "lava": {
        "color": Color(0.8, 0.2, 0.1, 0.6),   # Red, semi-transparent
        "render_as": "area",                   # Filled region, not icon
    },
}
```

---

## 5. Fog of War System

### Exploration Tracking
```gdscript
# Grid-based fog of war
const FOG_CELL_SIZE = 500.0  # World units per fog cell
const REVEAL_RADIUS = 800.0  # How far player reveals (sight range)

# Stored as dictionary of revealed cells
var revealed_cells: Dictionary = {}  # Vector2i -> bool

# Persistence: Save/load with player data
func save_fog_data() -> Dictionary:
    return {"revealed": revealed_cells.keys()}

func load_fog_data(data: Dictionary):
    for cell in data.get("revealed", []):
        revealed_cells[cell] = true
```

### Rendering Fog
```gdscript
# Use shader or texture mask approach
# Option 1: Pre-rendered fog texture updated on reveal
# Option 2: Shader with revealed_cells uniform

# Shader approach (recommended):
shader_type canvas_item;

uniform sampler2D fog_mask;  # R channel = revealed (0=hidden, 1=visible)
uniform vec4 fog_color = vec4(0.02, 0.02, 0.02, 0.95);

void fragment() {
    vec4 map_color = texture(TEXTURE, UV);
    float revealed = texture(fog_mask, UV).r;
    COLOR = mix(fog_color, map_color, revealed);
}
```

### Reveal Events
```gdscript
# Reveal fog as player moves
func _on_player_moved(new_position: Vector2):
    var cell = Vector2i(
        int(new_position.x / FOG_CELL_SIZE),
        int(new_position.y / FOG_CELL_SIZE)
    )

    # Reveal cells in radius
    var cells_to_reveal = _get_cells_in_radius(cell, REVEAL_RADIUS / FOG_CELL_SIZE)
    for c in cells_to_reveal:
        if not revealed_cells.has(c):
            revealed_cells[c] = true
            _update_fog_texture(c)
```

---

## 6. Mouse Wheel Zoom Integration

### Hover Detection
```gdscript
# In Minimap.gd
var is_mouse_over: bool = false

func _ready():
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered():
    is_mouse_over = true

func _on_mouse_exited():
    is_mouse_over = false

func _input(event):
    if is_mouse_over and event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            _zoom_in()
            get_viewport().set_input_as_handled()  # Prevent camera zoom
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            _zoom_out()
            get_viewport().set_input_as_handled()

func _zoom_in():
    current_zoom_index = max(0, current_zoom_index - 1)
    _update_zoom()

func _zoom_out():
    current_zoom_index = min(ZOOM_LEVELS.size() - 1, current_zoom_index + 1)
    _update_zoom()

func _update_zoom():
    view_radius = ZOOM_LEVELS[current_zoom_index].radius
    # Animate zoom transition
    var tween = create_tween()
    tween.tween_property(self, "current_view_radius", view_radius, 0.2)
```

### Camera Zoom Modification
```gdscript
# In Player.gd or camera controller - check if minimap has focus
func _input(event):
    if event is InputEventMouseButton:
        if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            # Check if minimap is handling this
            var minimap = get_node_or_null("/root/GameWorld/UI/Minimap")
            if minimap and minimap.is_mouse_over:
                return  # Let minimap handle it
            # Otherwise do camera zoom
            _handle_camera_zoom(event)
```

---

## 7. Full Map Overlay

### Activation
```gdscript
# Toggle with M key or click on minimap
func _input(event):
    if event.is_action_pressed("toggle_map"):  # Map to M key
        _toggle_full_map()

    # Click on minimap opens full map
    if is_mouse_over and event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            _toggle_full_map()

func _toggle_full_map():
    full_map_visible = not full_map_visible
    $FullMapOverlay.visible = full_map_visible

    # Pause game while map is open (optional)
    # get_tree().paused = full_map_visible
```

### Full Map Layout
```gdscript
# Shows all of Zone 1 (chunks -1, 0, 1) plus Zone 2 indicator
const FULL_MAP_SIZE = Vector2(800, 500)  # Screen size
const FULL_MAP_WORLD_BOUNDS = Rect2(-12000, -4000, 32000, 8000)  # 3 chunks + buffer

# Zone 2 shown as grayed out region to the right with "Zone 2" label
# and arrow indicating transition point
```

### Full Map Features
- **Pan**: Click and drag to pan around
- **Zoom**: Mouse wheel to zoom in/out (independent of minimap zoom)
- **Markers**: All POIs visible (including undiscovered in fog)
- **Player Position**: Highlighted with pulsing marker
- **Chunk Grid**: Visible lines showing chunk boundaries
- **Zone Labels**: "Zone 1 - The Dreadlands", "Zone 2 - ???"
- **Legend**: Bottom of screen showing marker meanings
- **Close**: ESC key or click X button or click outside

---

## 8. Enemy Detection System

### Detection Criteria
```gdscript
# Enemy is "detected" and shown on minimap when ANY of:
# 1. Enemy has player as target (aggro'd)
# 2. Enemy took damage from player in last 10 seconds
# 3. Player is within enemy's detection range AND has line of sight

func is_enemy_detected(enemy: Node2D) -> bool:
    # Check aggro
    if enemy.has_method("get_target") and enemy.get_target() == local_player:
        return true

    # Check recent damage (would need to track this on enemy)
    if enemy.has_meta("last_damage_time"):
        var time_since_damage = Time.get_ticks_msec() / 1000.0 - enemy.get_meta("last_damage_time")
        if time_since_damage < 10.0:
            return true

    # Check detection range + line of sight
    var distance = local_player.global_position.distance_to(enemy.global_position)
    if distance < PLAYER_DETECTION_RANGE:
        # Simple LOS check (could use raycast for accuracy)
        return true

    return false

const PLAYER_DETECTION_RANGE = 600.0  # Player can "sense" enemies this close
```

### Detection Fade
```gdscript
# Track detected enemies and fade them out over time when no longer detected
var detected_enemies: Dictionary = {}  # enemy_id -> {enemy, last_seen_time, alpha}

func _update_enemy_detection():
    var current_time = Time.get_ticks_msec() / 1000.0

    for enemy in get_tree().get_nodes_in_group("enemies"):
        var id = enemy.get_instance_id()

        if is_enemy_detected(enemy):
            detected_enemies[id] = {
                "enemy": enemy,
                "last_seen": current_time,
                "alpha": 1.0
            }
        elif detected_enemies.has(id):
            # Fade out over ENEMY_FADE_TIME
            var time_since_seen = current_time - detected_enemies[id].last_seen
            if time_since_seen > ENEMY_FADE_TIME:
                detected_enemies.erase(id)
            else:
                detected_enemies[id].alpha = 1.0 - (time_since_seen / ENEMY_FADE_TIME)
```

---

## 9. File Structure

```
scripts/
└── ui/
    ├── Minimap.gd              # Main minimap controller
    ├── MinimapMarker.gd        # Individual marker component
    └── FullMapOverlay.gd       # Full screen map overlay

scenes/
└── ui/
    ├── Minimap.tscn            # Minimap scene
    ├── MinimapMarker.tscn      # Reusable marker prefab
    └── FullMapOverlay.tscn     # Full map overlay scene

assets/
└── ui/
    └── minimap/
        ├── minimap_frame.png       # Circular decorative border
        ├── minimap_mask.png        # Circular mask for clipping
        ├── icon_campfire.png       # 16x16 POI icons
        ├── icon_forge.png
        ├── icon_npc.png
        ├── icon_tree.png
        ├── icon_seed_empty.png
        ├── icon_seed_claimed.png
        ├── icon_exit.png
        ├── icon_ruins.png
        ├── player_arrow.png        # Player direction indicator
        └── enemy_dot.png           # Simple enemy marker

shaders/
└── minimap_fog.gdshader        # Fog of war shader
```

---

## 10. Implementation Phases

### Phase 1: Core Minimap (MVP)
- [ ] Create Minimap.tscn with CanvasLayer
- [ ] Circular mask and decorative frame
- [ ] Position above quest tracker
- [ ] Player marker (centered, rotating)
- [ ] World-to-minimap coordinate conversion
- [ ] Basic POI markers (campfire, vendors)

### Phase 2: Zoom & Interaction
- [ ] Three zoom levels
- [ ] Mouse wheel zoom when hovering
- [ ] Modify camera zoom to respect minimap hover
- [ ] Smooth zoom transitions

### Phase 3: Enemy Detection
- [ ] Detection criteria implementation
- [ ] Enemy markers with color coding
- [ ] Fade-out system for undetected enemies
- [ ] Track damaged enemies

### Phase 4: Fog of War
- [ ] Grid-based exploration tracking
- [ ] Fog shader/texture system
- [ ] Reveal on player movement
- [ ] Save/load fog state with player data

### Phase 5: Full Map Overlay
- [ ] Full map scene and toggle
- [ ] Pan and zoom controls
- [ ] Zone 1 complete view
- [ ] Zone 2 indicator
- [ ] Legend and labels

### Phase 6: Polish
- [ ] Decorative medieval frame
- [ ] Marker animations (pulse for quest targets)
- [ ] Edge fade for markers leaving view
- [ ] Sound effects for zoom/toggle
- [ ] Tooltip on hover over POIs

---

## 11. Input Mapping

Add to project input map:
```
toggle_map: M key
```

---

## 12. Performance Budget

| Operation | Target | Notes |
|-----------|--------|-------|
| Marker updates | 10 Hz | Every 0.1s |
| Fog updates | On move | Only when player moves 100+ units |
| Full redraw | 2 Hz | Background terrain |
| Max markers | 50 | Pool and reuse |
| Draw calls | < 20 | Batch markers |

---

## 13. Dependencies

- Quest tracker position may need adjustment (move down ~240px)
- Camera zoom input handling needs modification
- Player data save/load needs fog state
- Enemy scripts need `last_damage_time` tracking

---

## 14. Future Considerations

- **Zone 2+ Support**: Extend full map for additional zones
- **Waypoints**: Player-placed custom markers
- **Party Markers**: Show party member positions
- **Minimap Ping**: Click to ping location for party
- **Quest Objective Markers**: Show active quest targets
- **Dynamic POIs**: Temporary events, world bosses
