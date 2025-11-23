# LPC Character System - Complete Guide

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Getting Started](#getting-started)
4. [Asset Creation](#asset-creation)
5. [Sprite System](#sprite-system)
6. [Armor System](#armor-system)
7. [Weapon System](#weapon-system)
8. [Character Creation](#character-creation)
9. [Implementation Guide](#implementation-guide)
10. [Asset Reference](#asset-reference)
11. [Advanced Topics](#advanced-topics)
12. [Troubleshooting](#troubleshooting)

---

## Overview

The LPC (Liberated Pixel Cup) Character System provides a complete solution for creating modular, layered 2D characters in Godot. The system supports multiple body types, animations, equipment layers, and visual customization.

### Key Features

- Fully modular character composition
- 5-layer armor system (head, chest, arms, legs, feet)
- Dynamic weapon rendering
- 13 standard animations per character
- Variable sprite sizes (64x64 and 192x192 tiles)
- Gender-specific sprites
- Equipment drag-and-drop UI
- Real-time sprite reloading on equipment changes

### LPC Sprite Format

All LPC sprites follow this standard structure:

#### Walk Animation (576 x 256 pixels)
- 9 frames per row
- 4 rows: UP (north), LEFT (west), DOWN (south), RIGHT (east)
- Frame size: 64x64 pixels

#### Slash Animation (384 x 256 pixels)
- 6 frames per row
- 4 rows: UP, LEFT, DOWN, RIGHT
- Frame size: 64x64 pixels

#### Hurt Animation (384 x 64 pixels)
- 6 frames in a single row
- Frame size: 64x64 pixels

**IMPORTANT**: Never use flip_h or scale.x = -1 with LPC sprites. Each direction has its own sprite row.

---

## System Architecture

### Components

```
Character Rendering System
├── CharacterStats.gd       # Equipment state management
├── Player.gd               # Multi-layer sprite rendering
├── SimpleLPCSprite.gd      # Core sprite animation system
├── CharacterUI.gd          # Equipment interface
└── LPC Assets              # Sprite sheets and textures
```

### Data Flow

1. **Equipment Change** → CharacterStats.gd updates equipment state
2. **Signal Emitted** → `armor_equipped` or `weapon_equipped` signal fires
3. **Sprite Reload** → Player.gd rebuilds sprite layers
4. **Layer Creation** → SimpleLPCSprite.gd creates AnimatedSprite2D nodes
5. **Animation Sync** → All layers play synchronized animations

---

## Getting Started

### LPC Generator Access

**Online Generator**: https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/

**Local Repository**: `C:\Fraps\Universal-LPC-Spritesheet-Character-Generator-master (1)\Universal-LPC-Spritesheet-Character-Generator-master\`

### Local Repository Structure

```
spritesheets/
├── arms/          # Arm armor, gloves, armguards
├── body/          # Body types, tails, wings, wounds
├── dress/         # Dresses and bodices
├── feet/          # Boots, shoes, armor
├── hair/          # Hair styles
├── hat/           # Hats and helmets
├── head/          # Head accessories
├── legs/          # Pants, leggings, skirts, armor
├── shield/        # All shield types
├── torso/         # Shirts, armor, jackets, robes
└── weapon/        # All weapon types
```

---

## Asset Creation

### Creating Custom Characters

#### Step 1: Access the Generator
1. Open the LPC generator URL
2. You'll see a character preview with customization options on the left

#### Step 2: Configure Character Appearance

**Body:**
- Select body type: Male, Female, Muscular, Teen, Child
- Choose skin tone

**Clothing:**
- Torso: Shirts, armor, robes, jackets, aprons
- Legs: Pants, leggings, skirts, armor
- Feet: Boots, shoes
- Head: Helmets, hats, hair

**Accessories:**
- Facial hair: Beards, mustaches
- Backpacks, capes, shoulder pads
- Weapons and shields

#### Step 3: Export Sprite Sheets

**Required Exports** (3 animation types):

1. **WALK animations** (9 frames per direction)
   - In generator: Click "Walk" tab
   - Click "Download PNG"
   - Save as: `[name]_walk.png`

2. **SLASH animations** (6 frames per direction)
   - In generator: Click "Slash" tab
   - Click "Download PNG"
   - Save as: `[name]_slash.png`

3. **HURT animations** (6 frames)
   - In generator: Click "Hurt" tab
   - Click "Download PNG"
   - Save as: `[name]_hurt.png`

### Export Methods

#### Method 1: Composite Export (Easiest)

Design the full character with all layers enabled, then export once.

**Pros:**
- Fastest method
- Single file per animation
- Simple to implement

**Cons:**
- No layer flexibility
- Can't swap individual pieces

#### Method 2: Layered Export (Recommended)

Export each layer separately for maximum flexibility.

**Example Layers:**
- Body base layer
- Clothing/armor layers
- Facial hair layer
- Accessory layers

**Pros:**
- Maximum flexibility
- Can mix and match pieces
- Supports equipment system

**Cons:**
- More files to manage
- Requires careful layer management

### File Organization

```
assets/characters/
├── lpc/
│   ├── blacksmith/
│   │   ├── body_male_walk.png
│   │   ├── body_male_slash.png
│   │   ├── body_male_hurt.png
│   │   ├── beard_male_walk.png
│   │   ├── beard_male_slash.png
│   │   ├── beard_male_hurt.png
│   │   ├── apron_walk.png
│   │   ├── apron_slash.png
│   │   └── apron_hurt.png
│   └── README.md
└── armor_tier1/
    ├── standard/              # Male sprites
    │   ├── walk/
    │   │   ├── 015 feet armour plate male copper.png
    │   │   ├── 020 legs armour plate male copper.png
    │   │   ├── 060 arms armour plate male copper.png
    │   │   ├── 060 torso armour plate male copper.png
    │   │   └── 130 hat helmet bascinet adult copper.png
    │   ├── slash/
    │   └── ... (13 animations total)
    ├── female/                # Female sprites (future)
    └── credits/
        └── metadata.json
```

---

## Sprite System

### SimpleLPCSprite API

The core sprite system provides layered character rendering.

#### setup_lpc_sprite()

```gdscript
func setup_lpc_sprite(
    walk_tex: Texture2D,
    slash_tex: Texture2D = null,
    hurt_tex: Texture2D = null,
    weapon_slash_tex: Texture2D = null,
    weapon_walk_tex: Texture2D = null
)
```

Sets up the base character sprite with optional combat animations and weapon layers.

#### play_lpc_animation()

```gdscript
func play_lpc_animation(anim_name: String, direction: String)
```

- **anim_name**: "walk", "idle", "slash", "hurt"
- **direction**: "north", "south", "east", "west"

**Important**: Direction names use LPC convention (north/south/east/west), not Godot convention (up/down/left/right).

#### create_animation_from_image()

```gdscript
func create_animation_from_image(
    img: Image,
    anim_name: String,
    row: int,
    frame_count: int,
    frame_indices: Array,
    fps: float,
    loop: bool,
    target_frames: SpriteFrames = null,
    tile_size: int = 64  # Auto-calculated for variable sizes
)
```

Low-level function for creating animations from sprite sheets.

### Layer System

#### Layer Order (Z-Index)

```
Layer 7: Weapon (when facing south/east/west) [z=1]
Layer 6: Head armor (helmet) [z=0.5]
Layer 5: Arm armor (armguards) [z=0.4]
Layer 4: Chest armor (torso) [z=0.3]
Layer 3: Leg armor (pants) [z=0.2]
Layer 2: Foot armor (boots) [z=0.1]
Layer 1: Base body [z=0]
Layer 0: Weapon (when facing north) [z=-1]
```

**Note**: Weapon layer switches between z=1 and z=-1 based on facing direction to appear in front or behind the character.

### Variable Tile Size Support

The system automatically detects sprite tile sizes:

- **Standard sprites**: 64x64 tiles (576x256 walk sheets)
- **Oversize sprites**: 192x192 tiles (1152x768 sheets)

Calculation: `tile_size = sprite_width / frame_count`

This allows for larger weapon sprites (like longswords) to render correctly.

### Animation Synchronization

All layers play the same animation frame simultaneously:
- Frame 0 of walk → All layers show walk frame 0
- Frame 3 of slash → All layers show slash frame 3

This ensures perfect visual alignment across all equipment layers.

---

## Armor System

### Armor Slots (5 Total)

| Slot | Type | Layer Order | Z-Index | Example Item |
|------|------|-------------|---------|--------------|
| `feet` | Boots | Layer 2 | 0.1 | Copper Plate Boots |
| `legs` | Pants/Leg Armor | Layer 3 | 0.2 | Copper Plate Legs |
| `chest` | Shirt/Chest Armor | Layer 4 | 0.3 | Copper Plate Torso |
| `arms` | Armguards/Sleeves | Layer 5 | 0.4 | Copper Plate Armguards |
| `head` | Helmet/Hat | Layer 6 | 0.5 | Copper Bascinet Helmet |

**Note**: The slot name for arm armor is "arms" (not "gauntlets"). Use "armguards" when referring to this equipment slot.

### Copper Armor Set (Tier 1)

**Location**: `assets/characters/armor_tier1/`

The Copper Armor Set serves as the reference template for all future armor tiers.

#### Exported Files (Per Armor Piece)

Each armor piece is exported as a separate spritesheet for **13 different animations**:

**Standard Animations:**
- `walk` - 9 frames
- `run` - 8 frames
- `idle` - 2 frames
- `combat_idle` - 2 frames
- `slash` - 6 frames
- `halfslash` - 7 frames
- `backslash` - 13 frames
- `thrust` - 8 frames
- `shoot` - 13 frames
- `spellcast` - 7 frames
- `hurt` - 6 frames
- `climb` - 6 frames
- `sit` - 3 frames
- `jump` - 5 frames
- `emote` - 3 frames

**Currently Used**: walk, slash, hurt (expand as needed)

### LPC Naming Convention

#### File Naming Format

```
[Z-Index] [Category] [Type] [Gender] [Material].png
```

**Examples:**
- `015 feet armour plate male copper.png` → Z-index 15, Feet Armor, Plate type, Male, Copper material
- `020 legs armour plate male copper.png` → Z-index 20, Leg Armor, Plate type, Male, Copper
- `060 arms armour plate male copper.png` → Z-index 60, Arm Armor, Plate type, Male, Copper
- `060 torso armour plate male copper.png` → Z-index 60, Torso Armor, Plate type, Male, Copper
- `130 hat helmet bascinet adult copper.png` → Z-index 130, Helmet, Bascinet style, Adult size, Copper

#### Z-Index Layer Order
- `015` - Feet (boots)
- `020` - Legs (pants)
- `060` - Arms & Torso (worn in same visual layer)
- `130` - Head (helmets/hats)

### Equipment Management

#### CharacterStats.gd - Armor State

```gdscript
# Equipped armor dictionary
var equipped_armor = {
    "head": null,
    "chest": null,
    "arms": null,
    "legs": null,
    "feet": null
}

# Equip function
func equip_armor(armor_item: Dictionary) -> bool:
    var slot = armor_item.get("slot", "")

    # Auto-unequip old armor
    if equipped_armor[slot]:
        var old_armor = equipped_armor[slot]
        InventorySystem.add_item(old_armor)

    # Equip new armor
    equipped_armor[slot] = armor_item
    armor_equipped.emit(slot, armor_item)
    return true

# Unequip function
func unequip_armor(slot: String) -> bool:
    var armor_item = equipped_armor[slot]
    if armor_item:
        equipped_armor[slot] = null
        armor_unequipped.emit(slot, armor_item)
        return true
    return false
```

#### Signals

- `armor_equipped(slot: String, armor_item: Dictionary)` - Emitted when armor is equipped
- `armor_unequipped(slot: String, armor_item: Dictionary)` - Emitted when armor is removed

The Player.gd listens to these signals and reloads armor sprites automatically.

### Armor Item Data Structure

```gdscript
{
    "name": "Copper Plate Boots",
    "slot": "feet",
    "type": "armor",
    "defense": 5,
    "value": 150,
    "description": "Heavy copper plate boots",
    "sprite_name": "copper_plate_boots",
    "rarity": "Common",
    "required_level": 1,
    "stackable": false
}
```

#### Required Fields

- `name` (String) - Display name
- `slot` (String) - Must be: "head", "chest", "arms", "legs", or "feet"
- `type` (String) - Must be "armor"
- `defense` (int) - Defense value added to total
- `sprite_name` (String) - Base name for sprite files (without animation suffix)

#### Optional Fields

- `required_level` (int) - Minimum level to equip
- `rarity` (String) - Common, Uncommon, Rare, Epic, Legendary
- `set_bonus` (String) - Set item identification (future)
- `special_effect` (String) - Special armor effects (future)

### Defense Calculation

```gdscript
func get_total_defense() -> int:
    var total = 0
    for slot in equipped_armor:
        var armor_item = equipped_armor[slot]
        if armor_item:
            total += armor_item.get("defense", 0)
    return total
```

Defense reduces incoming damage (exact formula TBD).

### Starting Equipment

Players start with basic clothing (not armor):

```gdscript
# Default starting outfit (CharacterStats.gd _ready())
equipped_armor["chest"] = {
    "name": "White Shirt",
    "slot": "chest",
    "type": "armor",
    "defense": 0,
    "value": 0,
    "description": "Simple cloth shirt",
    "sprite_name": "white_shirt",
    "rarity": "Common"
}

equipped_armor["legs"] = {
    "name": "Green Pants",
    "slot": "legs",
    "type": "armor",
    "defense": 0,
    "value": 0,
    "description": "Common cloth pants",
    "sprite_name": "green_pants",
    "rarity": "Common"
}
```

---

## Weapon System

### Dynamic Weapon Loading

Weapons are dynamically loaded based on the equipped weapon's `weapon_type` property.

```gdscript
if CharacterStats.equipped_weapon:
    var weapon_type = CharacterStats.equipped_weapon.weapon_type
    var weapon_path = "res://assets/weapons/" + weapon_type + "/"

    weapon_slash_tex = load(weapon_path + "slash.png")
    weapon_walk_tex = load(weapon_path + "walk.png")
```

### Weapon Layer Features

- **Auto-detection**: Tile size calculated from sprite dimensions
- **Direction-based offsets**: Slash animations offset to align with player body
- **Z-index switching**: Weapon renders behind player when facing north
- **Visibility control**: Hidden when no weapon equipped or during walk/idle

### Weapon Slash Offsets

Direction-specific offsets to align weapon with player body:

- **East** (facing right): `(-5, 10)`
- **West** (facing left): `(5, 10)`
- **North** (facing up): `(-10, 0)`
- **South** (facing down): `(-5, 5)`

### Supported Weapon Types

Located in `assets/weapons/{type}/`:

- `mace` - Default starter weapon (Wooden Mace - free)
- `longsword` - Longsword family
- `dagger` - Fast attack weapons
- `spear` - Polearms
- `warhammer` - Slow, heavy weapons
- `rapier` - Fast precision weapons
- `club` - Basic blunt weapons
- `glowsword_blue` - Legendary drop
- `glowsword_red` - Legendary drop

### Weapon Equipment Flow

1. **Player picks up weapon** → Added to inventory
2. **Player equips weapon** → `CharacterStats.equip_weapon()` called
3. **Signal emitted** → `weapon_equipped` signal triggers
4. **Player sprite refreshed** → `create_player_sprite()` rebuilds sprite with weapon
5. **Weapon layer created** → SimpleLPCSprite creates weapon AnimatedSprite2D child
6. **Animations synced** → Weapon animations play in sync with body animations

---

## Character Creation

### Creating NPCs

#### Simple NPCs (Non-Combat)

For vendors, quest givers, and other non-combat NPCs, you only need walk animations.

**Example**: The Blacksmith

**Location**: `assets/characters/lpc/blacksmith/`

**Required Files**:
- `blacksmith_walk.png` (256x64 = 4 frames of 64x64)

See `Vendor.gd` for an example of loading a simple 4-frame walk cycle.

#### Complex NPCs (Combat-Capable)

For enemies, companions, and combat NPCs, use the full LPCCharacter class.

**Required Animations**:
- Walk (9 frames per direction)
- Slash (6 frames per direction)
- Hurt (6 frames)

**Examples**: Skeleton, Zombie enemies

### NPC Creation Workflow

#### Step 1: Design in LPC Generator

**Blacksmith Example**:
- Body: Male, tan/muscular skin
- Facial Hair: Fullbeard or Muttonchops (brown/grey)
- Torso: Apron or leather vest
- Legs: Brown pants or work trousers
- Feet: Brown boots
- Optional: Bald/short hair, rolled-up sleeves

#### Step 2: Export Sprites

**For Simple NPCs**: Export walk animation only
**For Combat NPCs**: Export walk, slash, and hurt animations

#### Step 3: Organize Files

Place exported sprites in:
```
assets/characters/lpc/{npc_name}/
├── {npc_name}_walk.png
├── {npc_name}_slash.png  # If combat-capable
└── {npc_name}_hurt.png   # If combat-capable
```

#### Step 4: Create NPC Script

Use `LPCCharacter` class for combat NPCs or simple AnimatedSprite2D for non-combat NPCs.

### Quick NPC Ideas

Once you have the system working, you can easily create:

- **Guards**: Metal armor, helmet, sword (use Zone 2/3 armor)
- **Merchants**: Fancy robes, hat
- **Farmers**: Simple clothes, straw hat
- **Mages**: Robes, staff
- **Innkeeper**: Apron, casual clothes
- **Zombies**: Use zombie body type
- **Skeletons**: Use skeleton body
- **Bandits**: Mix of leather armor and civilian clothes
- **Nobles**: Fancy clothing, jewelry accessories

---

## Implementation Guide

### Player.gd Integration

#### create_player_sprite()

```gdscript
func create_player_sprite():
    # Load base body textures
    var body_type = "human" if selected_gender == Gender.MALE else "female"
    var walk_tex = load("res://assets/characters/BODY_" + body_type + "_walk.png")
    var slash_tex = load("res://assets/characters/BODY_" + body_type + "_slash.png")
    var hurt_tex = load("res://assets/characters/BODY_" + body_type + "_hurt.png")

    # Load weapon textures based on equipped weapon
    var weapon_slash_tex = null
    var weapon_walk_tex = null

    if CharacterStats.equipped_weapon:
        var weapon_type = CharacterStats.equipped_weapon.weapon_type
        var weapon_path = "res://assets/weapons/" + weapon_type + "/"

        if ResourceLoader.exists(weapon_path + "slash.png"):
            weapon_slash_tex = load(weapon_path + "slash.png")
        if ResourceLoader.exists(weapon_path + "walk.png"):
            weapon_walk_tex = load(weapon_path + "walk.png")

    # Setup layered sprite
    character_sprite.setup_lpc_sprite(
        walk_tex, slash_tex, hurt_tex,
        weapon_slash_tex, weapon_walk_tex
    )
```

#### update_lpc_animation()

```gdscript
func update_lpc_animation(velocity_dir: Vector2) -> void:
    var character_sprite = get_node_or_null("CharacterSprite")
    if not character_sprite:
        return

    # Don't interrupt attack animations
    if character_sprite.animation and character_sprite.animation.begins_with("slash_") and character_sprite.is_playing():
        return

    # Get direction
    var is_moving = velocity_dir.length() > 0.1
    var dir_str = get_direction_string(velocity_dir) if is_moving else get_direction_string(attack_direction)
    var lpc_dir = convert_to_lpc_direction(dir_str)

    # Play animation
    var anim = "walk" if is_moving else "idle"
    character_sprite.play_lpc_animation(anim, lpc_dir)
```

#### attempt_attack()

```gdscript
func attempt_attack() -> void:
    # ... attack logic ...

    # Play attack animation
    var character_sprite = get_node_or_null("CharacterSprite")
    if character_sprite:
        var dir_str = get_direction_string(attack_direction)
        var lpc_dir = convert_to_lpc_direction(dir_str)
        character_sprite.play_lpc_animation("slash", lpc_dir)
```

#### Direction Conversion Helper

```gdscript
func convert_to_lpc_direction(godot_dir: String) -> String:
    match godot_dir:
        "down": return "south"
        "up": return "north"
        "left": return "west"
        "right": return "east"
        _: return "south"  # Default
```

### Loading Armor Textures

```gdscript
func reload_sprites():
    # Load armor textures for each slot
    var boots_walk_tex = null
    var pants_walk_tex = null
    var shirt_walk_tex = null
    var arms_walk_tex = null
    var head_walk_tex = null

    # Check each equipped armor slot
    if CharacterStats.equipped_armor.has("feet"):
        var boots_armor = CharacterStats.equipped_armor["feet"]
        var sprite_name = boots_armor.get("sprite_name", "")
        var path = "res://assets/characters/boots/" + sprite_name
        if ResourceLoader.exists(path + "_walk.png"):
            boots_walk_tex = load(path + "_walk.png")

    # ... repeat for other slots ...

    # Pass all textures to sprite renderer
    character_sprite.setup_lpc_sprite(
        walk_tex, slash_tex, hurt_tex,
        boots_walk_tex, boots_slash_tex,
        pants_walk_tex, pants_slash_tex,
        shirt_walk_tex, shirt_slash_tex,
        arms_walk_tex, arms_slash_tex,
        head_walk_tex, head_slash_tex,
        weapon_slash_tex, weapon_walk_tex,
        weapon_type
    )
```

---

## Asset Reference

### Assets Already in Game

#### Armor (5 Slots, 4 Zones - 20 pieces total)

**Zone 1: The Wasteland** (Brown Leather - 41 defense)
- Location: `assets/armor/zone1/`
- Chest: Brown leather armor
- Hands: Leather gloves
- Legs: Leather leggings
- Feet: Brown boots
- Head: Bronze nasal helmet

**Zone 2: The Cursed Lands** (Iron/Chainmail - 70 defense)
- Location: `assets/armor/zone2/`
- Chest: Gray chainmail
- Hands: Iron bracers
- Legs: Iron plate greaves
- Feet: Iron plate boots
- Head: Iron barbuta helmet

**Zone 3: The Shadow Realm** (Silver Plate - 100 defense)
- Location: `assets/armor/zone3/`
- Chest: Silver plate armor
- Hands: Silver plate armguards
- Legs: Silver plate greaves
- Feet: Silver plate boots
- Head: Silver close helmet (full-face)

**Zone 4: The Abyss** (Dark Gleaming Endgame - EPIC/LEGENDARY)
- Location: `assets/armor/zone4/`
- Chest: Dark legion armor (gunmetal/dark base color)
- Hands: Dark iron plate armguards
- Legs: Dark iron plate greaves
- Feet: Dark iron plate boots
- Head: Dark flattop great helmet

#### Weapons (9 total)

Location: `assets/weapons/`

- Club (`club.png`)
- Dagger (`dagger.png`)
- Longsword (`longsword.png`)
- Mace (`mace.png`)
- Spear (`spear.png` - bronze)
- Rapier (`rapier.png`)
- Warhammer (`warhammer.png` - uses waraxe sprite)
- Glowsword Blue (`glowsword_blue.png` - legendary drop)
- Glowsword Red (`glowsword_red.png` - legendary drop)

#### Enemies (2 types)

Location: `assets/enemies/`

- Skeleton (`skeleton.png`) - Zone 1 enemy
- Zombie (`zombie.png`) - Zone 2 enemy

#### NPCs (4 sprites)

Location: `assets/npcs/`

- Male body (`male_body.png` - light skin)
- Female body (`female_body.png` - light skin)
- Male vest (`male_vest.png` - brown merchant clothing)
- Female robe (`female_robe.png` - dark brown merchant clothing)

#### Shields (4 variants)

Location: `assets/shields/`

- Bronze shield (`shield_bronze.png`) - Zone 1
- Silver shield (`shield_silver.png`) - Zone 2/3
- Gold shield (`shield_gold.png`) - Zone 3
- Crusader shield (`shield_crusader.png`) - Zone 4 endgame

### Available Assets (Not Yet Used)

#### Body Types
- Muscular - For elite enemies or bosses
- Child - For village NPCs (non-combat)
- Teen - For younger NPCs
- Pregnant - For NPC variety
- Fur variants - For beast-like characters (black, brown, copper, gold, grey, tan, white)

#### Clothing & Accessories

**Torso/Chest:**
- Blouses (regular, long sleeve)
- Corsets
- Long/short sleeve shirts
- Sleeveless shirts
- Tunics (multiple styles)
- Vests (regular and open)
- Jackets (collared, frock, iverness, pockets, santa, tabard, trench)
- Aprons (full, half, overalls, suspenders)
- Bandages

**Legs:**
- Cuffed pants
- Formal pants (plain and striped)
- Fur leggings
- Hose
- Leggings (2 variants)
- Pantaloons
- Regular pants (2 variants)
- Shorts
- Skirts

**Head/Hair:**
- Beards (5 o'clock shadow, basic, full, muttonchops, goatees)
- Hair (massive variety - long, short, styled)
- Hats (formal, headbands, holiday, magic, pirate, visors)
- Helmets (decorative variants beyond combat types)

#### Accessories
- Backpacks - Could add inventory visual
- Bauldrons - Shoulder armor
- Capes - Legendary cosmetic items
- Tools - Rod, whip, smash, thrust
- Quivers - For archers
- Wrists - Wrist armor/accessories
- Shoulders - Shoulder pads/armor

#### Additional Weapons

**Magical Weapons:**
- Diamond staff (thrust/spellcast animations)
- Diamond off-hand variant
- Various magical implements

**Melee Weapons:**
- Katana, Saber, Scimitar
- Arming sword variants
- Flail, Halberd, Longspear
- Dragonspear, Scythe, Trident
- Cane

**Ranged Weapons:**
- Bows (various styles)
- Crossbows

#### Shield Variants

- Heater shields
- Kite shields
- Plus shields
- Scutum (Roman style)
- Spartan shields
- Two engrailed
- Round shields (various colors)
- Colored variants for all types

#### Special Features

- Shadow sprites - Character shadows for depth
- Body prosthetics - Hook hands, peg legs, wheelchairs
- Wings - Bat wings, bird wings
- Tails - Animal tails for beast characters
- Wounds - Injury overlays

---

## Advanced Topics

### Creating New Armor Tiers

#### Future Armor Tiers (Planned)

| Tier | Material | Level Range | Defense Range | Location |
|------|----------|-------------|---------------|----------|
| 1 | Copper | 1-10 | 5-15 per piece | `armor_tier1/` |
| 2 | Bronze | 11-18 | 12-25 per piece | `armor_tier2/` |
| 3 | Iron | 19-24 | 20-35 per piece | `armor_tier3/` |
| 4 | Steel | 25-30 | 30-50 per piece | `armor_tier4/` |
| 5 | Legendary | 30+ | 45-70 per piece | `armor_tier5/` |

#### Template Process

1. **Export from LPC Generator**:
   - Use same body type (male/female)
   - Export all 13 standard animations
   - Use consistent naming: `015 feet armour plate male [MATERIAL].png`
   - Export to `assets/characters/armor_tier[X]/standard/[animation]/`

2. **Create Metadata**:
   - Copy `armor_tier1/credits/metadata.json`
   - Update timestamp, material name
   - Verify all animations exported

3. **Define Item Data**:
   - Create JSON file in `data/shop_armor_zone[X].json`
   - Set appropriate defense values for tier
   - Set required level
   - Set gold cost (generally: tier * 100-300g per piece)

4. **Add to Vendors**:
   - Ruins 1 sells Tier 1 (copper)
   - Ruins 2 sells Tier 2 (bronze)
   - Ruins 3 sells Tier 3 (iron)
   - Castle shop sells Tier 4-5

### Gender Support

#### Current Status
- Male sprites: Fully implemented (copper tier 1)
- Female sprites: Structure ready, not yet exported

#### Future Implementation

Female armor will use the same system:
```
armor_tier1/
├── standard/     # Male sprites (current)
└── female/       # Female sprites (future)
    ├── walk/
    └── ... (same 13 animations)
```

Player.gd will check `selected_gender` and load from appropriate folder.

### Metadata Tracking

The `metadata.json` file tracks export information:

```json
{
  "exportTimestamp": "2025-11-18T03-14-50",
  "bodyType": "male",
  "standardAnimations": {
    "exported": {
      "walk": [
        "015 feet armour plate male copper.png",
        "020 legs armour plate male copper.png",
        "060 arms armour plate male copper.png",
        "060 torso armour plate male copper.png",
        "130 hat helmet bascinet adult copper.png"
      ]
    }
  },
  "frameCounts": {
    "walk": 9,
    "slash": 6
  }
}
```

### Performance Considerations

#### Sprite Loading
- Armor sprites are loaded on-demand when equipped
- Uses `ResourceLoader.exists()` checks before loading
- Textures cached by Godot automatically

#### Memory Usage
- 5 layers × 13 animations × 64x64 pixels
- Approximately 2-3 MB per complete armor set
- Negligible impact with modern hardware

### UI Integration

#### Character Sheet (CharacterUI.gd)

Players can:
1. Drag armor from inventory to equipment slot
2. Double-click equipped armor to unequip
3. Right-click equipped armor to unequip
4. See visual preview of equipped items

#### Equipment Slots Display

```
┌─────────────────┐
│    [HEAD]       │  ← Helmet slot
│   [ARMS]        │  ← Armguards slot
│   [CHEST]       │  ← Chest armor slot
│   [LEGS]        │  ← Leg armor slot
│   [FEET]        │  ← Boots slot
└─────────────────┘
```

Equipped items show:
- Item icon
- Item name
- Defense value
- Rarity color border

### Testing Checklist

After making changes:

1. Walk in all 4 directions - character faces correctly without flipping
2. Pick up weapon from vendor - weapon appears
3. Attack in all directions - weapon slashes in correct direction
4. Unequip weapon - weapon disappears
5. Equip armor piece - armor layer appears
6. Unequip armor - armor layer disappears
7. Check equipment UI - All slots display correctly
8. Verify animations sync across all layers

---

## Troubleshooting

### Common Issues

#### Armor equipped but not visible

**Causes:**
- sprite_name doesn't match file name exactly
- Files don't exist in correct animation folders
- File paths are incorrect

**Solutions:**
- Check sprite_name matches file name (case-sensitive)
- Verify files exist: `ResourceLoader.exists()` check
- Review console for error messages

#### Armor layers in wrong order

**Causes:**
- Incorrect Z-index in LPC naming convention
- Wrong layer order in Player.gd setup_lpc_sprite() call

**Solutions:**
- Verify Z-index in file names (015, 020, 060, 130)
- Check layer order matches Z-index order

#### Animation desync

**Causes:**
- Sprite sheets have different frame counts per animation
- Metadata frame counts don't match actual files

**Solutions:**
- Verify all sprite sheets have same frame counts
- Check metadata.json frame counts
- Re-export sprite sheets if necessary

#### Sprites not loading

**Causes:**
- File paths incorrect
- Files not exactly 576x256 (walk), 384x256 (slash), or 384x64 (hurt)
- Files corrupted during export

**Solutions:**
- Check file paths in script
- Verify file dimensions
- Check console for error messages from LPCCharacter
- Re-export from LPC generator

#### Character flipping incorrectly

**Cause:**
- Using flip_h or scale.x = -1

**Solution:**
- Remove all flip_h usage
- LPC sprites have separate rows for each direction
- Use direction rows: 0=north, 1=west, 2=south, 3=east

### Debug Output

When armor is equipped/unequipped:
```
🛡 Armor equipped in slot chest: Copper Plate Torso
   Walk: ✓
   Slash: ✓
👕 Armor unequipped from slot chest: Copper Plate Torso
```

When sprites fail to load:
```
⚠ Could not load armor sprite: res://assets/characters/boots/invalid_name_walk.png
```

### Getting Help

If you're still having issues:

1. Check file paths in your script
2. Verify files are correct dimensions
3. Check console for error messages from LPCCharacter
4. Review this guide's implementation examples
5. Check the local LPC repository for correct sprite structure

---

## License & Attribution

LPC sprites are licensed under multiple licenses:
- GPL 3.0
- CC-BY-SA 3.0
- CC-BY 3.0
- OGA-BY 3.0

### Required Attribution

Create `CREDITS.txt` in your project root with:

```
Liberated Pixel Cup (LPC) Sprites
- Universal LPC Spritesheet Character Generator
- https://github.com/sanderfrenken/Universal-LPC-Spritesheet-Character-Generator
- Multiple contributors (see repository for full list)
- Licenses: GPL 3.0, CC-BY-SA 3.0, CC-BY 3.0, OGA-BY 3.0
```

---

## Future Enhancements

### Planned Features
- [ ] Female armor variants
- [ ] Armor dyeing/recoloring system
- [ ] Armor set bonuses (2pc, 4pc, 5pc)
- [ ] Transmog/appearance override system
- [ ] Enchantment visual effects (glows, particles)
- [ ] Damaged armor states (low durability visual)
- [ ] Additional animation types (run, thrust, spellcast)

### Not Planned
- Weapon/shield sprites in armor system (handled separately)
- Back slot items (cloaks) - LPC has limited cloak support
- Wing/tail attachments - outside core LPC spec

---

## Quick Reference

### Key File Locations

- **Base body sprites**: `assets/characters/BODY_{type}_{animation}.png`
- **Armor tiers**: `assets/characters/armor_tier{X}/standard/`
- **Weapons**: `assets/weapons/{weapon_type}/`
- **NPCs**: `assets/characters/lpc/{npc_name}/`
- **Equipment data**: `data/shop_armor_zone{X}.json`

### Animation Types

- **walk**: 9 frames, 4 directions (576x256)
- **slash**: 6 frames, 4 directions (384x256)
- **hurt**: 6 frames, 1 direction (384x64)
- **idle**: 2 frames, 4 directions (128x256)

### Direction Mapping

- Godot: down, up, left, right
- LPC: south, north, west, east
- Rows: 0=north, 1=west, 2=south, 3=east

### Z-Index Layers

- -1: Weapon (behind, when facing north)
- 0: Base body
- 0.1: Feet armor
- 0.2: Leg armor
- 0.3: Chest armor
- 0.4: Arm armor
- 0.5: Head armor
- 1: Weapon (front, when facing south/east/west)

---

## Summary

The LPC Character System provides a complete, modular solution for 2D character rendering in Godot:

✓ Fully modular character composition
✓ 5-layer armor system with real-time equipment changes
✓ Dynamic weapon rendering with direction-based positioning
✓ 13 standard animations per character/equipment piece
✓ Support for variable sprite sizes (64x64 and 192x192)
✓ Gender-specific sprite support
✓ Drag-and-drop equipment UI
✓ Signal-based reactive updates
✓ Comprehensive asset library with LPC Generator integration

The **Copper Armor Tier 1** serves as the reference template for all future armor implementations. Follow its structure for consistent, maintainable character assets.
