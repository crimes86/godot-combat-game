# Dreadland Project Guidelines

## Quick Reference: Where Am I Working?

| Context | Config File | Main Scene | Key Docs |
|---------|-------------|------------|----------|
| **Client (Godot)** | `project.godot` | `MainMenu.tscn` | This file, `docs/` folder |
| **Server (Godot)** | `project.server.godot` | `server_main.tscn` | [Dedicated Server Build](#dedicated-server-build) |
| **Backend (Python)** | `backend/.env` | FastAPI app | `backend/README.md`, `backend/docs/` |

---

## Client Development (Godot)

The client is a Godot 4.5 game. Key entry points:
- **Main scene:** `scenes/ui/MainMenu.tscn`
- **Player:** `scripts/player/Player.gd`
- **Combat:** `scripts/player/PlayerCombat.gd`
- **Networking:** `scripts/networking/NetworkManager.gd`

### Windows Environment (IMPORTANT)

This project runs on **Windows**. Always use Windows-native commands:

**DO NOT USE:** `find`, `wc`, `grep`, `xargs`, `sed`, `awk`, `$(...)` subshells

**USE INSTEAD:** PowerShell cmdlets or Claude Code's built-in tools (Glob, Grep, Read)

```powershell
# Count PNG files
(Get-ChildItem -Path assets/icons -Filter *.png -Recurse).Count

# Find files by pattern
Get-ChildItem -Path . -Filter *.png -Recurse
```

### Code Conventions
- Equipment loading: `assets/equipment/` paths
- Enemy loading: `assets/characters/enemies/` paths
- Audio loading: `assets/audio/` paths (sfx/ or music/)

---

## Commit & Deployment Workflow

This is the **local dev machine** (Windows). Commit and push when asked.
After pushing, always tell the user which servers need syncing:

| Change touches... | Game Server needs pull? | Backend needs pull? |
|-------------------|------------------------|---------------------|
| GDScript only (client-only UI, HUD) | No | No |
| GDScript shared (Enemy.gd, game_world.gd, autoloads) | **Yes** — rebuild + restart `ashbane-game` | No |
| `project.server.godot` or server stubs | **Yes** — rebuild + restart `ashbane-game` | No |
| `backend/` Python code | No | **Yes** — restart backend service |
| Both GDScript shared + backend | **Yes** | **Yes** |

After push, remind user: "Game server needs pull + rebuild" or "Backend needs restart" or "Client-only, no server changes needed."

---

## Dedicated Server Build

**⚠️ CRITICAL: Before ANY server build/deploy, read `docs/SERVER_OPERATIONS.md` first!**

The server uses `project.server.godot` with stub autoloads (no UI rendering).

### Service Names (IMPORTANT)

| Service | Port | Status |
|---------|------|--------|
| `ashbane-game` | 7777 | ✅ **USE THIS** |
| `ashbane-server` | 7000 | ❌ DEPRECATED - DO NOT USE |

### Build and Deploy Steps

```bash
# 1. Read the operations doc first!
cat docs/SERVER_OPERATIONS.md

# 2. Build server (handles project file swap)
cd /opt/ashbane-game/source
./build_server.sh

# 3. Restart the CORRECT service
systemctl restart ashbane-game

# 4. Verify
systemctl status ashbane-game
journalctl -u ashbane-game -n 20
```

### Monorepo Workflow

```
project.godot          # CLIENT - always committed from Windows machine
project.server.godot   # SERVER - used only during export
build_server.sh        # Handles swap automatically
```

**Server-specific patterns:**
- `--server` flag detection: `"--server" in OS.get_cmdline_user_args()`
- No sprites on server - use `current_animation` variable for sync (see `docs/MULTIPLAYER_ANIMATION_SYNC.md`)
- AI sleep system when no players nearby
- Stub autoloads for UI systems

---

## Backend Development (Python/FastAPI)

Located in `backend/` folder. Handles auth, items, telemetry, trading.

**Setup:**
```bash
cd backend
pip install -r requirements.txt
cp .env.example .env  # Configure for local/prod
python -m uvicorn app.main:app --reload
```

**Key files:**
- `backend/app/main.py` - FastAPI app entry
- `backend/app/routers/` - API endpoints
- `backend/data/items.json` - Forge item definitions (source of truth)
- `backend/docs/` - Backend-specific docs

**Deployment:** See `backend/docs/DIGITALOCEAN_DEPLOYMENT.md`

---

## Documentation Reference

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
| World tree system (v2.1) | `docs/WORLD_TREE_V2.1.md` |
| World tree design spec | `docs/WORLD_TREE_FINAL_DESIGN_V2.1.md` |
| World tree blockchain | `docs/WORLD_TREE_BLOCKCHAIN_INTEGRATION.md` |
| **Art & Assets** | |
| LPC sprite guide | `docs/LPC_GUIDE.md` |
| Asset design guide | `docs/ASSET_DESIGN_GUIDE.md` |
| Godot item handoff | `docs/GODOT_ITEM_HANDOFF.md` |
| Gun weapon spec | `docs/GUN_WEAPON_SPEC.md` |
| **Architecture** | |
| System architecture | `docs/ARCHITECTURE.md` |
| Server architecture | `docs/SERVER_ARCHITECTURE.md` |
| **Server operations (READ BEFORE DEPLOY)** | `docs/SERVER_OPERATIONS.md` |
| Shard system (multi-server) | `docs/SHARD_SYSTEM.md` |
| Multiplayer animation sync | `docs/MULTIPLAYER_ANIMATION_SYNC.md` |
| Performance guide | `docs/PERFORMANCE.md` |
| API contract | `docs/API_CONTRACT.md` |
| Digital Ocean deployment | `backend/docs/DIGITALOCEAN_DEPLOYMENT.md` |
| Dev mode checklist | `backend/docs/DEV_MODE_CHECKLIST.md` |
| **Rules & Process** | |
| Golden rules (immutable) | `docs/GOLDEN_RULES.md` |
| Provider roadmap | `docs/PROVIDER_ROADMAP.md` |
| Itch.io release | `docs/ITCH_RELEASE_GUIDE.md` |

---

## Workflow Preferences

- For features touching 3+ files, use Plan mode first
- Always check existing patterns in similar code before implementing
- For Godot scripts, check for syntax with basic validation before considering done

---

## Asset Structure (Refactored Dec 2024)

All game assets should follow this canonical structure. Do NOT create new root-level folders.

```
assets/
├── audio/                      # ALL audio files
│   ├── music/                  # Background music tracks
│   └── sfx/                    # Sound effects
│       ├── ambient/            # Campfire, wolf howls, etc.
│       ├── combat/             # Hits, reactions, weapon sounds
│       ├── footsteps/          # Player, skeleton, wolf steps
│       ├── player/             # Player hurt, death, healing sounds
│       ├── tree/               # Chopping, falling sounds
│       └── ui/                 # Button clicks, inventory, quest sounds
│
├── characters/                 # Character sprites (players, enemies)
│   ├── body_male/              # Male player body
│   ├── body_female/            # Female player body
│   ├── body_skeleton/          # Skeleton enemy body
│   ├── enemies/                # ALL enemy sprites (wolf, skeleton, zombie)
│   ├── shadow/                 # Character shadow sprites
│   └── [clothing folders]/     # pants/, shirt/, boots/, etc.
│
├── equipment/                  # All equippable items
│   ├── armor/                  # Armor sets (starter/, tier1/)
│   ├── weapons/                # Combat weapons (sword/, mace/, spear/, etc.)
│   ├── tools/                  # Harvesting tools (axe/, pickaxe/)
│   ├── shields/
│   └── forged/                 # Forged item sprites
│
├── environment/                # World objects, terrain, props
├── icons/                      # UI icons for items, abilities
│   └── forged/                 # Forge system icons
├── npcs/                       # Non-enemy NPCs
├── sprites/                    # Additional sprite assets
└── ui/                         # UI elements, frames, buttons
```

## LPC Sprite Naming Convention

For equipment sprites in `equipment/armor/`:
```
[slot]/[item_name]/standard/
├── walk.png      # 9 frames x 4 directions (576x256)
├── slash.png     # 6 frames x 4 directions (384x256)
├── thrust.png    # 8 frames x 4 directions (512x256)
└── hurt.png      # 6 frames x 1 direction (384x64)
```

For starter clothes in `characters/`:
```
[item_name]_walk.png
[item_name]_slash.png
[item_name]_thrust.png
[item_name]_hurt.png
```

---

## Forge Icon Standards

**Spec:** 64x64 PNG, RGBA, centered content, min 4px padding

**Orientation:**
- Weapons: Diagonal 45°, tip pointing **upper-right**
- Armor/Shields: Upright, centered
- Accessories: Natural, centered

**Validation:** `python assets/icons/forged/icon_standards.py --validate`

---

## Forged Item Completion

**Full Process:** `docs/ACHIEVEMENT_ITEM_CREATION_PROCESS.md`

Key phases:
- **Phase 4.3** - Update `has_sprites`/`has_icon` in items.json
- **Phase 9.1** - Godot completion checklist
- **Phase 11.1** - Asset verification QA

**Source of Truth:** `backend/data/items.json`

---

## LPC Helmet Layers

Helmets can have separate layers (base, visor, wings). When processing:

1. Extract all layers from zip
2. Tint each layer separately if needed
3. Composite layers (base first, enhancements on top)

```python
from PIL import Image
result = Image.new('RGBA', base.size, (0, 0, 0, 0))
result.paste(base_tinted, (0, 0), base_tinted)
result.paste(wings_tinted, (0, 0), wings_tinted)
```

---

## Potential Issues After Dec 2024 Refactor

If assets fail to load:

| Issue | Old Path | New Path |
|-------|----------|----------|
| Sounds not playing | `assets/sounds/` | `assets/audio/sfx/` |
| Weapons not showing | `assets/weapons/` | `assets/equipment/weapons/` |
| Tools not loading | `assets/tools/` | `assets/equipment/tools/` |
| Armor not loading | `assets/armor/zone1/` | `assets/equipment/armor/tier1/` |

Key files to check:
- `scripts/systems/sound_manager.gd`
- `scripts/SimpleLPCSprite.gd`
- `scripts/player/Player.gd`
- `scripts/enemies/Enemy.gd`
- `scripts/systems/ItemIconGenerator.gd`
