# Armor System Documentation

## Overview

The game features a **fully modular LPC-based armor system** with 5-layer visual rendering. Players can equip individual armor pieces that are rendered as separate sprite layers, allowing for flexible visual customization and gear progression.

---

## System Architecture

### Components

1. **CharacterStats.gd** - Armor data management and equipment state
2. **Player.gd** - Multi-layer armor rendering system
3. **CharacterUI.gd** - Drag-and-drop equipment interface
4. **LPC Sprite Assets** - Animation spritesheets for each armor piece

### Armor Slots (5 Total)

| Slot | Type | Layer Order | Example Item |
|------|------|-------------|--------------|
| `feet` | Boots | Layer 1 (Bottom) | Copper Plate Boots |
| `legs` | Pants/Leg Armor | Layer 2 | Copper Plate Legs |
| `chest` | Shirt/Chest Armor | Layer 3 | Copper Plate Torso |
| `arms` | Arm Armor/Sleeves | Layer 4 | Copper Plate Arms |
| `head` | Helmet/Hat | Layer 5 (Top) | Copper Bascinet Helmet |

---

## Copper Armor Set (Tier 1)

### Tier 1 Template - Complete Reference Implementation

**Location**: `assets/characters/armor_tier1/`

The **Copper Armor Set** serves as the base template for the modular armor system. This is the reference implementation that all future armor tiers should follow.

### Exported Files (Per Animation)

Each armor piece is exported as a separate spritesheet for **13 different animations**:

#### Standard Animations (13)
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

### File Structure

```
assets/characters/armor_tier1/
├── standard/              # Male body type
│   ├── walk/
│   │   ├── 015 feet armour plate male copper.png
│   │   ├── 020 legs armour plate male copper.png
│   │   ├── 060 arms armour plate male copper.png
│   │   ├── 060 torso armour plate male copper.png
│   │   └── 130 hat helmet bascinet adult copper.png
│   ├── run/
│   │   └── (same 5 files)
│   ├── slash/
│   │   └── (same 5 files)
│   └── ... (all 13 animations)
├── female/                # Future: Female body type variants
└── credits/
    └── metadata.json      # Export metadata and configuration
```

### Metadata Tracking

The `metadata.json` file tracks:
- Export timestamp
- Body type (male/female)
- Successfully exported animations
- Failed exports (debugging)
- Frame counts per animation
- Frame size (64x64 pixels)

Example:
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

---

## LPC Naming Convention

### File Naming Format
```
[Z-Index] [Category] [Type] [Gender] [Material].png
```

Examples:
- `015 feet armour plate male copper.png` → Z-index 15, Feet Armor, Plate type, Male, Copper material
- `130 hat helmet bascinet adult copper.png` → Z-index 130, Hat/Helmet, Bascinet style, Adult size, Copper color

### Z-Index Layer Order
- `015` - Feet (boots)
- `020` - Legs (pants)
- `060` - Arms & Torso (worn in same layer in our 5-layer system)
- `130` - Head (helmets/hats)

---

## Equipment System

### Equipping Armor

**CharacterStats.gd** manages equipment state:

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

### Signals

- `armor_equipped(slot: String, armor_item: Dictionary)` - Emitted when armor is equipped
- `armor_unequipped(slot: String, armor_item: Dictionary)` - Emitted when armor is removed

The Player.gd listens to these signals and reloads armor sprites automatically.

---

## Rendering System

### 5-Layer Visual Rendering

**Player.gd** renders armor in 5 distinct layers (bottom to top):

```gdscript
# Layer order (rendered bottom-to-top):
1. Body base sprite
2. Boots (feet slot)
3. Pants (legs slot)
4. Shirt (chest slot)
5. Arms (arms slot)
6. Head (head slot)
7. Weapon (mainhand)
```

### Loading Armor Textures

The system dynamically loads armor sprite sheets based on equipped items:

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

### Animation Synchronization

All 5 armor layers play the same animation frame simultaneously:
- Frame 0 of walk → All layers show walk frame 0
- Frame 3 of slash → All layers show slash frame 3

This ensures perfect visual alignment.

---

## Starting Equipment

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

## UI Integration

### Character Sheet (CharacterUI.gd)

