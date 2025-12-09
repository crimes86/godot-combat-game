# Security Audit & Pre-Production Checklist

> **Status**: Audit Complete - Fixes Pending
> **Audit Date**: December 2024
> **Audited By**: Claude Code
> **Codebase Size**: ~64K lines GDScript, ~10K lines Python

---

## Summary

| Category | Count | Status |
|----------|-------|--------|
| Critical | 4 | ❌ Not Started |
| High | 3 | ❌ Not Started |
| Medium | 3 | ❌ Not Started |
| Low | 2 | ❌ Not Started |
| Dead Code | 4 files | ❌ Not Started |
| Stale Docs | 2 | ❌ Not Started |

---

## Critical Issues (Production Blockers)

### CRIT-1: API Keys in Repository

**Risk**: Complete account takeover for all OAuth providers
**Location**: `backend/.env`
**Current State**: File is in `.gitignore` but shows as "modified" in git status

**Exposed Secrets**:
- Steam API Key
- Battle.net Client ID + Secret
- Discord Client ID + Secret
- GitHub Client ID + Secret
- Facebook App ID + Secret
- Roblox Client Secret
- OpenXBL API Key
- Beta Access Code

**Fix Specification**:
```bash
# 1. Check if .env was ever committed
git log --all --full-history -- backend/.env

# 2. If committed, remove from history (requires force push)
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch backend/.env' \
  --prune-empty --tag-name-filter cat -- --all

# 3. Verify it's properly ignored
echo "backend/.env" >> .gitignore
git rm --cached backend/.env 2>/dev/null || true

# 4. BEFORE PRODUCTION: Regenerate ALL keys from each provider's dashboard
# - Steam: https://steamcommunity.com/dev/apikey
# - Battle.net: https://develop.battle.net/
# - Discord: https://discord.com/developers/applications
# - GitHub: https://github.com/settings/developers
# - Facebook: https://developers.facebook.com/
# - Roblox: https://create.roblox.com/credentials
# - OpenXBL: https://xbl.io/
```

---

### CRIT-2: Default Admin Secret

**Risk**: Anyone with source code can grant themselves admin
**Location**: `backend/app/main.py:141`

**Current Code**:
```python
ADMIN_SECRET = os.environ.get("ADMIN_SECRET", "mantle-dev-admin-2024")  # Change in production!
```

**Fix Specification**:
```python
# Replace with:
ADMIN_SECRET = os.environ.get("ADMIN_SECRET")
if not ADMIN_SECRET:
    if os.environ.get("ENV") == "production":
        raise RuntimeError("ADMIN_SECRET environment variable is required in production")
    else:
        ADMIN_SECRET = "dev-only-admin-secret"  # Only for local development
        print("⚠️  WARNING: Using default ADMIN_SECRET - do not use in production!")
```

**Production Deployment**:
```bash
# Generate secure secret
python -c "import secrets; print(secrets.token_urlsafe(32))"
# Add to production environment
export ADMIN_SECRET="<generated-secret>"
```

---

### CRIT-3: Weak Session Secret

**Risk**: Session forgery, authentication bypass
**Location**: `backend/.env:3`

**Current Value**:
```
SESSION_SECRET=change-this-to-a-secure-random-string-32chars
```

**Fix Specification**:
```bash
# Generate proper secret
python -c "import secrets; print(secrets.token_hex(32))"

# Update .env (local dev)
SESSION_SECRET=<64-char-hex-string>

# For production: set in environment, not in file
export SESSION_SECRET="<generated-secret>"
```

---

### CRIT-4: Private Key Documentation Risk

**Risk**: Developers may commit real private keys while following documentation
**Location**: `backend/contracts/README.md`

**Fix Specification**:

Add warning banner at top of file:
```markdown
# Smart Contract Deployment Guide

> ⚠️ **SECURITY WARNING** ⚠️
>
> This guide references private keys and secrets. **NEVER commit real private keys to git.**
>
> Before deploying:
> 1. Use `.env.example` as a template (contains placeholders only)
> 2. Create `.env` locally with real values
> 3. Verify `.env` is in `.gitignore`
> 4. Consider using a hardware wallet for production deployments
```

Add to `.gitignore`:
```
# Blockchain
*.key
*private*key*
```

Add pre-commit hook (`.pre-commit-config.yaml`):
```yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
```

---

## High Priority Issues

### HIGH-1: RPC Client ID Trust

**Risk**: Player impersonation, unauthorized actions
**Location**: `scripts/game_world.gd:3619`

**Current Code**:
```gdscript
@rpc("any_peer")
func _request_existing_players(requester_id: int):
    # Trusts client-provided requester_id
```

