# Dev Mode to Production Checklist

This document tracks all development-mode accommodations that must be addressed before production deployment.

---

## Environment Variables (`.env`)

| Variable | Dev Value | Prod Value | Notes |
|----------|-----------|------------|-------|
| `DEV_MODE` | `true` | `false` | Disables blockchain simulation + mock activity |
| `CHAIN_ID` | `84532` (Base Sepolia) | `8453` (Base Mainnet) | Dashboard reads from backend |
| `RPC_URL` | `https://sepolia.base.org` | Mainnet RPC URL | Get from Alchemy/Infura |
| `ACHIEVEMENT_CONTRACT_ADDRESS` | (empty) | Deployed contract address | Deploy contract first |
| `MINTER_PRIVATE_KEY` | (empty) | Backend wallet private key | **NEVER commit this** |
| `PLATFORM_WALLET_ADDRESS` | (empty) | Platform custody wallet | For bridge system |
| `PLATFORM_WALLET_KEY` | (empty) | Platform wallet private key | **NEVER commit this** |
| `DATABASE_URL` | `sqlite:///./socialauth.db` | PostgreSQL URL | Use managed DB |
| `SESSION_SECRET` | dev string | Random 32+ char string | `openssl rand -hex 32` |
| `ADMIN_SECRET` | auto-generated | Secure random string | `openssl rand -hex 16` |
| `APP_URL` | ngrok URL | Production domain | HTTPS required |
| `CORS_ORIGINS` | (empty) | Production domain(s) | Comma-separated |

---

## Automated by DEV_MODE Flag

These are now automatically controlled by setting `DEV_MODE=false`:

### 1. Mock Activity Seeding (FIXED)
**File:** `backend/app/main.py`

Mock global feed and live activity generator now only run when `DEV_MODE=true`:
```python
if DEV_MODE:
    seed_mock_global_feed()
    start_mock_activity(min_interval=20, max_interval=60)
```

### 2. Blockchain Simulation (Already Working)
**File:** `backend/app/services/wallet_service.py`

Bridge transfers are simulated when `DEV_MODE=true`, real transactions when `false`.

### 3. CORS Localhost Origins (FIXED)
**File:** `backend/app/main.py`

Localhost origins only added when `DEV_MODE=true` or no CORS_ORIGINS configured.

---

## Automated by CHAIN_ID Environment Variable

### Dashboard Chain Switching (FIXED)
**File:** `backend/templates/dashboard.html`

Chain ID now read from backend environment and injected into template:
```javascript
const CHAIN_ID = {{ chain_id | default(84532) }};
const CHAIN_ID_HEX = '0x' + CHAIN_ID.toString(16);
```

Just set `CHAIN_ID=8453` in `.env` for mainnet.

---

## Automated by DATABASE_URL

### Alembic Migrations (FIXED)
**File:** `backend/alembic/env.py`

Now reads `DATABASE_URL` from environment, fallback to SQLite:
```python
url = os.getenv("DATABASE_URL", "sqlite:///./socialauth.db")
```

---

## Still Requires Manual Review

### 1. Bridge System - Chain ID Filtering

**File:** `backend/app/routes/wallet_routes.py`

**Lines ~1036-1039** - `/bridge-in/available`:
```python
# CURRENT (dev): No chain_id filter - finds items on any chain
available_items = db.query(ForgedAchievement).filter(
    ForgedAchievement.bridge_status == BridgeStatus.BRIDGED.value,
    ForgedAchievement.external_owner_wallet == wallet.wallet_address.lower(),
).all()
```

**Decision needed:** Should we filter by chain_id in production? This affects items forged on different chains.

---

## Godot Client Changes

### API Base URL (FIXED)
**File:** `scripts/systems/AshbaneAuth.gd`

Now auto-detects export builds and uses production URL:
```gdscript
const API_BASE_PROD = ""  # TODO: Set your production domain

func get_api_base() -> String:
    # Export builds use production URL
    var is_export_build = OS.has_feature("standalone") or OS.has_feature("template")
    if (is_export_build or FORCE_PRODUCTION) and API_BASE_PROD != "":
        return API_BASE_PROD
    # Development uses LAN or ngrok
    ...
```

**Action:** Set `API_BASE_PROD` to your production domain before exporting.

---

## Pre-Production Checklist

- [ ] **Rotate all API keys** (Steam, Battle.net, Discord, GitHub, Facebook, Roblox, OpenXBL)
- [ ] Generate new `SESSION_SECRET` with `openssl rand -hex 32`
- [ ] Generate new `ADMIN_SECRET` with `openssl rand -hex 16`
- [ ] Set `DEV_MODE=false`
- [ ] Set `DATABASE_URL` to PostgreSQL
- [ ] Set `APP_URL` to production domain
- [ ] Set `CORS_ORIGINS` to production domain
- [ ] Set `CHAIN_ID` to production chain (8453 for Base Mainnet)
- [ ] Set `API_BASE_PROD` in Godot AshbaneAuth.gd
- [ ] Deploy smart contract and set `ACHIEVEMENT_CONTRACT_ADDRESS`
- [ ] Fund minter/platform wallets with gas
- [ ] Run `alembic upgrade head` on production database
- [ ] Test full auth flow with all providers
- [ ] Test bridge flow (if using)

---

## Quick Reference: Files Modified for Dev Mode

1. `backend/.env` - DEV_MODE, CHAIN_ID, DATABASE_URL
2. `backend/app/main.py` - DEV_MODE controls mock activity + CORS
3. `backend/app/services/wallet_service.py` - DEV_MODE controls blockchain simulation
4. `backend/app/routes/wallet_routes.py` - Relaxed chain_id filtering (manual)
5. `backend/templates/dashboard.html` - CHAIN_ID from backend
6. `scripts/systems/AshbaneAuth.gd` - API_BASE_PROD for exports

---

*Last updated: December 2024*
