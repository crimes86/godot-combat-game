# Godot Item System Handoff

This document explains how the Ashbane forge system works and what the Godot client needs to implement.

## Overview

The forge system converts achievements into in-game items. The **backend computes all item properties** at forge time and stores them. Godot simply fetches pre-computed item data and renders it.

```
Achievement -> Backend checks mapping -> Item selected -> ForgedAchievement stored -> Godot fetches & renders
```

## Key Design Principles

1. **Items are cosmetic only** - No gameplay stat bonuses. Visual flair only.
2. **Explicit mappings** - Specific achievements map to specific items via `achievement_mappings`.
3. **LPC sprite system** - All items use Liberated Pixel Cup standard animations.
4. **Pre-computed everything** - Godot doesn't calculate stats, just renders what backend provides.

---

## Achievement → Item Mapping

Achievements are explicitly mapped to items in `data/items.json`:

```json
"achievement_mappings": {
  "374320:THE_DARK_SOUL": "coiled_sword",
  "374320:NAMELESS_KING": "dragonslayer_swordspear",
  "1245620:SHARDBEARER_MALENIA": "hand_of_malenia",
  "discord:NITRO_SUBSCRIBER": "discord_nitro_badge"
}
```

**Key format:** `app_id:api_name`

### Selection Priority
1. **Explicit mapping** - If `app_id:api_name` exists in mappings, use that item
2. **Theme match** - Fall back to random item from same game theme
3. **Generic fallback** - Use basic item if nothing else matches

### API: Get All Mappings
`GET /api/catalog/mappings` returns all mappings with full item details:

```json
{
  "total_mappings": 20,
  "needs_sprites": 18,
  "ready": 2,
  "by_theme": {"dark_souls": 4, "elden_ring": 4, ...},
  "by_weapon_type": {"sword": 6, "katana": 3, ...},
  "mappings": [
    {
      "achievement_key": "374320:THE_DARK_SOUL",
      "app_id": "374320",
      "api_name": "THE_DARK_SOUL",
      "item_id": "coiled_sword",
      "needs_sprites": true,
      "item": {
        "item_id": "coiled_sword",
        "item_name": "Coiled Sword",
        "item_type": "weapon",
        "weapon_type": "sword",
        "theme": "dark_souls",
        "base_rarity": "legendary",
        "visuals": {
          "sprite_folder": "weapons/coiled_sword",
          "effect": "ember_trail",
          "glow_color": "#FF6A00"
        }
      }
    }
  ]
}
```

Use this endpoint to see exactly what assets need to be created.

---

## Asset Workflow

### Where Assets Live

```
Backend (Web Dashboard)              Godot
─────────────────────────           ──────
static/items/
  icons/                            (import from backend or duplicate)
    coiled_sword.png
    hand_of_malenia.png
  sprites/
    weapons/
      coiled_sword/
        idle.png
        slash.png
      hand_of_malenia/
        idle.png
        slash.png
    armor/
      ...
```

### Asset Creation Flow

1. **Godot engineer creates sprites** using LPC format
2. **Export to backend**: Copy sprites to `static/items/sprites/`
3. **Update items.json**: Set `has_sprites: true` for completed items
4. **Web dashboard**: Serves sprites via `/static/items/sprites/...`
5. **Godot client**: Can use same sprites or keep separate copy

### Item Visuals in items.json

Each item specifies where its assets are:

```json
{
  "item_id": "coiled_sword",
  "visuals": {
    "icon_url": "/static/items/icons/coiled_sword.png",
    "sprite_folder": "weapons/coiled_sword",
    "effect": "ember_trail",
    "glow_color": "#FF6A00"
  },
  "has_sprites": false,
  "has_icon": false
}
```

- `icon_url`: Full path for web dashboard display
- `sprite_folder`: Relative path under `static/items/sprites/`
- `has_sprites`: Set to `true` once sprites are created
- `has_icon`: Set to `true` once icon is created

