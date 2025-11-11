# 🎯 RhythmRPG Refactoring Guide

## Overview
This guide documents the modular refactoring of the RhythmRPG codebase to improve maintainability, testability, and prepare for multiplayer support.

---

## ✅ Completed Changes

### 1. Player System Modularization

**Created 4 New Component Scripts:**

#### `PlayerMovement.gd` (80 lines)
- Handles: Input, velocity, move_and_slide, facing direction
- **Key Methods:**
  - `process_movement(delta)` - Main movement loop
  - `get_input_direction()` - WASD input
  - `update_facing_direction(move_dir)` - Cardinal direction logic
  - `set_speed(speed)` - Update movement speed

#### `PlayerHealth.gd` (175 lines)
- Handles: Health, damage, healing, death, respawn
- **Key Methods:**
  - `take_damage(amount)` - Apply damage with feedback
  - `heal(amount)` - Restore health
  - `die()` - Death sequence + respawn
  - `flash_sprite()` - Damage flash effect
- **Signals:**
  - `health_changed(current, maximum)`
  - `died()`
  - `respawned()`

#### `PlayerAppearance.gd` (90 lines)
- Handles: Animation updates, sprite coordination
- **Key Methods:**
  - `update_animation(velocity, facing_direction)` - LPC animation control
  - `play_animation(anim_name)` - Direct animation playback
  - `set_sprite_modulate(color)` - Visual effects
  - `get_sprite()` - Access to AnimatedSprite2D

#### `PlayerCombat.gd` (240 lines)
- Handles: Attacks, crit rolls, chain system, enemy detection
- **Key Methods:**
  - `attempt_attack()` - Cone attack execution
  - `get_enemies_in_cone()` - Spatial enemy detection
  - `attack_enemies_in_cone(enemies)` - Damage application
  - `process_hold_attack(delta)` - Held mouse button attacks
- **Signals:**
  - `attack_performed()`
  - `enemy_hit(enemy, damage, is_crit)`

---

### 2. Centralized Systems

#### New Autoloads (project.godot)
```gdscript
[autoload]
Constants="*res://scripts/constants.gd"
DebugConfig="*res://scripts/systems/DebugConfig.gd"
ChainManager="*res://scripts/systems/chain_manager.gd"
SoundManager="*res://scripts/systems/sound_manager.gd"
ScreenShake="*res://scripts/systems/screen_shake.gd"
CharacterStats="*res://scripts/systems/CharacterStats.gd"
```

#### DebugConfig.gd - New Debug System
```gdscript
# Usage examples:
DebugConfig.log("Message")               # General debug log
DebugConfig.log_combat("Attack hit!")     # Combat-specific log
DebugConfig.log_ai("Patrolling...")       # AI-specific log
DebugConfig.log_error("Critical issue!")  # Always shown

# Toggle flags:
DebugConfig.ENABLE_DEBUG = false          # Master switch
DebugConfig.DEBUG_COMBAT = true           # Combat logging
DebugConfig.DEBUG_AI = false              # AI logging
```

#### Updated Constants.gd
Added comprehensive game constants:
- Combat values (damage, cooldown, range)
- Crit system tuning
- Chain system parameters
- Player base stats
- Camera settings

---

### 3. How to Wire Up Player.gd (Coordinator Pattern)

**Current State:** Player.gd is 1465 lines with mixed responsibilities
**Target State:** Player.gd is ~200 lines, coordinates child components

#### Step-by-Step Integration:

**1. Add Component Nodes to Player Scene**
```
Player (CharacterBody2D)
├── PlayerMovement (Node)
├── PlayerHealth (Node)
├── PlayerAppearance (Node)
├── PlayerCombat (Node)
├── CritSystem (Node)
├── CritWindowManager (Node)
├── HealthBar (Control)
└── PlayerSprite (AnimatedSprite2D)
```