**Fix Specification**:
```gdscript
@rpc("any_peer")
func _request_existing_players():
    # Use actual sender ID, never trust client parameter
    var requester_id = multiplayer.get_remote_sender_id()

    if not multiplayer.is_server():
        return
    # ... rest of function
```

**Audit Required**: Search all `@rpc("any_peer")` functions:
```bash
grep -rn "@rpc.*any_peer" scripts/ --include="*.gd"
```

Each must either:
1. Have `if not multiplayer.is_server(): return` guard
2. Use `multiplayer.get_remote_sender_id()` instead of client params
3. Be intentionally client-callable (document why)

---

### HIGH-2: Resource Harvesting RPC Validation

**Risk**: Resource duplication, economy exploit
**Locations**:
- `scripts/items/PickableBone.gd:207`
- `scripts/environment/HarvestableTree.gd:1322-1342`
- `scripts/environment/HarvestableRock.gd:1227-1247`

**Fix Specification**:

Add server-side validation pattern:
```gdscript
@rpc("any_peer", "call_remote", "reliable")
func request_harvest():
    if not multiplayer.is_server():
        return

    var requester_id = multiplayer.get_remote_sender_id()
    var player = get_player_by_peer_id(requester_id)

    if not player:
        return

    # Validate distance
    if global_position.distance_to(player.global_position) > MAX_HARVEST_DISTANCE:
        return

    # Validate cooldown
    if not _can_player_harvest(requester_id):
        return

    # Process harvest server-side
    _do_harvest(requester_id)
```

---

### HIGH-3: Chat XSS Prevention

**Risk**: Cross-site scripting in web dashboard
**Location**: `backend/app/routes/chat_routes.py:211-215`

**Current Code**:
```python
content = body.content.strip()
if len(content) > 500:
    raise HTTPException(status_code=400, detail="Message too long")
```

**Fix Specification**:
```python
import html
from bleach import clean

def sanitize_chat_message(content: str) -> str:
    """Sanitize chat message for safe display"""
    # Strip whitespace
    content = content.strip()

    # Length check
    if len(content) > 500:
        raise HTTPException(status_code=400, detail="Message too long (max 500 chars)")

    if len(content) == 0:
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    # HTML escape for web display
    content = html.escape(content)

    # Optional: Strip any remaining HTML tags (belt and suspenders)
    content = clean(content, tags=[], strip=True)

    return content
```

Add to `requirements.txt`:
```
bleach>=6.0.0
```

---

## Medium Priority Issues

### MED-1: Plaintext OAuth Tokens

**Risk**: Database breach exposes all linked accounts
**Location**: `backend/app/models.py` - `ProviderAccount.access_token`

**Fix Specification**:

```python
# backend/app/crypto.py
from cryptography.fernet import Fernet
import os

def get_fernet() -> Fernet:
    key = os.environ.get("TOKEN_ENCRYPTION_KEY")
    if not key:
        raise RuntimeError("TOKEN_ENCRYPTION_KEY required")
    return Fernet(key.encode())

def encrypt_token(token: str) -> str:
    return get_fernet().encrypt(token.encode()).decode()

def decrypt_token(encrypted: str) -> str:
    return get_fernet().decrypt(encrypted.encode()).decode()
```

```python
# backend/app/models.py
class ProviderAccount(Base):
    # ... existing fields ...
    access_token_encrypted = Column(String, nullable=True)  # Rename column

    @property
    def access_token(self) -> str:
        if self.access_token_encrypted:
            return decrypt_token(self.access_token_encrypted)
        return None

    @access_token.setter
    def access_token(self, value: str):
        self.access_token_encrypted = encrypt_token(value) if value else None
```

Generate encryption key:
```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

---

### MED-2: Device Codes in Memory

**Risk**: Auth flows fail on server restart
**Location**: `backend/app/main.py:146`

**Current Code**:
```python
device_codes: dict = {}
```

**Fix Specification** (Redis):
```python
import redis
import json

redis_client = redis.from_url(os.environ.get("REDIS_URL", "redis://localhost:6379"))

def store_device_code(code: str, data: dict, expires_in: int = 900):
    redis_client.setex(f"device_code:{code}", expires_in, json.dumps(data))

def get_device_code(code: str) -> dict | None:
    data = redis_client.get(f"device_code:{code}")
    return json.loads(data) if data else None

def delete_device_code(code: str):
    redis_client.delete(f"device_code:{code}")
```

**Fix Specification** (Database fallback):
```python
# backend/app/models.py
class DeviceCode(Base):
    __tablename__ = "device_codes"

    code = Column(String, primary_key=True)
    user_code = Column(String, unique=True)
    data = Column(JSON)
    expires_at = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
```

---

### MED-3: Trading Input Validation

**Risk**: Negative prices, integer overflow, unauthorized trades
**Location**: `backend/app/routes/trading_routes.py`

**Fix Specification**:
```python
from pydantic import Field, validator

