# Dreadland Architecture

> **This document explains the monorepo structure, why it exists, and how to separate the systems for production.**

---

## Overview

Dreadland is a multiplayer game built with two main components:

1. **Godot Client** (`/`) - The game itself, built in Godot 4.5
2. **Ashbane Backend** (`/backend/`) - FastAPI server for authentication and achievement aggregation

Both components live in this repo **temporarily** for streamlined AI-assisted development. For production, they will be separated.

---

## Why a Monorepo?

### The Problem
When building a system where:
- Backend defines achievement → item mappings
- Frontend displays those items with specific sprites/effects
- Both must agree on weapon types, effect names, rarity tiers, etc.

...having separate repos causes **constant sync issues**:
- Backend adds new weapon type → Godot crashes on unknown type
- Godot renames effect → Backend sends old name → Nothing renders
- Documentation drifts apart → Engineers guess at contracts

### The Solution
**Single repo = Single source of truth**

During development, Claude (or any AI assistant) can:
- Read `backend/data/items.json` to understand item definitions
- Read `scripts/systems/ForgeItemDB.gd` to see Godot's enums
- Ensure both match without context switching

This eliminates the "telephone game" between repos.

---

## Repository Structure

```
godot-combat-game-master/
├── .claude/                    # Claude Code instructions
│   └── CLAUDE.md               # Project-specific AI guidelines
│
├── docs/                       # ALL documentation (consolidated)
│   ├── ARCHITECTURE.md         # This file
│   ├── API_CONTRACT.md         # Backend ↔ Godot API spec
│   ├── FORGE_AND_Ashbane.md     # Forge system spec
│   ├── GODOT_ITEM_HANDOFF.md   # Item system handoff
│   ├── GODOT_HANDOFF.md        # Vision and cosmetic systems
│   ├── ACHIEVEMENT_VERIFICATION.md  # Anti-exploit systems
│   ├── PROVIDER_ROADMAP.md     # Platform integration status
│   ├── ASSET_DESIGN_GUIDE.md   # Asset creation guidelines
│   ├── LPC_GUIDE.md            # Sprite format guide
│   └── ...                     # Other game docs
│
├── backend/                    # Ashbane backend (Python/FastAPI)
│   ├── app/
│   │   ├── main.py             # Routes (~3000 lines)
│   │   ├── models.py           # SQLAlchemy models
│   │   ├── database.py         # DB connection
│   │   ├── providers/          # OAuth provider configs
│   │   │   └── __init__.py     # Provider registry
│   │   ├── services/           # Business logic
│   │   │   ├── steam_services.py
│   │   │   ├── battlenet_services.py
│   │   │   ├── item_forge_service.py  # Item computation
│   │   │   └── effort_scoring.py      # Unified rarity
│   │   └── routes/             # Modular route files
│   │       ├── wallet_routes.py
│   │       ├── friend_routes.py
│   │       └── chat_routes.py
│   ├── data/
│   │   └── items.json          # Item catalog (source of truth)
│   ├── templates/              # Jinja2 HTML templates
│   ├── static/                 # Web assets (CSS, images)
│   ├── alembic/                # Database migrations
│   ├── contracts/              # Solidity NFT contracts
│   ├── requirements.txt        # Python dependencies
│   ├── .env.example            # Environment template
│   └── CLAUDE.md               # Backend-specific AI instructions
│
├── scripts/                    # Godot GDScript files
│   ├── systems/
│   │   ├── AshbaneAuth.gd      # Auth + API client
│   │   ├── AshbaneCosmetics.gd # Cosmetic application
│   │   ├── ForgeItemManager.gd # Fetches forged items
│   │   ├── ForgeItemDB.gd      # Item definitions (enums)
│   │   └── ForgeVisualEffects.gd  # Effect rendering
│   └── ui/
│       └── Armory.gd           # Forge UI
│
├── assets/                     # Game assets
│   ├── equipment/
│   │   └── forged/             # Forged item sprites
│   └── icons/
│       └── forged/             # 64x64 item icons
│
├── scenes/                     # Godot scenes
├── data/                       # Game data (shop items, etc.)
└── project.godot               # Godot project file
```

---

## Data Flow

### Authentication
```
Godot                          Backend
  │                               │
  ├─ GET /api/auth/device ───────►│
  │◄──── device_code + auth_url ──┤
  │                               │
  │  [User opens browser]         │
  │  [Logs in with Steam/etc]     │
  │                               │
  ├─ GET /api/auth/status ───────►│
  │◄──── token ───────────────────┤
  │                               │
  │  [Save token locally]         │
```

### Fetching Forged Items
```
Godot                          Backend
  │                               │
  ├─ GET /api/me/forged-items ───►│
  │   (Bearer token)              │
  │                               │
  │◄─── forged_items[] ───────────┤
  │   - item_id                   │
  │   - item_name                 │
  │   - weapon_type               │
  │   - effect_name               │
  │   - effect_intensity          │
  │   - glow_color                │
  │                               │
  │  [Render items in Armory]     │
```

### Shared Definitions

Both systems must agree on:

| Definition | Backend Location | Godot Location |
|------------|------------------|----------------|
| Weapon types | `backend/data/items.json` → `weapon_types` | `scripts/systems/ForgeItemDB.gd` → `WeaponClass` |
| Item types | `backend/data/items.json` → `item_types` | `scripts/systems/ForgeItemDB.gd` → `ItemType` |
| Effect names | `backend/data/items.json` → `themes.*.effects` | `scripts/systems/ForgeVisualEffects.gd` → `EFFECT_CONFIGS` |
| Rarity tiers | `backend/data/items.json` → `rarities` | `scripts/systems/ForgeItemDB.gd` → `Rarity` |
| Theme colors | `backend/data/items.json` → `themes.*.color` | `scripts/systems/ForgeVisualEffects.gd` |

**`backend/data/items.json` is the source of truth.** Godot's enums should mirror it.

---

## Separation Strategy

When ready to launch, separate into two repos:

### Step 1: Create Backend Repo

```bash
# Clone just the backend
git clone <this-repo> Ashbane-backend-temp
cd Ashbane-backend-temp

# Keep only backend
git filter-branch --subdirectory-filter backend HEAD

# Push to new repo
git remote set-url origin git@github.com:your-org/Ashbane-backend.git
git push -u origin main
```

### Step 2: Create Game Client Repo

```bash
# Clone the full repo
git clone <this-repo> dreadland-client

# Remove backend folder
cd dreadland-client
rm -rf backend/
git add -A
git commit -m "Remove backend for separate deployment"

# Push to new repo
git remote set-url origin git@github.com:your-org/dreadland-client.git
git push -u origin main
```

### Step 3: Configure API Endpoint

In the game client, update `AshbaneAuth.gd`:

```gdscript
# Development
const API_BASE = "http://localhost:8000"

# Production (after separation)
const API_BASE = "https://api.ashbane.gg"
```

### Step 4: Shared Definitions

After separation, keep definitions in sync via:

**Option A: Manual Sync**
- Update `items.json` in backend
- Manually update Godot enums to match
- Document in release notes

**Option B: Code Generation**
- Backend exports `items.json`
- CI job generates `ForgeItemDB.gd` from it
- Auto-PR to game repo

**Option C: Runtime Fetch**
- Godot fetches `/api/catalog/weapon-types` at startup
- Builds enums dynamically
- More resilient but slower startup

### Step 5: Documentation Split

| Document | Goes To |
|----------|---------|
| `API_CONTRACT.md` | Both repos |
| `ACHIEVEMENT_VERIFICATION.md` | Backend only |
| `PROVIDER_ROADMAP.md` | Backend only |
| `FORGE_AND_Ashbane.md` | Both repos |
| `GODOT_ITEM_HANDOFF.md` | Both repos |
| `LPC_GUIDE.md` | Game client only |
| `ASSET_DESIGN_GUIDE.md` | Game client only |

---

## Development Workflow

### Running Backend Locally

```bash
cd backend

# First time setup
python -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your API keys

# Run migrations
alembic upgrade head

# Start server
uvicorn app.main:app --reload --port 8000
```

### Running Godot

1. Open `project.godot` in Godot 4.5
2. Ensure backend is running at `localhost:8000`
3. Press F5 to run

### Testing the Integration

1. Start backend: `uvicorn app.main:app --reload`
2. Run Godot game
3. Click "Login" in Armory
4. Complete OAuth in browser
5. Return to game → should show your achievements

---

## Key Files Reference

### Backend

| File | Purpose |
|------|---------|
| `app/main.py` | All routes, auth, tier calculation |
| `app/models.py` | Database models (User, Achievement, ForgedAchievement) |
| `app/providers/__init__.py` | OAuth provider configs (Steam, Xbox, PSN, etc.) |
| `app/services/item_forge_service.py` | Computes item stats at forge time |
| `app/services/effort_scoring.py` | Unified 0-100 effort score across platforms |
| `data/items.json` | Item catalog, weapon types, themes, mappings |

### Godot

| File | Purpose |
|------|---------|
| `scripts/systems/AshbaneAuth.gd` | Auth flow, API calls, token management |
| `scripts/systems/ForgeItemManager.gd` | Fetches/caches forged items from API |
| `scripts/systems/ForgeItemDB.gd` | Item/weapon type enums, static mappings |
| `scripts/systems/ForgeVisualEffects.gd` | Effect rendering configs |
| `scripts/ui/Armory.gd` | Forge UI implementation |

---

## Why Not Just Use API Docs?

API documentation describes the **interface**. But when building:

- "What weapon types exist?" → Need to check both systems
- "Does `ember_trail` effect exist in Godot?" → Need to read GDScript
- "Which achievements map to which items?" → Need `items.json`

A monorepo lets AI assistants answer these instantly by reading both codebases.

---

## Changelog

| Date | Change |
|------|--------|
| 2024-12-08 | Created ARCHITECTURE.md |
| 2024-12-08 | Consolidated docs from backend/docs/ to root docs/ |
| 2024-12-08 | Deleted duplicate documentation files |