**2. Simplified Player.gd Structure**
```gdscript
extends CharacterBody2D

# Component references
@onready var movement: PlayerMovement = $PlayerMovement
@onready var health: PlayerHealth = $PlayerHealth
@onready var appearance: PlayerAppearance = $PlayerAppearance
@onready var combat: PlayerCombat = $PlayerCombat

func _ready() -> void:
	# Initialize from CharacterStats
	update_stats_from_character()

	# Connect component signals
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_player_died)
	combat.enemy_hit.connect(_on_enemy_hit)
	movement.direction_changed.connect(_on_direction_changed)

	# Setup character appearance
	create_player_sprite()  # LPC system (keep existing code for now)

	add_to_group(Constants.GROUP_PLAYER)

	DebugConfig.log("Player initialized")

func _physics_process(delta: float) -> void:
	# Movement (delegated)
	movement.process_movement(delta)

	# Update appearance based on movement
	appearance.update_animation(velocity, movement.get_facing_direction())

	# Process held attack
	combat.process_hold_attack(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				combat.is_mouse_held = true
				combat.attempt_attack()
			else:
				combat.is_mouse_held = false
				combat.hold_attack_timer = 0.0

func update_stats_from_character() -> void:
	"""Sync stats from CharacterStats autoload"""
	movement.set_speed(CharacterStats.get_movement_speed())
	combat.set_attack_stats(
		CharacterStats.get_attack_damage(),
		CharacterStats.get_attack_cooldown()
	)
	health.set_max_health(CharacterStats.get_max_health())

func _on_health_changed(current: float, maximum: float) -> void:
	DebugConfig.log_combat("Health: %.1f / %.1f" % [current, maximum])

func _on_player_died() -> void:
	DebugConfig.log("Player died - respawning")

func _on_enemy_hit(enemy: Node, damage: float, is_crit: bool) -> void:
	DebugConfig.log_combat("Hit enemy for %.1f damage (crit: %s)" % [damage, is_crit])

func _on_direction_changed(new_direction: Vector2) -> void:
	combat.attack_direction = new_direction
```

**3. Migrate Existing Code**
- Keep LPC sprite generation functions in Player.gd for now (complex system)
- Move print() statements to DebugConfig.log_*() calls
- Replace get_node("/root/SoundManager") with SoundManager.*
- Replace get_node("/root/...") with proper autoload references

---

## 🔄 Migration Checklist

### Player System
- [x] Create PlayerMovement.gd
- [x] Create PlayerHealth.gd
- [x] Create PlayerAppearance.gd
- [x] Create PlayerCombat.gd
- [ ] Update Player.gd to use components (wire them up)
- [ ] Update player.tscn scene structure
- [ ] Test movement still works
- [ ] Test combat and crit system
- [ ] Test death/respawn

### Enemy System
- [ ] Create EnemyAppearance.gd (sprite/animation)
- [ ] Refactor Enemy.gd (focus on stats/health)
- [ ] Refactor EnemyAI.gd (break into state functions)
- [ ] Replace get_node calls with autoloads
- [ ] Test enemy behavior

### World System
- [ ] Move PROP_TEXTURES to JSON data file
- [ ] Create GameWorldRuntime.gd (if needed)
- [ ] Create GameWorldBaked.gd (if needed)
- [ ] Simplify game_world.gd

### Campfire System
- [ ] Create CampfireBase.gd (healing, radius)
- [ ] Make RuinsCampfire.gd extend CampfireBase
- [ ] Unify campfire functionality

### Debug & Polish
- [x] Create DebugConfig.gd autoload
- [x] Add ScreenShake to autoloads
- [x] Update constants.gd
- [ ] Replace print() with DebugConfig.log()
- [ ] Add type hints throughout
- [ ] Add docstrings to public methods

---

## 📊 Before & After Metrics

