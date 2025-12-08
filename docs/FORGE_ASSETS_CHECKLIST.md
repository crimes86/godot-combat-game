# Forge Assets Checklist

This document tracks all LPC-compatible assets needed for the Forge Item system.

## Asset Generation Tool
Use the [Universal LPC Character Generator](https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/) for base sprites.

## Directory Structure
```
assets/
├── equipment/forged/           # Forged item sprites
│   ├── weapons/
│   │   └── {item_name}/
│   │       ├── walk.png
│   │       ├── slash.png
│   │       ├── thrust.png
│   │       └── hurt.png
│   ├── armor/
│   │   ├── head/{item_name}/
│   │   ├── chest/{item_name}/
│   │   ├── legs/{item_name}/
│   │   ├── hands/{item_name}/
│   │   └── feet/{item_name}/
│   ├── capes/{item_name}/
│   ├── shields/{item_name}/
│   └── tools/{item_name}/
│
└── icons/forged/               # Inventory icons (64x64)
    ├── weapons/
    ├── armor/
    ├── accessories/
    ├── capes/
    ├── shields/
    └── tools/
```

---

## Priority 1: Elden Ring (Most Popular)

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Margit's Shackle | Accessory | Common | Icon only | [ ] |
| Grafted Blade Greatsword | Weapon (Greatsword) | Common | Greatsword + golden tint | [ ] |
| Carian Royal Crown | Head Armor | Uncommon | Crown/tiara + blue glow | [ ] |
| Starscourge Greatswords | Weapon (Greatsword) | Uncommon | Paired swords + purple | [ ] |
| Hand of Malenia | Weapon (Katana) | Rare | Katana + red/pink petals | [ ] |
| Elden Armory Pauldrons | Chest Armor | Epic | Plate shoulder + gold | [ ] |
| Elden Lord's Crown | Head Armor | Legendary | Ornate crown + golden rays | [ ] |

### Elden Ring Visual Effects
- `golden_glow` - Subtle gold particle aura
- `moonlight_aura` - Blue/white ethereal glow
- `gravity_particles` - Purple floating rocks
- `purple_glow` - Purple tint on weapon
- `scarlet_rot_trail` - Red particles while moving
- `flower_petals` - Pink petals floating
- `golden_sparkle` - Sparkle particles
- `erdtree_blessing` - Golden light rays
- `golden_leaves` - Falling leaf particles
- `light_rays` - Volumetric light beams

---

## Priority 2: Dark Souls 3

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Coiled Sword Fragment | Accessory | Common | Icon only | [ ] |
| Farron Greatsword | Weapon (Greatsword) | Uncommon | Greatsword + wolf motif | [ ] |
| Dragonslayer Swordspear | Weapon (Spear) | Rare | Ornate spear + lightning | [ ] |
| Coiled Sword | Weapon (Sword) | Legendary | Twisted sword + fire | [ ] |

### Dark Souls 3 Visual Effects
- `ember_glow` - Orange/red pulsing glow
- `wolf_blood_aura` - Blue-gray misty aura
- `lightning_crackle` - Electric arcs
- `storm_particles` - Wind/cloud particles
- `ember_trail` - Fire particles while moving
- `flame_idle_glow` - Fire effect when standing
- `heat_distortion` - Screen distortion shader

---

## Priority 3: Stardew Valley

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Farmer's Straw Hat | Head Armor | Common | Straw hat | [ ] |
| Master Farmer's Hoe | Weapon (Tool) | Uncommon | Golden hoe/pickaxe | [ ] |
| Stardrop Pendant | Accessory | Epic | Icon only + particles | [ ] |
| Prairie King's Crown | Head Armor | Legendary | Pixel art crown | [ ] |

### Stardew Valley Visual Effects
- `golden_sparkle` - Gold star particles
- `stardust_trail` - Rainbow sparkle trail
- `healing_aura` - Green healing particles
- `pixel_sparkle` - 8-bit style sparkles
- `retro_trail` - Pixelated motion trail

---

## Priority 4: Hollow Knight

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Pure Nail | Weapon (Sword) | Uncommon | Thin sword + white | [ ] |
| Shade Cloak | Cape | Rare | Black flowing cape | [ ] |
| Void Heart Charm | Accessory | Legendary | Icon only | [ ] |

