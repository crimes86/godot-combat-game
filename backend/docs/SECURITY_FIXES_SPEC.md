# Security Fixes Specification

Go-live security hardening - ordered by severity.

---

## Deployment Context (Researched)

| Question | Answer | Notes |
|----------|--------|-------|
| Reverse proxy? | **Yes** - nginx | X-Forwarded-For and X-Real-IP already configured |
| Multiple workers? | **Yes** - 2 workers | Uvicorn with `--workers 2` in systemd |
| ENV=production set? | **No** | Uses DEV_MODE instead; add ENV=production to .env |
| Session invalidation OK? | **Yes** | DB-backed, no cascades, users just re-login |

**Bonus finding:** `cleanup_expired_sessions()` is defined but never called - expired sessions accumulate.

---

## CRITICAL

### 1. Admin Elevation IP Check Bypass via Reverse Proxy

**Location:** `backend/app/main.py:5773-5776`, `5800-5803`

**Problem:** `request.client.host` returns the proxy IP (often `127.0.0.1`) when behind nginx/load balancer, not the real client IP. Combined with the dev fallback secret, this allows remote admin elevation.

**Current Code:**
```python
client_ip = request.client.host if request.client else None
if client_ip not in ("127.0.0.1", "::1", "localhost"):
    raise HTTPException(status_code=403, detail="Admin grants must be made from server")
```

**Fix:**
1. Create `get_real_client_ip(request)` helper that checks `X-Forwarded-For` / `X-Real-IP` headers when `TRUST_PROXY=true`
2. Add `TRUSTED_PROXY_IPS` env var to whitelist which proxies to trust
3. For admin endpoints specifically, **remove IP-based gating entirely** - rely only on `ADMIN_SECRET` (which should be strong and never defaulted in prod)
4. Ensure `ENV=production` check is watertight (already exists at line 276-278)

**Implementation:**
```python
# Add near top of main.py (after other env vars ~line 280)
TRUST_PROXY = os.getenv("TRUST_PROXY", "false").lower() in ("true", "1")

def get_real_client_ip(request: Request) -> str:
    """Get real client IP, respecting X-Forwarded-For when behind trusted proxy."""
    if TRUST_PROXY:
        # X-Real-IP is set by nginx to $remote_addr (single IP, most reliable)
        real_ip = request.headers.get("X-Real-IP")
        if real_ip:
            return real_ip
        # Fallback: first IP from X-Forwarded-For chain (original client)
        forwarded = request.headers.get("X-Forwarded-For", "")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"

# For admin grant/revoke - remove IP check, rely on secret only:
@app.post("/api/admin/grant")
async def grant_admin(request: Request, secret: str, ...):
    if secret != ADMIN_SECRET:
        logger.warning(f"Invalid admin secret from {get_real_client_ip(request)}")
        raise HTTPException(status_code=403, detail="Invalid admin secret")
    # ... rest of logic
```

**Env change:** Add to production `.env`:
```
TRUST_PROXY=true
```

**Files to modify:**
- `backend/app/main.py` - Add helper, update both admin endpoints
- `backend/.env` - Add TRUST_PROXY=true

---

### 2. Default Admin Secret Fallback

**Location:** `backend/app/main.py:274-279`

**Problem:** If `ADMIN_SECRET` is unset and `ENV` != `production`, it falls back to `"dev-only-admin-secret"`. If production deploy forgets to set `ENV=production`, the default secret is active.

**Current Risk Level:** LOW - You already have ADMIN_SECRET set in prod `.env`. This is defense-in-depth.

**Current Code:**
```python
ADMIN_SECRET = os.environ.get("ADMIN_SECRET")
if not ADMIN_SECRET:
    if os.environ.get("ENV") == "production":
        raise RuntimeError("ADMIN_SECRET environment variable is required in production")
    ADMIN_SECRET = "dev-only-admin-secret"
```

