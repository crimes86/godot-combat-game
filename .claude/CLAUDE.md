# Project Guidelines for Claude

## Documentation Reference

When working on specific systems, consult these docs:

| Topic | Document |
|-------|----------|
| **Forge System** | |
| Item creation workflow | `docs/ACHIEVEMENT_ITEM_CREATION_PROCESS.md` |
| Achievement shortlist | `docs/FORGE_ACHIEVEMENT_SHORTLIST.md` |
| Item philosophy & design | `docs/FORGE_ITEM_PHILOSOPHY.md` |
| Item effects & abilities | `docs/FORGE_ITEM_EFFECTS.md` |
| Trading & economy | `docs/FORGE_ECONOMY_DESIGN.md` |
| Bridge system (NFT) | `docs/FORGE_BRIDGE_SYSTEM.md` |
| Provenance tracking | `docs/FORGE_PROVENANCE_SYSTEM.md` |
| Forged weapon stats | `docs/FORGED_WEAPON_STATS.md` |
| **Gameplay Systems** | |
| Combat mechanics | `docs/COMBAT_SYSTEMS.md` |
| Chunk spawning | `docs/CHUNK_AND_SPAWNING.md` |
| Inventory & loot | `docs/INVENTORY_AND_LOOT.md` |
| Trading hub | `docs/TRADING_HUB_DESIGN.md` |
| World tree system | `docs/WORLD_TREE_SYSTEM.md` |
| **Art & Assets** | |
| LPC sprite guide | `docs/LPC_GUIDE.md` |
| Asset design guide | `docs/ASSET_DESIGN_GUIDE.md` |
| Godot item handoff | `docs/GODOT_ITEM_HANDOFF.md` |
| Gun weapon spec | `docs/GUN_WEAPON_SPEC.md` |
| **Architecture** | |
| System architecture | `docs/ARCHITECTURE.md` |
| Server architecture | `docs/SERVER_ARCHITECTURE.md` |
| Shard system (multi-server) | `docs/SHARD_SYSTEM.md` |
| Performance guide | `docs/PERFORMANCE.md` |
| API contract | `docs/API_CONTRACT.md` |
| **Rules & Process** | |
| Golden rules (immutable) | `docs/GOLDEN_RULES.md` |
| Provider roadmap | `docs/PROVIDER_ROADMAP.md` |
| Itch.io release | `docs/ITCH_RELEASE_GUIDE.md` |

---

## Asset Structure (Refactored Dec 2024)

All game assets should follow this canonical structure. Do NOT create new root-level folders.

```
assets/
├── audio/                      # ALL audio files
│   ├── music/                  # Background music tracks
│   └── sfx/                    # Sound effects (consolidated from old sounds/)
│       ├── ambient/            # Campfire, wolf howls, etc.
│       ├── combat/             # Hits, reactions, weapon sounds
│       │   ├── hits/
│       │   ├── reactions/
│       │   ├── weapons/
│       │   └── weapon_swings/
│       ├── footsteps/          # Player, skeleton, wolf steps
│       ├── player/             # Player hurt, death, healing sounds
│       ├── tree/               # Chopping, falling sounds
│       └── ui/                 # Button clicks, inventory, quest sounds
│
├── characters/                 # Character sprites (players, enemies)
│   ├── body_male/              # Male player body
│   ├── body_female/            # Female player body
│   ├── body_skeleton/          # Skeleton enemy body
│   ├── head_male/              # Male head options
│   ├── head_female/            # Female head options
│   ├── hair_male/              # Male hair options
│   ├── hair_female/            # Female hair options
│   ├── shadow/                 # Character shadow sprites
│   ├── enemies/                # ALL enemy sprites
│   │   ├── wolf-*.png          # Wolf directional sprites
│   │   ├── skeleton.png        # Basic skeleton
│   │   └── zombie.png          # Zombie enemy
│   ├── skeletal_guardian/      # Elite skeleton variants
│   ├── armor_tier1/            # Character armor definition data
│   ├── equipment/              # Player equipment sprites
│   ├── lpc/                    # LPC character templates (blacksmith, etc.)
│   │
│   # STARTER CLOTHES (flat file structure):
│   ├── pants/                  # green_pants_*.png, copper_plate_*.png
│   ├── pants_female/           # Female variants
│   ├── shirt/                  # white_shirt_*.png, copper_plate_*.png
│   ├── shirt_female/
│   ├── boots/
│   ├── boots_female/
│   ├── arms/
│   ├── arms_female/
│   ├── hands/
│   ├── hands_female/
│   ├── head/                   # Head armor pieces
│   ├── head_female_armor/
│   ├── head_leather_hat/       # Leather hat variants
│   ├── torso_leather/          # Leather torso armor
│   └── legs_greenish/          # Green leg variants
│
├── equipment/                  # All equippable items
│   ├── armor/                  # Armor sets
│   │   ├── starter/            # Starting armor pieces
│   │   ├── tier1/              # Zone 1 armor (copper plate set)
│   │   │   ├── chest/copper_plate/standard/
│   │   │   ├── legs/copper_plate/standard/
│   │   │   └── ...
│   │   └── head/               # Head armor pieces
│   ├── weapons/                # Combat weapons
│   │   ├── sword/
│   │   ├── mace/
│   │   ├── spear/
│   │   ├── staff/
│   │   ├── dagger/
│   │   ├── halberd/
│   │   ├── katana/
│   │   ├── rapier/
│   │   ├── saber/
│   │   └── scimitar/
│   ├── tools/                  # Harvesting tools
│   │   ├── axe/
│   │   └── pickaxe/
│   ├── shields/
│   └── forged/                 # Forged item icons (from Mantle achievements)
│
├── environment/                # World objects, terrain, props
│   └── wasteland/              # Zone 1 environment assets
│
├── icons/                      # UI icons for items, abilities
│   └── forged/                 # Forge system icons
│
├── npcs/                       # Non-enemy NPCs (merchants, quest givers)
│
├── sprites/                    # Additional sprite assets
│   └── lpc/                    # LPC sprite templates
│
└── ui/                         # UI elements, frames, buttons
```

