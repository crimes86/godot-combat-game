# Guest Auth Flow - Backend Troubleshooting

**Status:** ✅ Fixed
**Issue:** Existing accounts getting `is_new: true` instead of `is_new: false`

## Root Cause (Fixed)

The query was using `ForgedAchievement.user_id` which **doesn't exist**. ForgedAchievement uses:
- `wallet_account_id` → links to WalletAccount (which has user_id)
- `current_owner_id` → current owner after trades (NULL = original forger)

Fixed query now properly joins through WalletAccount and checks both forged items and traded items.

## Expected Behavior

When a guest authenticates mid-game via `POST /api/vendor/character/initialize`:

1. **New account (no prior activity):** Return `is_new: true`, sync guest progress
2. **Existing account (has played before):** Return `is_new: false`, client redirects to Armory

## Current Problem

Users with existing accounts (forge items, play history) are getting `is_new: true`, causing the client to stay in-game instead of redirecting to Armory.

## Endpoint Location

`/root/ashbane-backend/backend/app/routes/vendor_routes.py`

Look for the `POST /character/initialize` endpoint (around line 385-440).

## Current Detection Logic

```python
# Check if this is a "played" character (not brand new)
has_forge_items = db.query(ForgedAchievement).filter(ForgedAchievement.user_id == user.id).first() is not None
has_played_before = character.last_played_at is not None

is_existing_character = (
    character.level > 1 or
    character.gold > 100 or
    len((character.character_data or {}).get("inventory", [])) > 0 or
    has_forge_items or
    has_played_before
)
```

## Debugging Steps

1. Add logging to see what values are being checked:
```python
logger.info(f"Character check for user {user.id}: level={character.level}, gold={character.gold}, "
            f"inventory_len={len((character.character_data or {}).get('inventory', []))}, "
            f"has_forge_items={has_forge_items}, has_played_before={has_played_before}")
```

2. Check if `ForgedAchievement` query is working:
```python
forge_count = db.query(ForgedAchievement).filter(ForgedAchievement.user_id == user.id).count()
logger.info(f"User {user.id} has {forge_count} forged achievements")
```

3. Check if `last_played_at` is being set properly on the Character model

4. Verify the response is actually returning `is_new: False`:
```python
logger.info(f"Returning is_new={not is_existing_character} for user {user.id}")
```

## Test Commands

```bash
# Check service status
systemctl status ashbane

# View recent logs
journalctl -u ashbane -n 50 --no-pager

# Restart after changes
systemctl restart ashbane
```

## Client Expectation

When `is_new: false`:
- Client shows "Welcome back! You have an existing character. Loading Armory..."
- Client disconnects from game
- Client redirects to `res://scenes/ui/Armory.tscn`

When `is_new: true`:
- Client shows "Your progress has been saved. Resuming game..."
- Client stays in current game session

## Files Involved

- Backend: `/root/ashbane-backend/backend/app/routes/vendor_routes.py`
- Client: `scripts/ui/AuthOverlay.gd` (handles response)
- Spec: `backend/docs/GUEST_PROGRESS_SYNC_SPEC.md`