**Fix:**
1. Use `DEV_MODE` (which you already set) instead of `ENV`
2. Generate ephemeral secret in dev instead of known default
3. Add `ENV=production` to `.env` as extra safety net

**Implementation:**
```python
ADMIN_SECRET = os.environ.get("ADMIN_SECRET")
if not ADMIN_SECRET:
    # Fail in production (either ENV=production OR DEV_MODE=false with real APP_URL)
    is_prod = (
        os.environ.get("ENV") == "production" or
        (not DEV_MODE and APP_URL and not APP_URL.startswith("http://localhost"))
    )
    if is_prod:
        raise RuntimeError("ADMIN_SECRET is REQUIRED in production")
    # In dev, generate a random one-time secret and log it
    import secrets
    ADMIN_SECRET = secrets.token_urlsafe(32)
    print(f"⚠️  No ADMIN_SECRET set - generated ephemeral: {ADMIN_SECRET[:16]}...")
    print("   Set ADMIN_SECRET env var for persistent admin access")
```

**Env change:** Add to production `.env` (defense-in-depth):
```
ENV=production
```

**Files to modify:**
- `backend/app/main.py`
- `backend/.env` - Add ENV=production

---

## HIGH

### 3. OAuth Tokens Logged on Failure

**Location:** `backend/app/main.py:1472`, `backend/app/providers/oauth_handler.py:121`

**Problem:** Access/refresh tokens logged verbatim to console and admin log viewer.

**Current Code (main.py:1472):**
```python
logger.error(f"Battle.net login failed: Could not retrieve user ID. Token: {oauth_token}")
```

**Current Code (oauth_handler.py:121):**
```python
logger.error(f"Could not extract user ID for {provider_name}. Token: {token}, Userinfo: {userinfo}")
```

**Fix:** Never log tokens. Log sanitized metadata only.

**Implementation:**
```python
# main.py:1472
logger.error(f"Battle.net login failed: Could not retrieve user ID. Token present: {bool(oauth_token)}")

# oauth_handler.py:121
logger.error(
    f"Could not extract user ID for {provider_name}. "
    f"Token keys: {list(token.keys()) if token else None}, "
    f"Userinfo keys: {list(userinfo.keys()) if userinfo else None}"
)
```

**Files to modify:**
- `backend/app/main.py` - Line ~1472
- `backend/app/providers/oauth_handler.py` - Line ~121
- Grep for other `Token:` or `token=` in logger calls and sanitize

---

### 4. Duplicate Route Definitions (bridge-in/approval-*)

**Location:** `backend/app/routes/wallet_routes.py`

**Problem:** Same routes defined twice - FastAPI uses the **last** definition, silently overriding:
- Lines 1139 and 1481: `GET /bridge-in/approval-status`
- Lines 1179 and 1528: `GET /bridge-in/approval-tx`
- Lines 1226 and 1585: `POST /bridge-in/verify-approval`

The first set (1139-1226) has stricter chain_id checks. The second set (1481-1585) is more lenient. Second set wins.

**Fix:** Delete the duplicate block (lines 1139-1260 OR lines 1481-1620). Keep whichever has the correct behavior and merge any missing features.

**Analysis of differences:**
- First block (1139-1226): Filters wallet by `chain_id` match, raises exception on no wallet
- Second block (1481-1620): No chain_id filter, returns error object instead of exception

**Recommendation:** Keep second block (1481+) but add back the chain_id filtering from first block.

**Implementation:**
1. Delete lines 1139-1260 entirely
2. Update second block to add chain_id filter:
```python
wallet = db.query(WalletAccount).filter(
    WalletAccount.user_id == current_user.id,
    WalletAccount.chain_id == _wallet_service.CHAIN_ID,  # ADD THIS
).first()
```

**Files to modify:**
- `backend/app/routes/wallet_routes.py`

---

## MEDIUM

### 5. Session Tokens Stored Plaintext

**Location:** `backend/app/models.py:190-199`

**Problem:** Session tokens stored unhashed. DB leak = immediate account takeover.

