# Claude Instructions for Mantle

## Project Overview

Mantle is a two-part system:
1. **Backend (this repo)** - FastAPI authentication layer that aggregates gaming achievements
2. **Godot Game (separate repo)** - Multiplayer game where achievements become cosmetics

The web dashboard is NOT a TrueAchievements competitor. It's the auth layer for the game.

---

## Environment Variables

**Required (app crashes without these):**
```
SESSION_SECRET=<random 32-char string>
DATABASE_URL=sqlite:///./socialauth.db  # or PostgreSQL for prod
APP_URL=http://localhost:8000
```

**Provider APIs:**
```
STEAM_API_KEY=<from steamcommunity.com/dev/apikey>
BATTLENET_CLIENT_ID=<from develop.battle.net>
BATTLENET_CLIENT_SECRET=<from develop.battle.net>
```

**Admin/Beta:**
```
ADMIN_SECRET=<change from default in production>
BETA_ACCESS_CODE=<optional - enables beta gate>
```

---

## Documentation Rules

**When you modify an API endpoint:**
1. Update `API_CONTRACT.md` with the new request/response format
2. Update the version number and changelog at the bottom

**When you modify the anti-exploit system:**
1. Update `docs/ACHIEVEMENT_VERIFICATION.md`

**When you modify game design decisions (tiers, cosmetic mappings):**
1. Update `docs/GODOT_HANDOFF.md`

**When you add/modify provider support:**
1. Update `docs/PROVIDER_ROADMAP.md`

## Source of Truth

| Topic | Document |
|-------|----------|
| API endpoints, auth flow, request/response | `API_CONTRACT.md` |
| Anti-exploit, achievement verification | `docs/ACHIEVEMENT_VERIFICATION.md` |
| Game design, cosmetic mappings | `docs/GODOT_HANDOFF.md` |
| Provider integration status | `docs/PROVIDER_ROADMAP.md` |
| **Forge item design philosophy** | `docs/FORGE_ITEM_PHILOSOPHY.md` |
| **Trading & economy system** | `docs/FORGE_ECONOMY_DESIGN.md` |
| **Provenance & blockchain backing** | `docs/FORGE_PROVENANCE_SYSTEM.md` |
| **Item effects & abilities** | `docs/FORGE_ITEM_EFFECTS.md` |
| **Immutable design principles** | `docs/GOLDEN_RULES.md` |

---

## Key Architecture

### Anti-Exploit System (Critical)

The `AchievementCredit` table tracks claims globally by `provider_name + provider_user_id`:
- `is_original_claim=True` → Counts toward Mantle tier, can be forged
- `is_original_claim=False` → Display only (prevents unlink/relink exploits)

**Never bypass this.** See `docs/ACHIEVEMENT_VERIFICATION.md` for details.

### Authentication Patterns

- **Web users:** Session cookie (`session_id`)
- **Godot client:** Bearer token in `Authorization` header
- Both resolved by `get_session_token()` in `app/main.py`

### Trading & Economy (Twinking System)

Forged items are Dreadland's **twinking system** - no level requirements, tradeable from day one.

**Key principles:**
- Trading is **frictionless MMO-style** - standard trade windows, gold exchanges
- Blockchain is **invisible infrastructure** - users never see wallets or gas fees
- Provenance tracked on-chain but **batched** every 5 minutes for efficiency
- **Traditional gamers first** - the crypto aspect is optional/hidden

**Backend responsibilities:**
- Record trades in database immediately (source of truth for gameplay)
- Queue chain updates for batch processing
- Apply 5% gold tax on trades
- Enforce 24-hour trade cooldowns
- Track provenance (forger, trade count, ownership chain)

See `docs/FORGE_ECONOMY_DESIGN.md` for full specification.

### Provider Registry

To add a new provider, edit `app/providers/__init__.py`:
1. Add entry to `PROVIDERS` dict
2. Set `enabled=False` initially
3. Implement `sync_{provider}_achievements()` function

---

## Important Constants

```python
SYNC_COOLDOWN_MINUTES = 15      # Admins bypass
SESSION_TOKEN_TTL = 24 hours
DEVICE_CODE_TTL = 10 minutes

# Tier thresholds (cosmetic only, no gameplay impact)
TIERS = {
    "initiate": 0,
    "bronze": 100,
    "silver": 500,
    "gold": 1000,
    "platinum": 2000,
    "diamond": 3000,
    "legendary": 5000,
    "mythic": 7500
}
```

---

## Gotchas

1. **Alembic hardcoded path** - `alembic/env.py` line 55 hardcodes SQLite. Must change for PostgreSQL.

2. **Device auth is in-memory** - Godot device codes stored in dict, not database. Lost on restart.

3. **Steam uses OpenID 2.0** - Different from OAuth2 (Battle.net). Special flow in `/auth/steam/login`.

4. **No tests exist** - Manual testing required. User tests in Godot before commits.

5. **OAuth tokens stored plaintext** - `ProviderAccount.access_token` is not encrypted.

---

## Key Files

| File | Purpose |
|------|---------|
| `app/main.py` | Routes, auth, tier calculation (~2300 lines) |
| `app/models.py` | SQLAlchemy models |
| `app/providers/__init__.py` | Provider registry |
| `app/services/effort_scoring.py` | **Unified effort scoring (0-100) across all providers** |
| `app/services/item_forge_service.py` | Item generation from achievements |
| `app/services/steam_services.py` | Steam sync logic |
| `app/services/battlenet_services.py` | Battle.net sync logic |
| `app/routes/wallet_routes.py` | NFT forging endpoints |
| `app/routes/trading_routes.py` | **Trading endpoints (pending)** |
| `alembic/versions/` | Database migrations |
| `data/items.json` | **Forge item catalog and achievement mappings** |

---

## Backend Tools

| Script | Purpose |
|--------|---------|
| `tools/convert_provider_icons.py` | Convert SVG icons to PNG for Godot |
| `tools/generate_item_manifest.py` | Generate item manifest from items.json |
| `scripts/fetch_wow_achievements.py` | Fetch WoW achievement data |
| `scripts/build_wow_achievement_db.py` | Build WoW achievement database |
| `scripts/cleanup_duplicate_achievements.py` | Clean up duplicate achievements |

### Provider Icon Conversion

When adding a new provider, you need PNG versions of icons for Godot (can't load SVGs from HTTP):

```bash
# Requires cairosvg (Windows needs GTK runtime installed)
pip install cairosvg

# Convert all provider SVGs to PNGs
python tools/convert_provider_icons.py
```

Icons are served at `/static/icons/{provider}.png` and returned in API responses.

---

## Database Migrations

```bash
# Create new migration
alembic revision -m "description"

# Apply migrations
alembic upgrade head

# Check current version
alembic current
```

---

## Principles

1. **Traditional gamers first** - Blockchain is invisible infrastructure, not marketing
2. **Anti-exploit first** - Always check for ways users could game the system
3. **Frictionless trading** - In-game trades work like any MMO, chain updates happen behind scenes
4. **Single source of truth** - Don't duplicate API specs across docs
5. **Test before commit** - User tests in Godot, not automated tests
6. **Never expose crypto complexity** - No wallets, gas fees, or blockchain terminology in user-facing flows

---

## Don't

- Don't commit without user testing in Godot
- Don't push until user confirms
- Don't create documentation files unless asked
- Don't store secrets in code (use .env)
- Don't bypass `is_original_claim` checks
