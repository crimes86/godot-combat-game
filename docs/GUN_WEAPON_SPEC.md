# Gun Weapon System - Design Specification

## Overview

Guns are precision ranged weapons that use cursor-based targeting with a small circular reticle. Unlike melee cone attacks or large healing circles, guns reward precise aiming with a tight targeting radius.

---

## Visual Targeting System

### Reticle Visualizer

**Similar to:** Healing staff circle visualizer
**Different from:** Melee cone visualizer

| Property | Healing Staff | Gun Reticle |
|----------|---------------|-------------|
| Shape | Circle (Polygon2D) | Circle (Polygon2D) |
| Radius | 80px (heal_radius) | 24-32px (precision) |
| Color | Green (0.4, 1.0, 0.5, 0.04) | Red/Orange (1.0, 0.3, 0.2, 0.08) |
| Position | Follows cursor | Follows cursor |
| Parent | Scene root (world space) | Scene root (world space) |

**Radius Rationale:**
- Player sprite frame: 64x64px
- Player hitbox: ~32px diameter (centered)
- Gun reticle: 24-32px radius = 48-64px diameter
- This means the reticle roughly covers one player/enemy sprite with slight forgiveness

### Reticle Appearance

```
Design Options (in order of preference):

1. Simple Circle (like healing but smaller + different color)
   - Red/orange fill at 8% opacity
   - Consistent with existing visual language

2. Crosshair Circle (more "gun-like")
   - Small circle with cross lines through center
   - More tactical feel

3. Dot with Ring
   - Center dot for precision
   - Outer ring shows hit radius
```

**Recommendation:** Start with Option 1 (simple circle) for consistency, iterate later if needed.

---

## Target Detection

### On Click Detection

```gdscript
func get_enemies_in_gun_radius(center_pos: Vector2, radius: float) -> Array:
    """Get all enemies within gun targeting circle"""
    var enemies_in_radius = []
    var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

    for enemy in enemies:
        if not is_instance_valid(enemy):
            continue

        var distance = center_pos.distance_to(enemy.global_position)
        if distance <= radius:
            enemies_in_radius.append(enemy)

    return enemies_in_radius
```

**Key Difference from Melee:**
- Melee: Cone from player position, direction-based
- Gun: Circle at cursor position, position-based

**Key Difference from Healing:**
- Healing: Detects allies (GROUP_PLAYER)
- Gun: Detects enemies (GROUP_ENEMIES)

---

## Damage System

### Damage Flow (Mirrors Melee)

```
Player clicks with gun equipped
         │
         ▼
┌─────────────────────────────┐
│ get_enemies_in_gun_radius() │
│ (cursor pos, gun_radius)    │
└─────────────────────────────┘
         │
         ▼
    For each enemy:
         │
         ▼
┌─────────────────────────────┐
│ CritSystem.roll_for_crit()  │
│ (same pity system as melee) │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Calculate final_damage      │
│ = base_damage * crit_mult   │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ apply_damage_with_feedback()│
│ (damage numbers, particles) │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ If crit: start_crit_window()│
│ (same crit window system)   │
└─────────────────────────────┘
```

### Shared Systems (No Changes Needed)

- `CritSystem` - Same crit rolling and pity system
- `CritWindowManager` - Same crit window on crit hits
- `apply_damage_with_feedback()` - Same damage numbers and particles
- `CharacterStats` - Same stat bonuses apply

### Gun-Specific Properties

```gdscript
# In Weapon.gd resource
@export var gun_radius: float = 28.0  # Targeting circle radius (pixels)
@export var gun_range: float = 400.0  # Max distance from player (optional, for balance)
```

---

## Attack Execution

### attempt_gun_attack() Function