**Current Code:**
```python
class Session(Base):
    token = Column(String(64), unique=True, index=True, nullable=False)
```

**Fix:** Store hashed tokens, compare on lookup.

**Implementation:**
```python
# models.py
import hashlib

class Session(Base):
    token_hash = Column(String(64), unique=True, index=True, nullable=False)
    # Remove: token = Column(...)

    @staticmethod
    def hash_token(token: str) -> str:
        return hashlib.sha256(token.encode()).hexdigest()

# main.py - session creation
session = Session(
    token_hash=Session.hash_token(session_token),
    user_id=user.id,
    expires_at=expires_at
)

# main.py - session lookup (update get_user_from_session)
def get_user_from_session(db: DbSession, token: str) -> Optional[User]:
    if not token:
        return None
    token_hash = Session.hash_token(token)
    session = db.query(Session).filter(
        Session.token_hash == token_hash,
        Session.expires_at > datetime.utcnow()
    ).first()
    return session.user if session else None
```

**Migration required:** Yes - need Alembic migration to rename column and rehash existing tokens (or invalidate all sessions on deploy).

**Files to modify:**
- `backend/app/models.py` - Update Session model
- `backend/app/main.py` - Update session creation and lookup
- `backend/alembic/versions/` - New migration

---

### 6. Token Encryption Silent Fallback

**Location:** `backend/app/services/crypto_service.py:54-75`

**Problem:**
- `encrypt_token` re-raises on failure (good)
- `decrypt_token` returns plaintext on `InvalidToken` (silent fallback for legacy migration)
- No alerting when legacy tokens encountered

**Fix:** Add structured logging/metrics when legacy tokens found, with plan to remove fallback after migration period.

**Implementation:**
```python
def decrypt_token(ciphertext: Optional[str]) -> Optional[str]:
    if not ciphertext:
        return None

    try:
        fernet = _get_fernet()
        decrypted = fernet.decrypt(ciphertext.encode())
        return decrypted.decode()
    except InvalidToken:
        # MIGRATION: Legacy unencrypted token detected
        # TODO: Remove this fallback after 2025-02-01 when all tokens rotated
        logger.warning(
            "LEGACY_TOKEN_DETECTED: Unencrypted token in database. "
            "Force re-auth to migrate. Remove fallback after migration deadline."
        )
        return ciphertext
    except Exception as e:
        logger.error(f"Token decryption failed: {e}")
        # Return None, don't silently return corrupted data
        return None
```

**Add migration enforcement:**
```python
# In startup, count legacy tokens and warn
legacy_count = db.query(ProviderAccount).filter(
    ~ProviderAccount.access_token.like("gAAAAA%")  # Not Fernet-encrypted
).count()
if legacy_count > 0:
    logger.warning(f"SECURITY: {legacy_count} unencrypted OAuth tokens in database. Force refresh recommended.")
```

**Files to modify:**
- `backend/app/services/crypto_service.py`
- `backend/app/main.py` (startup check)

---

### 7. Schema Creation on Import (Race Condition)

**Location:** `backend/app/main.py:62`

**Problem:** `Base.metadata.create_all(bind=engine)` runs at import time. With multiple workers:
- Race conditions on table creation
- Bypasses Alembic migrations
- Can cause schema drift

**Current Code:**
```python
Base.metadata.create_all(bind=engine)
```

**Fix:** Remove auto-create, rely exclusively on Alembic. Add startup check.

**Implementation:**
```python
# Remove line 62 entirely

# Add to startup_event():
@app.on_event("startup")
async def startup_event():
    # Verify migrations are current
    from alembic.config import Config
    from alembic import command
    from alembic.script import ScriptDirectory
    from alembic.runtime.migration import MigrationContext

    alembic_cfg = Config("alembic.ini")
    script = ScriptDirectory.from_config(alembic_cfg)

    with engine.connect() as conn:
        context = MigrationContext.configure(conn)
        current_rev = context.get_current_revision()
        head_rev = script.get_current_head()

        if current_rev != head_rev:
            logger.error(f"Database migrations not current! At {current_rev}, need {head_rev}")
            logger.error("Run: alembic upgrade head")
            if os.environ.get("ENV") == "production":
                raise RuntimeError("Cannot start with pending migrations in production")

    # ... rest of startup
```