class DirectTradeRequest(BaseModel):
    token_id: int = Field(ge=1)
    price_gold: int = Field(ge=0, le=999_999_999)  # Max ~1 billion
    buyer_id: int = Field(ge=1)

    @validator('price_gold')
    def validate_price(cls, v):
        if v < 0:
            raise ValueError('Price cannot be negative')
        return v

@router.post("/trade/direct")
async def execute_direct_trade(
    request: DirectTradeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Verify seller owns the token
    token = db.query(ForgedItem).filter(
        ForgedItem.id == request.token_id,
        ForgedItem.owner_id == current_user.id
    ).first()

    if not token:
        raise HTTPException(404, "Token not found or not owned by you")

    # Verify buyer exists and has enough gold
    buyer = db.query(User).filter(User.id == request.buyer_id).first()
    if not buyer:
        raise HTTPException(404, "Buyer not found")

    if buyer.gold < request.price_gold:
        raise HTTPException(400, "Buyer has insufficient gold")

    # ... proceed with trade
```

---

## Low Priority Issues

### LOW-1: Debug Prints in Production

**Location**: `scripts/game_world.gd` (search for 🔍)

**Fix Specification**:
```gdscript
# Replace:
print("🔍 Debug: something happened")

# With:
Constants.log_spawning("Debug: something happened")  # Or appropriate log category
```

Or wrap in debug check:
```gdscript
if OS.is_debug_build():
    print("🔍 Debug: something happened")
```

---

### LOW-2: Backup Files in Repository

**Location**:
- `scripts/player/Player.gd.backup_before_lpc_addon`
- `scripts/player/Player.gd.backup_before_modular_lpc`

**Fix Specification**:
```bash
# Delete backup files
rm scripts/player/Player.gd.backup_*

# Add to .gitignore
echo "*.backup*" >> .gitignore
echo "*.bak" >> .gitignore
```

---

## Dead Code to Remove

| File | Purpose | Action |
|------|---------|--------|
| `scripts/player/PlayerCombat.gd` | Unused combat subsystem | Delete or integrate |
| `scripts/player/PlayerMovement.gd` | Unused movement subsystem | Delete or integrate |
| `scripts/world/WorldPathManager.gd` | Unused path manager | Delete or integrate |
| `scripts/world/WorldPropSpawner.gd` | Unused prop spawner | Delete or integrate |

**Decision Required**: These were created for a refactor that never happened. Either:
1. Complete the refactor and integrate them
2. Delete them and use git history if needed later

---

## Documentation Updates Needed

### DOC-1: Contract README Security Warning

**Location**: `backend/contracts/README.md`

Add security warning banner (see CRIT-4 above).

### DOC-2: API Contract Tier Verification

**Location**: `docs/API_CONTRACT.md`

Cross-reference tier thresholds with `backend/app/main.py` and update if needed.

---

## Pre-Production Checklist

```
[ ] CRIT-1: Rotate all API keys
[ ] CRIT-2: Make ADMIN_SECRET required in production
[ ] CRIT-3: Generate real SESSION_SECRET
[ ] CRIT-4: Add private key warnings to docs
[ ] HIGH-1: Fix RPC client ID trust
[ ] HIGH-2: Add resource harvesting validation
[ ] HIGH-3: Add chat XSS sanitization
[ ] MED-1: Encrypt OAuth tokens at rest
[ ] MED-2: Move device codes to persistent storage
[ ] MED-3: Add trading input validation
[ ] LOW-1: Remove debug prints
[ ] LOW-2: Delete backup files
[ ] DEAD: Remove or integrate unused subsystems
[ ] DOC: Update contract README
[ ] DOC: Verify API contract accuracy
```

---

## Recommended Security Tools

```bash
# Install pre-commit hooks for secret detection
pip install pre-commit detect-secrets
detect-secrets scan > .secrets.baseline
pre-commit install

# Python dependency vulnerabilities
pip install safety
safety check

# Python static security analysis
pip install bandit
bandit -r backend/app/

# Keep dependencies updated
pip install pip-audit
pip-audit
```

---

## Positive Security Findings

The codebase already implements many security best practices:

- ✅ Server-authoritative combat (enemy damage validated server-side)
- ✅ Anti-cheat rate limiting with exponential backoff
- ✅ Password hashing with SHA-256 + per-user salt
- ✅ SQL injection prevention via SQLAlchemy ORM
- ✅ Login rate limiting (5 attempts/minute)
- ✅ Proper session token generation
- ✅ Environment variables for secrets (mostly)
- ✅ `.gitignore` covers sensitive files (mostly)

---

*Last Updated: December 2024*