```gdscript
func attempt_gun_attack() -> void:
    """Attempt to shoot enemies at cursor position with gun."""
    if not can_attack:
        return

    # Verify gun weapon equipped
    var weapon = CharacterStats.equipped_weapon
    if not weapon or weapon.attack_mode != "ranged_damage":
        return

    can_attack = false

    var cursor_pos = get_global_mouse_position()
    var gun_radius = weapon.gun_radius if weapon.get("gun_radius") else 28.0

    # Optional: Enforce max range from player
    var gun_range = weapon.gun_range if weapon.get("gun_range") else 400.0
    var distance_to_cursor = global_position.distance_to(cursor_pos)
    if distance_to_cursor > gun_range:
        # Clamp cursor position to max range
        var direction = (cursor_pos - global_position).normalized()
        cursor_pos = global_position + direction * gun_range

    # Get enemies in targeting circle
    var enemies = get_enemies_in_gun_radius(cursor_pos, gun_radius)

    # Face toward cursor
    attack_direction = (cursor_pos - global_position).normalized()

    # Play gun animation (thrust or custom gun anim)
    var character_sprite = get_node_or_null("CharacterSprite")
    if character_sprite:
        var dir_str = get_direction_string(attack_direction)
        var lpc_dir = convert_to_lpc_direction(dir_str)
        # Use thrust animation for gun (single-frame "aim" feel)
        character_sprite.play_lpc_animation("thrust", lpc_dir)

    # Spawn muzzle flash at player position
    _spawn_muzzle_flash()

    # Spawn bullet trail from player to cursor
    _spawn_bullet_trail(global_position, cursor_pos)

    # Play gunshot sound
    var sound_manager = get_node_or_null("/root/SoundManager")
    if sound_manager:
        sound_manager.play_gunshot_sound(global_position, -6.0)

    # Apply damage to all enemies in radius
    if enemies.size() > 0:
        attack_enemies_at_cursor(enemies)
    else:
        # Miss feedback (optional)
        _spawn_miss_indicator(cursor_pos)

    finish_attack_cooldown()
```

### attack_enemies_at_cursor() Function

```gdscript
func attack_enemies_at_cursor(enemies: Array) -> void:
    """Deal damage to enemies at gun cursor - mirrors attack_enemies_in_cone()"""
    for enemy in enemies:
        if not is_instance_valid(enemy):
            continue

        # Roll for crit (same system as melee)
        var is_crit = false
        var final_damage = attack_damage

        if crit_system and crit_system.has_method("roll_for_crit"):
            is_crit = crit_system.roll_for_crit()

            if is_crit:
                var crit_mult = crit_system.get_crit_multiplier()
                final_damage *= crit_mult

                # Crit sound
                var sound_manager = get_node_or_null("/root/SoundManager")
                if sound_manager:
                    sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -8.0)

                # Start crit window (same as melee)
                if crit_window_manager:
                    crit_window_manager.start_window(enemy)

        # Apply damage with feedback (same as melee)
        apply_damage_with_feedback(enemy, final_damage, is_crit, false)
```

---

## Visual Effects

### Muzzle Flash

```gdscript
func _spawn_muzzle_flash() -> void:
    """Spawn muzzle flash particle effect at gun position"""
    # Position at player + offset toward aim direction
    var flash_offset = attack_direction * 20  # 20px in front of player
    var flash_pos = global_position + flash_offset

    # Use existing particle system or create simple flash
    var flash = preload("res://scenes/effects/muzzle_flash.tscn").instantiate()
    flash.global_position = flash_pos
    flash.rotation = attack_direction.angle()
    get_tree().root.add_child(flash)
```

### Bullet Trail

```gdscript
func _spawn_bullet_trail(from: Vector2, to: Vector2) -> void:
    """Spawn bullet trail line from gun to target"""
    var trail = Line2D.new()
    trail.width = 2.0
    trail.default_color = Color(1.0, 0.9, 0.3, 0.8)  # Yellow-white
    trail.add_point(from)
    trail.add_point(to)
    trail.z_index = 10
    get_tree().root.add_child(trail)

    # Fade out and remove
    var tween = create_tween()
    tween.tween_property(trail, "modulate:a", 0.0, 0.15)
    tween.tween_callback(trail.queue_free)
```

### Hit Impact (at cursor on enemy hit)

```gdscript
# Reuse existing attack_feedback.trigger_attack_feedback()
# This already spawns blood/spark particles
```

### Miss Indicator (optional)

```gdscript
func _spawn_miss_indicator(pos: Vector2) -> void:
    """Small dust puff or spark when shot hits nothing"""
    # Simple particle burst or small sprite
    pass
```

---

## Sound Effects

### Required Sounds

| Sound | File | Notes |
|-------|------|-------|
| Gunshot | `gunshot.wav` | Sharp crack, not too loud |
| Gunshot Crit | `gunshot_crit.wav` | Beefier version (optional) |
| Bullet Impact | Reuse hit sounds | Same as melee hits |
| Empty/Reload | Future feature | For ammo system if added |