### Creating a New Item Asset

1. Check `/api/catalog/mappings` for items with `needs_sprites: true`
2. Create sprites in LPC format:
   - `idle.png` (required)
   - `slash.png` (required for weapons)
   - `thrust.png` (optional)
3. Export to `static/items/sprites/{sprite_folder}/`
4. Create icon (64x64 or 128x128 PNG)
5. Export to `static/items/icons/{item_id}.png`
6. Update `items.json`: set `has_sprites: true`, `has_icon: true`

---

## Weapon Types (18 Total)

These weapon types are defined in `scripts/weapons/WeaponAnimationData.gd` and `scripts/systems/ForgeItemDB.gd`.

### Core Types (7) - Have animation data in Godot
| Type | Style | Speed | Range | Notes |
|------|-------|-------|-------|-------|
| `sword` | balanced | medium | 100px | Default/fallback, longswords |
| `dagger` | fast | ultra-fast | 75px | High attack speed |
| `axe` | heavy | slow | 110px | High damage, includes waraxe |
| `mace` | crushing | medium | 100px | Aliases: `club`, `hammer`, `warhammer` |
| `spear` | thrusting | medium | 140px | Longest reach |
| `rapier` | precise | fast | 115px | Precision strikes |
| `staff` | casting | medium | 125px | Magic/healing weapons |

### Extended Types (12) - Fallback to core animations
| Type | Fallback | Notes |
|------|----------|-------|
| `greatsword` | sword | Two-handed swords |
| `katana` | sword | Curved Japanese sword |
| `saber` | sword | Curved cavalry sword |
| `scimitar` | sword | Curved Middle-Eastern sword |
| `halberd` | spear | Ornate polearm, axe+spear |
| `pike` | spear | Extra-long spear |
| `trident` | spear | Three-pronged polearm |
| `flail` | mace | Chain weapon |
| `scythe` | spear | Farming/reaper weapon |
| `bow` | staff | Standard bow |
| `crossbow` | staff | Mechanical ranged |
| `gun` | (special) | Uses Skorpio body swap - see "Gun Weapons" section |

### Aliases (map to core types)
```
club → mace
hammer → mace
warhammer → mace
longsword → sword
waraxe → axe
```

---

## API Endpoints

### GET /api/me/forged-items
Returns all forged items for the current user. **This is the main endpoint Godot uses.**

```json
{
  "total": 5,
  "forged_items": [
    {
      "token_id": 12345,
      "item_id": "coiled_sword",
      "item_name": "Ancient Mythic Coiled Sword",
      "item_type": "weapon",
      "weapon_type": "sword",
      "item_rarity": "legendary",
      "effect_name": "ember_trail",
      "effect_intensity": 0.85,
      "glow_color": "#FF6A00",
      "effort_tier": "Exceptional",
      "vintage_years": 10,
      "is_secret": false,
      "forged_at": "2025-12-08T15:30:00Z",
      "source": {
        "achievement_name": "The Dark Soul",
        "achievement_icon": "https://...",
        "app_id": "374320"
      }
    }
  ]
}
```

### GET /api/catalog/items
Returns the full item catalog. Useful for browsing/previewing.

Query params:
- `item_type`: Filter by weapon/armor/shield/accessory
- `theme`: Filter by dark_souls/steam/etc.
- `available_only`: Only items with sprites ready

### POST /api/forge/preview?achievement_id=123
Preview what item an achievement would forge into (before forging).

### GET /api/me/forge-status
Get summary of forgeable vs already-forged achievements.

---

## Item Properties Explained

### effect_intensity (0.0 - 1.0)
Controls particle/glow strength. Computed from `effort_score`:
- 0.0 = No effect (trivial achievement)
- 0.5 = Standard particles
- 1.0 = Maximum particles/glow (extremely hard achievement)

Formula: `0.3 + (effort_score/100)^0.8 * 0.7`

### effect_name
Particle effect to apply. Defined in `scripts/systems/ForgeVisualEffects.gd`. Themed by game:

**By Game Theme:**
| Game | app_id | Effects |
|------|--------|---------|
| Elden Ring | 1245620 | `erdtree_blessing`, `golden_sparkle`, `moonlight_aura`, `gravity_particles` |
| Dark Souls 3 | 374320 | `ember_trail`, `ember_glow`, `flame_idle_glow`, `wolf_blood_aura` |
| Hollow Knight | 367520 | `void_particles`, `void_trail`, `void_aura`, `shadow_tendrils` |
| Hades | 1145360 | `underworld_flame`, `blood_red_glow`, `infernal_glow`, `divine_glow` |
| Stardew Valley | 413150 | `nature_sparkle`, `golden_sparkle`, `stardust_trail`, `healing_aura` |
| Terraria | 105600 | `terra_beam`, `green_glow`, `eerie_glow` |
| Sekiro | 814380 | `crimson_slash`, `death_kanji`, `blood_mist` |
| Witcher 3 | 292030 | `silver_gleam`, `wolf_school_glow`, `danger_sense` |

**By Effort Tier:**
- `exceptional_aura` - Orange pulsing (effort 81+)
- `superior_trail` - Purple trail (effort 61-80)
- `enhanced_glow` - Blue glow (effort 41-60)
- `standard_particles` - Green particles (default)

### glow_color
Hex color for item glow outline. Matches game theme (defined in backend):

| Game | app_id | Color |
|------|--------|-------|
| Elden Ring | 1245620 | `#FFD700` (gold) |
| Dark Souls 3 | 374320 | `#FF6A00` (ember orange) |
| Hollow Knight | 367520 | `#1A0033` (void purple) |
| Hades | 1145360 | `#FF4444` (blood red) |
| Stardew Valley | 413150 | `#66FF66` (nature green) |
| Terraria | 105600 | `#00FF80` (terra green) |
| Sekiro | 814380 | `#CC0000` (crimson) |
| Witcher 3 | 292030 | `#E6B833` (medallion amber) |
| Discord | discord | `#5865F2` (blurple) |
| Generic | - | `#888888` (gray) |

### effort_tier
Human-readable effort label:
| Score Range | Tier |
|-------------|------|
| 90-100 | Exceptional |
| 75-89 | Superior |
| 60-74 | Remarkable |
| 45-59 | Notable |
| 30-44 | Solid |
| 15-29 | Modest |
| 0-14 | Common |

### vintage_years
Years since achievement was unlocked. Affects name prefix:
| Years | Prefix |
|-------|--------|
| 10+ | Ancient |
| 7-9 | Venerable |
| 5-6 | Veteran's |
| 3-4 | Seasoned |
| 1-2 | Proven |
| 0 | (none) |

### is_secret
True if the original achievement was hidden/secret. Adds "Occult" prefix.

---

## Item Name Generation

Names are generated with prefixes based on properties:

```
[Vintage Prefix] [Secret Prefix] [Base Name]
```

**Note:** Rarity prefixes are disabled for cleaner item names. Only vintage and secret prefixes apply.

Examples:
- `Ancient Coiled Sword` (10yr old achievement)
- `Occult Frost Spear` (secret/hidden achievement)
- `Veteran's Hand of Malenia` (5yr old achievement)
- `Adamant Rail` (new achievement, no prefixes)

Active prefixes:
| Type | Prefix | Threshold |
|------|--------|-----------|
| Vintage | Ancient | 10+ years |
| Vintage | Venerable | 7+ years |
| Vintage | Veteran's | 5+ years |
| Vintage | Seasoned | 3+ years |
| Vintage | Proven | 1+ year |
| Secret | Occult | Hidden achievement |

---

## Sprite Folder Structure

Forged items use LPC sprite format. Paths defined in `scripts/systems/ForgeItemDB.gd`:

```
assets/equipment/forged/
    weapons/
        coiled_sword/
            walk.png      # 9 frames x 4 directions (576x256)
            slash.png     # 6 frames x 4 directions (384x256)
            thrust.png    # 8 frames x 4 directions (512x256)
            hurt.png      # 6 frames x 1 direction (384x64)
        hand_of_malenia/
            walk.png
            slash.png
            ...
    armor/
        head/
            elden_lord/
                walk.png
                slash.png
                ...
        chest/
            grandmaster_wolf/
                ...
    capes/
        shade_cloak/
            ...
    shields/
        eye_shield/
            walk.png      # Shields only need walk animation

assets/icons/forged/
    weapons/
        coiled_sword.png      # 64x64 icon
        hand_of_malenia.png
    armor/
        elden_lord_crown.png
    accessories/
        void_heart.png
```

### Required Animations (LPC Format)
- **Weapons**: `walk.png`, `slash.png` (minimum), `thrust.png`, `hurt.png` (optional)
- **Armor**: `walk.png`, `slash.png`, `thrust.png`, `hurt.png`
- **Shields**: `walk.png` only
- **Capes**: `walk.png`, `slash.png`, `thrust.png`, `hurt.png`

### Icon Standards
- Size: 64x64 PNG with transparency
- Weapons: Diagonal ~45°, tip pointing upper-right
- Armor/Shields: Upright, centered
- Min padding: 4px from edge

Items without sprites have `has_sprites: false` and fall back to emoji placeholders in UI.

---

## Manifest Generator

When adding new items:

1. Create sprite folder with animations
2. Run: `python tools/generate_item_manifest.py --sprites-dir path/to/sprites`
3. Tool scans folders and updates `data/items.json`
4. Manually edit `items.json` to set rarity, theme, effects

The generator preserves manual edits - it only updates sprite paths and `has_sprites` status.

---

## Implementation Status (Godot)

### ✅ Completed
- [x] `ForgeItemManager.gd` - Fetches `/api/me/forged-items` on login
- [x] `ForgeItemDB.gd` - Achievement → Item mapping database
- [x] `ForgeVisualEffects.gd` - 60+ effect definitions with EFFECT_CONFIGS
- [x] `WeaponAnimationData.gd` - Weapon type fallbacks for animations
- [x] `Armory.gd` - Forge UI with item cards, ownership display, detail panel

### 🔲 Pending (needs backend API)
- [ ] Actual `/api/me/forged-items` endpoint (currently returns empty/404)
- [ ] `/api/forge/claim` endpoint for forging items

### 🔲 Pending (needs assets)
- [ ] LPC sprites for forged weapons (see `assets/equipment/forged/`)
- [ ] 64x64 icons for forged items (see `assets/icons/forged/`)

### 🔲 Future Polish
- [ ] Apply `glow_color` outline shader to equipped items
- [ ] Particle systems rendering for `effect_name` in-game
- [ ] Forge preview before claiming
- [ ] In-world Forge object interaction

---

## Testing

Test items are included in `data/items.json`:
- `coiled_sword` - Dark Souls theme weapon
- `bonfire_ember` - Dark Souls accessory
- `steam_badge` - Steam theme accessory
- Various generic items

Set `has_sprites: true` on test items even without real sprites to test the data flow.

---

## Key Files

**Godot:**
- `scripts/systems/ForgeItemManager.gd` - Fetches/caches forged items from backend
- `scripts/systems/ForgeItemDB.gd` - Achievement → Item mappings, enums
- `scripts/systems/ForgeVisualEffects.gd` - Effect rendering (EFFECT_CONFIGS)
- `scripts/weapons/WeaponAnimationData.gd` - Weapon animation data & fallbacks
- `scripts/ui/Armory.gd` - Forge UI implementation

**Documentation:**
- `docs/FORGE_AND_Ashbane.md` - Full system spec, backend standardization
- `docs/LPC_GUIDE.md` - LPC sprite format, asset creation guide
- `.claude/CLAUDE.md` - Asset folder structure