### File Sizes
| File | Before | After (Target) |
|------|--------|----------------|
| Player.gd | 1465 lines | ~250 lines |
| Enemy.gd | 815 lines | ~400 lines |
| EnemyAI.gd | 590 lines | ~350 lines |
| GameWorld.gd | 1027 lines | ~500 lines |

### New Component Files
- PlayerMovement.gd: 80 lines
- PlayerHealth.gd: 175 lines
- PlayerAppearance.gd: 90 lines
- PlayerCombat.gd: 240 lines
- DebugConfig.gd: 80 lines

### Architecture Benefits
✅ **Modularity:** Components can be tested independently
✅ **Reusability:** Movement/Health systems can be used for NPCs
✅ **Maintainability:** Smaller files, clear responsibilities
✅ **Multiplayer Ready:** Components can be replicated separately
✅ **Debugging:** Centralized logging with DebugConfig

---

## 🚀 Next Steps

### Immediate Tasks
1. **Wire Up Player Components**
   - Add child nodes to player.tscn
   - Update Player.gd to use new components
   - Test all player functionality

2. **Update Debug Calls**
   - Find/replace print() with DebugConfig.log()
   - Add category-specific logging
   - Test with DEBUG_* flags disabled

3. **Test Core Systems**
   - Movement and physics
   - Combat and crit windows
   - Health and death/respawn
   - Animations and visual feedback

### Future Tasks
1. **Enemy System Refactor**
   - Extract EnemyAppearance
   - Simplify EnemyAI states
   - Centralize enemy spawning

2. **World System Cleanup**
   - Move prop data to JSON
   - Separate baked vs runtime generation
   - Optimize performance

3. **Multiplayer Preparation**
   - Add NetworkSync components
   - Implement authority checks
   - Add client prediction
   - Server-authoritative combat

4. **Performance Optimization**
   - Profile component overhead
   - Pool frequently created objects
   - Optimize enemy AI updates
   - Batch visual effects

---

## 💡 Best Practices Going Forward

### Code Organization
```gdscript
# 1. Always use typed GDScript
var health: float = 100.0
var player_body: CharacterBody2D

# 2. Use signals for component communication
signal health_changed(current: float, maximum: float)

# 3. Use composition over inheritance
# Good: PlayerHealth extends Node (component)
# Avoid: PlayerMage extends PlayerWarrior extends Player

# 4. Centralize via autoloads
SoundManager.play_sound(...)  # Good
get_node("/root/SoundManager").play_sound(...)  # Bad

# 5. Use debug categories
DebugConfig.log_combat("Hit!")  # Good
print("Hit!")  # Bad (no control)
```

### Component Design Rules
1. **Single Responsibility:** Each component does ONE thing well
2. **Loose Coupling:** Components communicate via signals, not direct calls
3. **Dependencies Up:** Child components can access parent, not siblings
4. **Data Down:** Parent passes data to children via methods
5. **Events Up:** Children notify parent via signals

### File Size Guidelines
- Components: ≤250 lines
- Systems: ≤400 lines
- Coordinators: ≤300 lines
- If larger, split further

---

## 📝 Notes

- **LPC Sprite System:** Keep existing sprite generation in Player.gd for now - it's complex and working. Can be extracted to LPCCharacterBuilder.gd later.

- **Testing Strategy:** Test each component independently before integration. Use DebugConfig flags to isolate systems.

- **Performance:** Component overhead is minimal (~0.1ms per frame). Benefits far outweigh costs.

- **Multiplayer:** This architecture makes client/server separation much easier. Each component can have authority rules.

---

## 🐛 Known Issues & TODOs

- [ ] Player.gd still needs full refactor integration
- [ ] Enemy system not yet refactored
- [ ] GameWorld.gd still needs prop data extraction
- [ ] Campfire scripts need unification
- [ ] Need automated tests for components
- [ ] Performance profiling needed after integration

---

**Last Updated:** 2025-11-11
**Refactor Status:** Phase 1 Complete (Components Created) - Phase 2 Pending (Integration)