**Files to modify:**
- `backend/app/main.py` - Remove create_all, add migration check

---

### 8. Background Services Race in Multi-Worker

**Location:** `backend/app/main.py:128-140`

**Problem:** Chain batching service and transfer indexer start in each worker. With 2 workers = 2 instances racing on the same blockchain operations.

**Current Code:**
```python
# Start chain batching service for trade provenance
try:
    from app.services.chain_batching_service import chain_batching_service
    chain_batching_service.start()
except Exception as e:
    logger.warning(f"Chain batching service not started: {e}")
```

**Fix: Single-worker designation**
```python
# Add near other env vars at top
BACKGROUND_WORKER = os.getenv("BACKGROUND_WORKER", "false").lower() in ("true", "1")

# In startup_event(), wrap the service starts:
if BACKGROUND_WORKER:
    # Start chain batching service for trade provenance
    try:
        from app.services.chain_batching_service import chain_batching_service
        chain_batching_service.start()
        logger.info("Chain batching service started (BACKGROUND_WORKER=true)")
    except Exception as e:
        logger.warning(f"Chain batching service not started: {e}")

    # Start transfer indexer for bridge system
    try:
        from app.services.transfer_indexer_service import transfer_indexer_service
        transfer_indexer_service.start()
        logger.info("Transfer indexer started (BACKGROUND_WORKER=true)")
    except Exception as e:
        logger.warning(f"Transfer indexer not started: {e}")
else:
    logger.info("Background services disabled on this worker (BACKGROUND_WORKER not set)")
```

**Deployment change:** Update systemd service to run one worker with background services:

**Option A: Separate services (Recommended)**
```ini
# /etc/systemd/system/ashbane.service (main workers - no background)
ExecStart=/home/Ashbane/.../uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 2

# /etc/systemd/system/ashbane-worker.service (background worker)
ExecStart=/home/Ashbane/.../uvicorn app.main:app --host 127.0.0.1 --port 8001 --workers 1
Environment="BACKGROUND_WORKER=true"
# Note: This worker doesn't need to be in nginx upstream (internal only)
```

**Option B: Single service, one worker designated (Simpler)**
```ini
# Keep --workers 2, but only one will run background services
# Add to .env:
BACKGROUND_WORKER=true
# This means BOTH workers will try to run services (not ideal)
```

**Best approach:** Option A - separate service file for the background worker. It can run on a different port and doesn't need nginx routing.

**Files to modify:**
- `backend/app/main.py` - Add BACKGROUND_WORKER check
- `/etc/systemd/system/ashbane-worker.service` - New service file (optional)

---

## LOW

### 9. Admin Secret in Query Parameter (/logs)

**Location:** `backend/app/main.py:5932-5969`

**Problem:** `?secret=XXX` appears in:
- Server access logs
- Proxy logs
- Browser history
- Referrer headers

**Current Code:**
```python
@app.get("/logs")
async def logs_dashboard_redirect(
    request: Request,
    secret: Optional[str] = None,  # <-- Query param
    ...
):
```

**Fix Options:**

**Option A: Use POST with body (Recommended)**
```python
@app.post("/logs/auth")
async def logs_auth(request: Request, body: dict, db: ...):
    secret = body.get("secret")
    if secret == ADMIN_SECRET:
        # Set secure HTTP-only cookie for subsequent requests
        response = RedirectResponse(url="/api/logs/view", status_code=302)
        response.set_cookie(
            key="logs_auth",
            value=create_short_lived_token(),  # 15-min expiry
            httponly=True,
            secure=True,
            samesite="strict"
        )
        return response
```