**Assets:**
- `assets/equipment/forged/` - Forged item sprites
- `assets/icons/forged/` - 64x64 item icons
- LPC Generator: https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/

---

## Sprite Tinting Tool

For creating colored variants of base weapons, use the `forge_sprite_tinter.py` tool:

```bash
# Preview single item
python tools/forge_sprite_tinter.py --preview moonveil

# Generate single item sprites
python tools/forge_sprite_tinter.py --generate moonveil

# Generate all missing forged sprites
python tools/forge_sprite_tinter.py --generate-all

# Generate comparison image showing all tint methods
python tools/forge_sprite_tinter.py --compare moonveil
```

**Tinting Methods:**
| Method | Use Case |
|--------|----------|
| `simple` | Basic color multiply overlay |
| `additive` | Tint + brightness boost (glowing effect) |
| `hue_shift` | Rotate hue toward target color (preserves shading) |
| `hybrid` | Hue shift + additive glow based on rarity (recommended) |

Configure items in `FORGED_ITEMS` dict in the script:
```python
"moonveil": {
    "weapon_class": "katana",
    "glow_color": "#6495ED",  # Moonlight blue
    "rarity": "legendary",
    "game": "Elden Ring",
},
```

---

## Edge Case: Gun Weapons (Body Swap System)

Gun weapons require special handling because LPC sprites don't have a "holding gun" body pose. We use the **Skorpio SciFi Sprite Pack** body with arms extended for shooting.

### How It Works

1. **Normal LPC body** is used for idle animations
2. **Skorpio body** is swapped in during walk animations (arms extended for gun)
3. **Clothing layers** (pants, shirt, hair) render on top of whichever body is showing
4. **Gun weapon sprite** renders as a separate layer

### Files Involved

| File | Purpose |
|------|---------|
| `assets/characters/body_gun_pose/walk.png` | Skorpio MaleWalkShoot body (576x256) |
| `assets/equipment/weapons/gun/walk.png` | Base gun sprite overlay |
| `assets/equipment/forged/weapons/adamant_rail/walk.png` | Tinted forged gun |
| `scripts/SimpleLPCSprite.gd` | Gun body swap logic |
| `scripts/player/Player.gd` | Gun weapon detection |
| `scripts/systems/ForgeItemDB.gd` | GUN weapon class enum |

### Adding a New Gun Weapon

1. **Add to ForgeItemDB.gd** with `WeaponClass.GUN`:
   ```gdscript
   "hades_1145360_ADAMANT_RAIL": {
       "item_id": "adamant_rail",
       "item_name": "Adamant Rail",
       "weapon_class": WeaponClass.GUN,
       # ...
   },
   ```

2. **Generate tinted sprites**:
   ```bash
   python tools/forge_sprite_tinter.py --generate adamant_rail
   ```

3. **The system auto-detects** gun weapons in Player.gd:
   ```gdscript
   var gun_weapon_types = ["gun", "rifle", "pistol", "shotgun", "railgun"]
   if weapon_type in gun_weapon_types:
       # Load Skorpio gun pose body
       character_sprite.setup_gun_walk_animations(gun_body_walk_tex)
   ```

### Technical Details

**SimpleLPCSprite.gd** handles the body swap:
- `gun_body_sprite`: Separate AnimatedSprite2D for Skorpio body
- `setup_gun_walk_animations()`: Creates walk animations on gun body layer
- `_set_body_layers_visible()`: Uses `self_modulate.a` (not `modulate`) to hide body without hiding children
- Clothing layers sync to gun_body_sprite frames when it's visible

**Key insight**: Use `self_modulate` instead of `modulate` when hiding the body, otherwise all child sprites (clothing) become invisible too.

### Limitations

- Gun weapons only have walk animation (no slash/attack pose from Skorpio pack)
- Only one gun body pose available (MaleWalkShoot) - used for both male/female
- Hurt animation uses regular LPC body (no gun pose hurt exists)