### SoundManager Addition

```gdscript
func play_gunshot_sound(position: Vector2, volume_db: float = -6.0) -> void:
    # Similar to play_sword_swing_sound but for guns
    pass
```

---

## Weapon Resource Configuration

### Example Gun Weapon

```gdscript
# res://resources/weapons/forged/skorpio_pistol.tres
[resource]
script = preload("res://scripts/resources/Weapon.gd")

weapon_name = "Skorpio Pistol"
weapon_type = "gun"
damage_type = "pierce"  # For crit window mechanics
attack_mode = "ranged_damage"

base_damage = 12.0
attack_speed_bonus = 0.1  # Slightly faster than melee
crit_chance_bonus = 0.05  # Guns reward precision

gun_radius = 28.0  # Targeting circle radius
gun_range = 350.0  # Max shooting distance
```

---

## Integration Points

### Player.gd Changes

1. Add `gun_visualizer` similar to `circle_visualizer`
2. Add `create_gun_visualizer()` function
3. Add `update_gun_visualizer()` in `_physics_process()`
4. Route to `attempt_gun_attack()` based on weapon type

### Weapon.gd Changes

1. Add `gun_radius: float = 28.0`
2. Add `gun_range: float = 400.0`
3. Add `is_gun_weapon() -> bool` helper

```gdscript
func is_gun_weapon() -> bool:
    return weapon_type == "gun" or attack_mode == "ranged_damage"
```

### PlayerCombat.gd Changes

1. Add `get_enemies_in_gun_radius()` function
2. Add `attempt_gun_attack()` function
3. Add `attack_enemies_at_cursor()` function
4. Update `process_held_attack()` to route guns correctly

---

## Attack Flow Comparison

| Aspect | Melee | Healing Staff | Gun |
|--------|-------|---------------|-----|
| Visualizer | Cone from player | Circle at cursor | Small circle at cursor |
| Detection | Cone (dist + angle) | Circle (dist from cursor) | Circle (dist from cursor) |
| Targets | Enemies in cone | Allies in circle | Enemies in circle |
| Effect | Damage + crit window | Heal + visual | Damage + crit window |
| Animation | slash | slash (cast) | thrust |
| VFX | Swing arc | Heal pulse | Muzzle flash + bullet trail |

---

## Cooldown & Attack Speed

Guns use the **same cooldown system** as melee:

```gdscript
func finish_attack_cooldown() -> void:
    # Same for all weapons
    var cooldown = base_attack_cooldown
    if CharacterStats.equipped_weapon:
        cooldown -= CharacterStats.equipped_weapon.attack_speed_bonus
    cooldown = max(cooldown, 0.2)  # Minimum cooldown

    await get_tree().create_timer(cooldown).timeout
    can_attack = true
```

**Tuning Suggestions:**
- Base gun cooldown: Same as melee (consistency)
- Gun attack_speed_bonus: +0.1 to +0.2 (slightly faster fire rate)
- Can be tuned per-weapon via resource

---

## Future Considerations (Out of Scope)

These are NOT part of initial implementation:

- Ammo/reload system
- Bullet drop/travel time
- Penetration (hitting multiple enemies in a line)
- Different gun types (pistol, rifle, shotgun spread)
- Zoom/scope mechanics

---

## Implementation Checklist

### Phase 1: Core Functionality
- [ ] Add gun_radius, gun_range to Weapon.gd
- [ ] Add is_gun_weapon() helper
- [ ] Create gun reticle visualizer (small red circle)
- [ ] Add get_enemies_in_gun_radius() detection
- [ ] Add attempt_gun_attack() function
- [ ] Route gun weapons in process_held_attack()
- [ ] Test basic click-to-damage

### Phase 2: Visual Polish
- [ ] Muzzle flash effect
- [ ] Bullet trail effect
- [ ] Gunshot sound effect
- [ ] Miss indicator (optional)

### Phase 3: Integration
- [ ] Verify crit system works with gun
- [ ] Verify crit window triggers on gun crits
- [ ] Test damage numbers display correctly
- [ ] Test with Skorpio body swap (already implemented)

---

## Version History

- v1.0 (2024-12) - Initial specification