### Hollow Knight Visual Effects
- `void_particles` - Black/purple particles
- `void_trail` - Dark smoke trail
- `shadow_dash` - Blur on movement
- `void_aura` - Dark pulsing aura
- `shadow_tendrils` - Wispy dark extensions
- `dark_burst` - Explosion of darkness

---

## Priority 5: Hades

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Stygian Blade | Weapon (Sword) | Common | Red-tinted sword | [ ] |
| Adamant Rail | Weapon (Ranged) | Uncommon | Crossbow/gun | [ ] |
| Prince's Laurel Crown | Head Armor | Epic | Laurel wreath | [ ] |

### Hades Visual Effects
- `blood_red_glow` - Red ambient glow
- `infernal_glow` - Orange/red fire
- `divine_glow` - Golden godly light
- `laurel_particles` - Green leaves floating

---

## Priority 6: Terraria

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Eye of Cthulhu Shield | Shield | Common | Eye-themed shield | [ ] |
| Terra Blade | Weapon (Sword) | Legendary | Green glowing sword | [ ] |

### Terraria Visual Effects
- `eerie_glow` - Unsettling red/purple
- `terra_beam` - Green projectile trail
- `green_glow` - Nature green aura
- `sword_projectile` - Ranged swing effect

---

## Priority 7: Sekiro

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Gyoubu's Broken Horn Spear | Weapon (Spear) | Common | Ornate spear | [ ] |
| Mortal Blade | Weapon (Katana) | Legendary | Red katana | [ ] |

### Sekiro Visual Effects
- `crimson_slash` - Red slash trail
- `death_kanji` - Japanese character overlay
- `blood_mist` - Red particle mist

---

## Priority 8: The Witcher 3

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Witcher's Silver Sword | Weapon (Sword) | Common | Silver-tinted sword | [ ] |
| Grandmaster Wolf Chest | Chest Armor | Legendary | Ornate medium armor | [ ] |

### Witcher 3 Visual Effects
- `silver_gleam` - Silver reflection
- `wolf_school_glow` - Amber medallion glow
- `danger_sense` - Alert particles

---

## LPC Generator Notes

### Weapon Categories Available
- Swords (longsword, shortsword, rapier)
- Daggers
- Spears/Polearms
- Maces/Hammers
- Staves
- Bows/Crossbows
- Axes

### Armor Categories Available
- Head: Helmets, crowns, hats, hoods
- Chest: Plate, chain, leather, robes
- Legs: Plate, chain, leather, robes
- Hands: Gauntlets, gloves, bracers
- Feet: Boots, shoes, greaves

### Color Variations
Use generator's recolor options for:
- Gold/golden tints
- Silver tints
- Red/crimson
- Blue/azure
- Purple/void
- Green/nature
- Black/shadow

### Special Effects (In-Game)
Effects are implemented via GPUParticles2D and shaders in Godot, not in the LPC sprites themselves.

---

## Generation Workflow

1. **Open LPC Generator** with base character
2. **Select equipment type** matching the item
3. **Apply color/tint** matching item rarity and theme
4. **Export sprite sheets** (all animations)
5. **Create icon** (64x64 crop or custom)
6. **Place in correct directory** per structure above
7. **Mark as complete** in this checklist

---

## Asset Counts Summary

| Game | Common | Uncommon | Rare | Epic | Legendary | Total |
|------|--------|----------|------|------|-----------|-------|
| Elden Ring | 2 | 2 | 1 | 1 | 1 | 7 |
| Dark Souls 3 | 1 | 1 | 1 | 0 | 1 | 4 |
| Stardew Valley | 1 | 1 | 0 | 1 | 1 | 4 |
| Hollow Knight | 0 | 1 | 1 | 0 | 1 | 3 |
| Hades | 1 | 1 | 0 | 1 | 0 | 3 |
| Terraria | 1 | 0 | 0 | 0 | 1 | 2 |
| Sekiro | 1 | 0 | 0 | 0 | 1 | 2 |
| The Witcher 3 | 1 | 0 | 0 | 0 | 1 | 2 |
| **TOTAL** | **8** | **6** | **3** | **3** | **7** | **27** |

### By Asset Type
- Weapons: 15
- Head Armor: 6
- Chest Armor: 2
- Capes: 1
- Shields: 1
- Accessories (icon only): 4
- **Full sprite sheets needed**: 23
- **Icons only**: 4