Players can:
1. **Drag** armor from inventory to equipment slot
2. **Double-click** equipped armor to unequip
3. **Right-click** equipped armor to unequip
4. **See visual preview** of equipped items

### Equipment Slots Display

```
┌─────────────────┐
│    [HEAD]       │  ← Helmet slot
│   [ARMS]        │  ← Arm armor slot
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

---

## Item Data Structure

### Armor Item Format

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

### Required Fields

- `name` (String) - Display name
- `slot` (String) - Must be: "head", "chest", "arms", "legs", or "feet"
- `type` (String) - Must be "armor"
- `defense` (int) - Defense value added to total
- `sprite_name` (String) - Base name for sprite files (without animation suffix)

### Optional Fields

- `required_level` (int) - Minimum level to equip
- `set_bonus` (String) - Future: Set item identification
- `special_effect` (String) - Future: Special armor effects

---

## Defense Calculation

Total defense is calculated from all equipped armor:

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

---

## Creating New Armor Tiers

### Future Armor Tiers (Planned)

| Tier | Material | Level Range | Defense Range | Location |
|------|----------|-------------|---------------|----------|
| 1 | Copper | 1-10 | 5-15 per piece | `armor_tier1/` |
| 2 | Bronze | 11-18 | 12-25 per piece | `armor_tier2/` |
| 3 | Iron | 19-24 | 20-35 per piece | `armor_tier3/` |
| 4 | Steel | 25-30 | 30-50 per piece | `armor_tier4/` |
| 5 | Legendary | 30+ | 45-70 per piece | `armor_tier5/` |

### Template Process (Using Tier 1 as Base)

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

---

## Gender Support

### Current Status
- **Male sprites**: Fully implemented (copper tier 1)
- **Female sprites**: Structure ready, not yet exported

### Future Implementation

Female armor will use the same system:
```
armor_tier1/
├── standard/     # Male sprites (current)
└── female/       # Female sprites (future)
    ├── walk/
    └── ... (same 13 animations)
```

Player.gd will check `selected_gender` and load from appropriate folder.

---

## Performance Considerations

### Sprite Loading
- Armor sprites are loaded **on-demand** when equipped
- Uses `ResourceLoader.exists()` checks before loading
- Textures cached by Godot automatically

### Memory Usage
- 5 layers × 13 animations × 64x64 pixels
- Approximately 2-3 MB per complete armor set
- Negligible impact with modern hardware

---

## Debugging

### Debug Output

When armor is equipped/unequipped:
```
🛡️ Armor equipped in slot chest: Copper Plate Torso
   Walk: ✅
   Slash: ✅
👕 Armor unequipped from slot chest: Copper Plate Torso
```

When sprites fail to load:
```
⚠️  Could not load armor sprite: res://assets/characters/boots/invalid_name_walk.png
```

### Common Issues

**Armor equipped but not visible:**
- Check sprite_name matches file name exactly
- Verify files exist in correct animation folders
- Check ResourceLoader.exists() debug output

**Armor layers in wrong order:**
- Verify Z-index in LPC naming convention
- Check layer order in Player.gd setup_lpc_sprite() call

**Animation desync:**
- All sprite sheets must have same frame counts per animation
- Verify metadata.json frame counts match actual files

---

## Future Enhancements

### Planned Features
- [ ] Female armor variants
- [ ] Armor dyeing/recoloring system
- [ ] Armor set bonuses (2pc, 4pc, 5pc)
- [ ] Transmog/appearance override system
- [ ] Enchantment visual effects (glows, particles)
- [ ] Damaged armor states (low durability visual)

### Not Planned
- Weapon/shield sprites (handled separately in weapon system)
- Back slot items (cloaks) - LPC has limited cloak support
- Wing/tail attachments - outside LPC spec

---

## Summary

The **Copper Armor Tier 1** is the **complete reference template** for the modular armor system:

✅ **5 distinct armor pieces** (head, chest, arms, legs, feet)
✅ **13 full animations** per piece (walk, run, slash, etc.)
✅ **LPC Universal Generator** workflow established
✅ **Metadata tracking** system in place
✅ **Fully functional equip/unequip** system
✅ **Multi-layer rendering** working
✅ **UI integration** complete (drag-and-drop)
✅ **Defense calculation** implemented
✅ **Signal-based** reactive updates

**All future armor tiers should follow this exact structure.**
