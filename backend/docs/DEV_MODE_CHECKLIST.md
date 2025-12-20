# Dev Mode to Production Checklist

This document tracks all development-mode accommodations that must be addressed before production deployment.

---

## Environment Variables (`.env`)

| Variable | Dev Value | Prod Value | Notes |
|----------|-----------|------------|-------|
| `DEV_MODE` | `true` | `false` or remove | Disables blockchain simulation |
| `CHAIN_ID` | `84532` (Base Sepolia) | `8453` (Base Mainnet) | Or `137` for Polygon |
| `RPC_URL` | `https://sepolia.base.org` | Mainnet RPC URL | Get from Alchemy/Infura |
| `ACHIEVEMENT_CONTRACT_ADDRESS` | (empty) | Deployed contract address | Deploy contract first |
| `MINTER_PRIVATE_KEY` | (empty) | Backend wallet private key | **NEVER commit this** |
| `PLATFORM_WALLET_ADDRESS` | (empty) | Platform custody wallet | For bridge system |
| `PLATFORM_WALLET_KEY` | (empty) | Platform wallet private key | **NEVER commit this** |
| `DATABASE_URL` | `sqlite:///./socialauth.db` | PostgreSQL URL | Use managed DB |
| `SESSION_SECRET` | dev string | Random 32+ char string | Generate new for prod |
| `APP_URL` | ngrok URL | Production domain | HTTPS required |

---

## Code Changes to Revert/Review

### 1. Bridge System - Chain ID Filtering (RELAXED FOR DEV)

**File:** `backend/app/routes/wallet_routes.py`

**Lines 1038-1042** - `/bridge-in/available`:
```python
# CURRENT (dev): No chain_id filter - finds items on any chain
available_items = db.query(ForgedAchievement).filter(
    ForgedAchievement.bridge_status == BridgeStatus.BRIDGED.value,
    ForgedAchievement.external_owner_wallet == wallet.wallet_address.lower(),
).all()

# PROD: Add chain_id filter
available_items = db.query(ForgedAchievement).filter(
    ForgedAchievement.bridge_status == BridgeStatus.BRIDGED.value,
    ForgedAchievement.external_owner_wallet == wallet.wallet_address.lower(),
    ForgedAchievement.chain_id == chain_id,
).all()
```

**Lines 1107-1111** - `/bridge-in` (POST):
```python
# CURRENT (dev): No chain_id filter
forged = db.query(ForgedAchievement).filter(
    ForgedAchievement.token_id == token_id_int,
).first()

# PROD: Add chain_id filter back
forged = db.query(ForgedAchievement).filter(
    ForgedAchievement.token_id == token_id_int,
    ForgedAchievement.chain_id == chain_id,
).first()
```

**Why relaxed:** Test data has items with `chain_id=137` (Polygon) but wallet service defaults to `84532` (Base Sepolia).

---

### 2. DEV_MODE Blockchain Simulation

**File:** `backend/app/services/wallet_service.py`

**Lines 338-342** - `transfer_to_external()` (bridge-out):
```python
if DEV_MODE:
    mock_tx_hash = f"0x{'dev' + str(token_id).zfill(61)}"
    logger.info(f"[DEV MODE] Simulated bridge-out transfer...")
    return mock_tx_hash
```

**Lines 402-406** - `transfer_from_external()` (bridge-in):
```python
if DEV_MODE:
    mock_tx_hash = f"0x{'dev' + str(token_id).zfill(61)}"
    logger.info(f"[DEV MODE] Simulated bridge-in transfer...")
    return mock_tx_hash
```

**Prod behavior:** When `DEV_MODE=false`, these functions will execute real blockchain transactions. Requires:
- `MINTER_PRIVATE_KEY` set
- `PLATFORM_WALLET_ADDRESS` and `PLATFORM_WALLET_KEY` set
- Contract deployed and address configured
- Wallet has gas funds

---

### 3. Dashboard Chain Switching

**File:** `backend/templates/dashboard.html`

**Lines 3176-3177**:
```javascript
// CURRENT: Base Sepolia testnet
const baseSepoliaChainId = '0x14a34'; // 84532 in hex

// PROD: Change to mainnet
const baseMainnetChainId = '0x2105'; // 8453 in hex
```

---

## Database Considerations

### Test Data Cleanup
- Delete or migrate test `ForgedAchievement` records
- Update `chain_id` values to match production chain
- Clear test `WalletAccount` records
- Review `AchievementCredit.is_original_claim` for test accounts

### Migration
- Run `alembic upgrade head` on prod database
- Verify `alembic/env.py` line 55 uses PostgreSQL (not hardcoded SQLite)

---

## Godot Client Changes

### API Base URL

**File:** `scripts/systems/AshbaneAuth.gd`

**Lines 12-13**:
```gdscript
const API_BASE_DEV = "https://ngrok-url"  # Current dev
const API_BASE_PROD = ""  # TBD - set production URL
```

Update `get_api_base()` to return `API_BASE_PROD` in production builds.

---

## Pre-Production Checklist

- [ ] Deploy smart contract to mainnet
- [ ] Set all production environment variables
- [ ] Migrate database to PostgreSQL
- [ ] Clean up test data OR start fresh
- [ ] Update chain_id filters in bridge routes
- [ ] Set `DEV_MODE=false`
- [ ] Update Godot API base URL
- [ ] Fund platform wallet with gas
- [ ] Test full bridge flow on testnet first
- [ ] Set up monitoring/alerting
- [ ] Configure proper CORS for production domain

---

## Quick Reference: Files Modified for Dev Mode

1. `backend/.env` - DEV_MODE=true
2. `backend/app/services/wallet_service.py` - DEV_MODE checks
3. `backend/app/routes/wallet_routes.py` - Relaxed chain_id filtering
4. `backend/templates/dashboard.html` - Testnet chain ID
5. `scripts/systems/AshbaneAuth.gd` - API base URLs

---

*Last updated: December 2024*
