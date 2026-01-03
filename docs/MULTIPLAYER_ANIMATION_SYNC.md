# Multiplayer Animation Sync Architecture

## The Problem

On dedicated servers running with `--server` flag (headless mode), we delete all sprite nodes to save memory - the server doesn't need to render anything. However, **animations still need to be synced to clients**.

The original bug: `NetworkEnemyManager._get_enemy_animation()` tried to read the animation from the sprite node:
```gdscript
# OLD (BROKEN on dedicated server):
func _get_enemy_animation(enemy: Node) -> String:
    var sprite = enemy.get_node_or_null("Sprite")
    if sprite and sprite is AnimatedSprite2D:
        return sprite.animation  # Returns null on server - sprite was deleted!
    return "idle_down"  # Fallback - ALL enemies sent as "idle_down"
```

Result: All enemies appeared frozen on clients, stuck in `idle_down` animation.

## The Solution

Track animation state as a **variable** instead of reading from the sprite node.

### Key Components

#### 1. Enemy.gd / Wolf.gd / Spider.gd
```gdscript
# Animation state tracked as variable (works without sprites)
var current_animation: String = "idle_down"
```

#### 2. EnemyAI.gd - `update_enemy_animation()`
Calculate and set `current_animation` FIRST, before trying to play on sprites:
```gdscript
func update_enemy_animation(velocity: Vector2) -> void:
    # Calculate animation name based on velocity
    var anim_name = "walk_down"  # (simplified - actual logic uses direction)

    # ALWAYS set this - works on headless server without sprites
    enemy.current_animation = anim_name

    # Then optionally play on sprite if it exists (client-side only)
    if anim_sprite:
        anim_sprite.play(anim_name)
```

#### 3. NetworkEnemyManager.gd - `_get_enemy_animation()`
Read from the variable, not the sprite:
```gdscript
func _get_enemy_animation(enemy: Node) -> String:
    # Use tracked animation state (works on headless server)
    if "current_animation" in enemy:
        return enemy.current_animation

    # Fallback for backwards compatibility
    var sprite = enemy.get_node_or_null("Sprite")
    if sprite and sprite is AnimatedSprite2D:
        return sprite.animation
    return "idle_down"
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      DEDICATED SERVER                            │
│  (--server flag, headless, no sprites)                          │
│                                                                  │
│  EnemyAI._physics_process()                                     │
│       │                                                          │
│       ▼                                                          │
│  update_enemy_animation(velocity)                               │
│       │                                                          │
│       ├──► Calculate anim_name from velocity/state              │
│       │                                                          │
│       └──► enemy.current_animation = anim_name  ◄── KEY STEP    │
│                                                                  │
│  NetworkEnemyManager._sync_enemy_positions()                    │
│       │                                                          │
│       ▼                                                          │
│  _get_enemy_animation(enemy)                                    │
│       │                                                          │
│       └──► return enemy.current_animation                       │
│                                                                  │
│       │                                                          │
│       ▼                                                          │
│  RPC to clients: { pos: Vector2, anim: "walk_left", ... }       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT                                   │
│  (has sprites, renders animations)                              │
│                                                                  │
│  NetworkEnemyManager._client_sync_positions()                   │
│       │                                                          │
│       ▼                                                          │
│  var sprite = enemy.get_node_or_null("Sprite")                  │
│  sprite.play(data.anim)  ──► Plays "walk_left" animation        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Enemy Types Using This Pattern

| Enemy Type | File | Notes |
|------------|------|-------|
| Skeleton | `Enemy.gd` | Uses EnemyAI for animation updates |
| Wolf | `Wolf.gd` | Has own animation system, sets `current_animation` in `update_animation_for_direction()` |
| Spider | `Spider.gd` | Has own animation system, sets `current_animation` in `play_animation()` |

## Adding New Enemy Types

When creating a new enemy type that needs multiplayer animation sync:

1. Add `var current_animation: String = "idle_down"` to the enemy script
2. In every function that changes the animation, set `current_animation` BEFORE playing on the sprite
3. The animation name should match what clients expect (e.g., `walk_up`, `attack_left`, `idle_down`)

Example:
```gdscript
func update_animation(direction: Vector2) -> void:
    var anim_name = "walk_" + get_direction_string(direction)

    # Always set for server sync (even if no sprite)
    current_animation = anim_name

    # Play on sprite if available (client-side)
    if sprite:
        sprite.play(anim_name)
```

## Debugging Animation Sync Issues

If enemies appear frozen on clients:

1. **Check server logs** - Is EnemyAI running? (Should see state changes, pathfinding, etc.)
2. **Check `current_animation` is being set** - Add temporary logging in `update_enemy_animation()`
3. **Check NetworkEnemyManager sync** - Verify `_get_enemy_animation()` returns correct value
4. **Check client receives data** - Log incoming `data.anim` in `_client_sync_positions()`

Common issues:
- Server running in client mode (check for `--server` in cmdline args)
- Animation name mismatch between server and client sprite definitions
- EnemyAI not running (check multiplayer authority conditions)