**Option B: Require admin session only (Simplest)**
Remove secret query param entirely - require user to be logged in as admin first.

```python
@app.get("/logs")
async def logs_dashboard(request: Request, db: ...):
    token = get_session_token(request)
    user = get_user_from_session(db, token) if token else None

    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin login required")

    return RedirectResponse(url="/api/logs/view", status_code=302)
```

**Files to modify:**
- `backend/app/main.py` - Update /logs endpoint

---

## BONUS

### 10. Expired Sessions Never Cleaned Up

**Location:** `backend/app/main.py:527-530`

**Problem:** `cleanup_expired_sessions()` function exists but is never called. Expired session records accumulate in database forever.

**Current Code:**
```python
def cleanup_expired_sessions(db: DbSession):
    """Remove expired sessions"""
    db.query(SessionModel).filter(SessionModel.expires_at < datetime.utcnow()).delete()
    db.commit()
```

**Fix:** Call cleanup on startup and periodically (piggyback on existing device code cleanup or add to background worker).

**Implementation:**
```python
# In startup_event(), add after device code cleanup:
@app.on_event("startup")
async def startup_event():
    # Clean up expired sessions on startup
    db = SessionLocal()
    try:
        cleanup_expired_sessions(db)
        cleanup_expired_device_codes(db)
        logger.info("Cleaned up expired sessions and device codes")
    finally:
        db.close()

    # ... rest of startup

# For periodic cleanup (if BACKGROUND_WORKER):
if BACKGROUND_WORKER:
    import asyncio

    async def periodic_cleanup():
        while True:
            await asyncio.sleep(3600)  # Every hour
            db = SessionLocal()
            try:
                cleanup_expired_sessions(db)
                cleanup_expired_device_codes(db)
            finally:
                db.close()

    asyncio.create_task(periodic_cleanup())
```

**Files to modify:**
- `backend/app/main.py` - Call cleanup in startup and add periodic task

---

## Pre-Deployment Checklist

**Env vars to add to production `.env`:**
```bash
ENV=production
TRUST_PROXY=true
BACKGROUND_WORKER=true  # Only on background worker service
```

---

## Pre-Implementation Questions (ANSWERED)

| Question | Answer | Source |
|----------|--------|--------|
| Behind reverse proxy? | **Yes** - nginx with X-Forwarded-For | DIGITALOCEAN_DEPLOYMENT.md |
| Multiple workers? | **Yes** - 2 workers via systemd | DIGITALOCEAN_DEPLOYMENT.md |
| ENV=production set? | **No** - uses DEV_MODE instead | .env.example |
| Session invalidation OK? | **Yes** - DB-backed, no cascades | models.py analysis |

---

## Implementation Order

**Phase 1: Quick wins (no deployment changes)**
1. **Fix #3** - Token logging (5 min - stops ongoing leak to logs)
2. **Fix #4** - Duplicate routes (5 min - delete 120 lines)
3. **Fix #6** - Encryption fallback logging (5 min - add warning)

**Phase 2: Code + env changes**
4. **Fix #2** - Admin secret fallback (10 min - add DEV_MODE check)
5. **Fix #1** - IP check + TRUST_PROXY (15 min - add helper function)
6. **Fix #10** - Session cleanup (10 min - call existing function)

**Phase 3: Deployment changes**
7. **Fix #8** - Background worker isolation (requires new systemd service)
8. **Fix #7** - Remove create_all (requires Alembic discipline)

**Phase 4: Migration required**
9. **Fix #5** - Session token hashing (Alembic migration + invalidate sessions)

**Phase 5: Low priority**
10. **Fix #9** - Logs auth method (nice-to-have)

---

## Summary of Env Changes

Add to production `.env`:
```bash
ENV=production          # Defense-in-depth for admin secret
TRUST_PROXY=true        # Enable X-Forwarded-For parsing
```

Add to background worker only:
```bash
BACKGROUND_WORKER=true  # Only on the dedicated background service
```