## LPC Sprite Naming Convention

For LPC-compatible sprites in equipment/armor/, use this folder structure:
```
[slot]/[item_name]/standard/
├── walk.png      # 9 frames x 4 directions (576x256)
├── slash.png     # 6 frames x 4 directions (384x256)
├── thrust.png    # 8 frames x 4 directions (512x256)
└── hurt.png      # 6 frames x 1 direction (384x64)
```

For starter clothes in characters/, use flat naming:
```
[item_name]_walk.png
[item_name]_slash.png
[item_name]_thrust.png
[item_name]_hurt.png
```

## Code Conventions

- Don't commit until user has tested changes in Godot
- Equipment loading should use `assets/equipment/` paths
- Enemy loading should use `assets/characters/enemies/` paths
- Audio loading should use `assets/audio/` paths (sfx/ or music/)

## Potential Issues After Refactor

If assets fail to load after the Dec 2024 refactor, check:

1. **Sounds not playing**: Paths changed from `assets/sounds/` to `assets/audio/sfx/`
2. **Weapons not showing**: Paths changed from `assets/weapons/` to `assets/equipment/weapons/`
3. **Tools not loading**: Paths changed from `assets/tools/` to `assets/equipment/tools/`
4. **Armor not loading**: Paths changed from `assets/armor/zone1/` to `assets/equipment/armor/tier1/`

Key files with path references (check these first):
- `scripts/systems/sound_manager.gd` - All sound effects
- `scripts/SimpleLPCSprite.gd` - Equipment sprites during combat
- `scripts/player/Player.gd` - Weapon and clothing loading
- `scripts/enemies/Enemy.gd` - Enemy equipment
- `scripts/systems/ItemIconGenerator.gd` - Inventory icons

## When Adding New Assets

1. Check this structure FIRST before creating folders
2. Place assets in the correct category
3. Follow LPC naming conventions for sprites
4. Update relevant loader scripts if paths change

## Forge Icon Standards

When creating or modifying forge icons (`assets/icons/forged/`):

**Spec:** 64x64 PNG, RGBA, centered content, min 4px padding

**Orientation:**
- Weapons: Diagonal 45°, tip pointing **upper-right**
- Armor/Shields: Upright, centered
- Accessories: Natural, centered

**Validation tool:** `assets/icons/forged/icon_standards.py`

```bash
python icon_standards.py --validate    # Check compliance
python icon_standards.py --fix         # Auto-center all
python icon_standards.py --orient weapons/x.png upper-right  # Fix orientation
python icon_standards.py --preview     # Generate shop grid preview
```

See `docs/FORGE_ASSET_GENERATION_GUIDE.md` for full details

## LPC Helmet Layers

Helmets from the LPC sprite generator can include **separate layers** for visors, wings, and other enhancements. When processing helmets:

**Layer Structure:**
- Base helmet layer (e.g., `130 xeon_helmet__gold_.png.png`)
- Enhancement layers (e.g., `139 helmet_wings__gold_.png.png`, visor layers, etc.)

**Processing Approach:**
1. Extract all layers from the zip file
2. Tint each layer separately if needed (base color, accent color, etc.)
3. Composite layers together in order (base first, enhancements on top)
4. Save the final composited sprite

**Tinting:**
- Use Python PIL to tint grayscale/white sprites to target colors
- Preserve brightness/shading by multiplying color by (brightness/255)
- Each layer can have a different tint color for multi-color effects

**Example composite code:**
```python
from PIL import Image
result = Image.new('RGBA', base.size, (0, 0, 0, 0))
result.paste(base_tinted, (0, 0), base_tinted)
result.paste(wings_tinted, (0, 0), wings_tinted)  # Wings on top
```

## Forged Item Completion

**Full Process:** `docs/ACHIEVEMENT_ITEM_CREATION_PROCESS.md`

Key sections for checking completion:
- **Phase 4.3** - Update `has_sprites`/`has_icon` in items.json after asset creation
- **Phase 9.1** - Godot completion checklist (lines 665-690)
- **Phase 11.1** - Asset verification QA (lines 823-834)

**Source of Truth:** `backend/data/items.json` - check `has_sprites` and `has_icon` flags
