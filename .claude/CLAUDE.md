# Project Guidelines for Claude

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
│   └── head_female_armor/
│
├── equipment/                  # All equippable items
│   ├── armor/                  # Armor sets
│   │   └── tier1/              # Zone 1 armor (copper plate set)
│   │       ├── chest/copper_plate/standard/
│   │       ├── legs/copper_plate/standard/
│   │       └── ...
│   ├── weapons/                # Combat weapons
│   │   ├── sword/
│   │   ├── mace/
│   │   ├── spear/
│   │   ├── staff/
│   │   └── dagger/
│   ├── tools/                  # Harvesting tools
│   │   ├── axe/
│   │   └── pickaxe/
│   └── shields/
│
├── environment/                # World objects, terrain, props
│   └── wasteland/              # Zone 1 environment assets
│
├── icons/                      # UI icons for items, abilities
│
├── npcs/                       # Non-enemy NPCs (merchants, quest givers)
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
