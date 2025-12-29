# Forge Item Destruction Endpoints

## Overview

The game client now calls backend endpoints when forged items are destroyed (deleted, sold to vendor). This makes the **game server authoritative** for in-game actions, with the backend updated accordingly.

## Required Endpoints

### 1. `POST /api/forge/destroy`

Permanently destroys a forged item. Used when:
- Player deletes item from inventory (drag to trash)
- Player sells item to vendor
- (Future) Item decays after being dropped

**Request:**
```json
{
  "token_id": 123,
  "reason": "player_delete" | "vendor_sale" | "dropped_decay"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "gold_received": 500,  // For vendor_sale, based on rarity
  "item_name": "Adamant Rail",
  "transferred_to": "treasury"
}
```

**Response (400/403/404):**
```json
{
  "success": false,
  "error": "Item not found" | "Not owned by user" | "Item is bridged out"
}

```

**Backend Logic:**
1. Verify `token_id` belongs to authenticated user
2. Check item is `claimed_in_game = true` (can't destroy unclaimed items)
3. Check `bridge_status = "in_game"` (can't destroy bridged items)
4. **Soft delete**:
   - Set `destroyed_at = now()`
   - Set `destroyed_reason = reason`
   - Set `destroyed_by_user_id = current_user.id`
   - Transfer ownership to treasury wallet address
5. Calculate gold value if `reason == "vendor_sale"`:
   - Rare: 300 gold
   - Epic: 600 gold
   - Legendary: 1200 gold
6. Keep full record for support ticket restoration

**Database Changes:**
```sql
ALTER TABLE forged_achievements ADD COLUMN destroyed_at TIMESTAMP NULL;
ALTER TABLE forged_achievements ADD COLUMN destroyed_reason VARCHAR(50) NULL;
ALTER TABLE forged_achievements ADD COLUMN destroyed_by_user_id INTEGER NULL;
ALTER TABLE forged_achievements ADD COLUMN previous_owner_id INTEGER NULL;
```

---

### 2. `POST /api/forge/unclaim-from-game`

Unclaims an item from game inventory. Item still exists, can be re-claimed from Armory.
Use case: "Stash" functionality, or if we want a softer removal option.

**Request:**
```json
{
  "token_id": 123
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "item_name": "Adamant Rail"
}
```

**Backend Logic:**
1. Verify `token_id` belongs to authenticated user
2. Set `claimed_in_game = false`
3. Item remains in user's forged items list, visible in Armory

---

### 3. Treasury Wallet

For destroyed/vendored items, transfer to a treasury wallet rather than burning:

```python
# config.py
TREASURY_WALLET_ADDRESS = os.getenv("TREASURY_WALLET_ADDRESS", "0x...treasury...")
```

This allows:
- Items to potentially be resold by vendors (future feature)
- Full audit trail of where items went
- Support ticket restoration with provenance intact

---

## Gold Value Calculation

When `reason == "vendor_sale"`, calculate gold based on rarity:

```python
VENDOR_SELL_VALUES = {
    "common": 50,
    "uncommon": 150,
    "rare": 300,
    "epic": 600,
    "legendary": 1200
}

def get_vendor_value(forged_item):
    rarity = forged_item.item_rarity.lower()
    return VENDOR_SELL_VALUES.get(rarity, 100)
```

---

## Support Ticket Restoration

Admin endpoint to restore a destroyed item:

### `POST /api/admin/forge/restore` (Admin only)

**Request:**
```json
{
  "token_id": 123,
  "restore_to_user_id": 456,  // Optional, defaults to original owner
  "reason": "Support ticket #1234"
}
```

**Backend Logic:**
1. Find item by `token_id` where `destroyed_at IS NOT NULL`
2. Clear `destroyed_at`, `destroyed_reason`, `destroyed_by_user_id`
3. Transfer ownership back from treasury to target user
4. Set `claimed_in_game = false` (user must re-claim from Armory)
5. Log restoration in audit table

---

## Existing Endpoint Update

### `GET /api/me/forged-items`

Should now exclude destroyed items:

```python
forged_items = session.query(ForgedAchievement).filter(
    ForgedAchievement.user_id == current_user.id,
    ForgedAchievement.destroyed_at.is_(None)  # ADD THIS
).all()
```

---

## Migration Script

```python
"""Add destroyed item tracking columns

Revision ID: xxx
"""

from alembic import op
import sqlalchemy as sa

def upgrade():
    op.add_column('forged_achievements', sa.Column('destroyed_at', sa.DateTime(), nullable=True))
    op.add_column('forged_achievements', sa.Column('destroyed_reason', sa.String(50), nullable=True))
    op.add_column('forged_achievements', sa.Column('destroyed_by_user_id', sa.Integer(), nullable=True))
    op.add_column('forged_achievements', sa.Column('previous_owner_id', sa.Integer(), nullable=True))

    # Index for finding destroyed items (for admin restore)
    op.create_index('ix_forged_achievements_destroyed', 'forged_achievements', ['destroyed_at'])

def downgrade():
    op.drop_index('ix_forged_achievements_destroyed')
    op.drop_column('forged_achievements', 'previous_owner_id')
    op.drop_column('forged_achievements', 'destroyed_by_user_id')
    op.drop_column('forged_achievements', 'destroyed_reason')
    op.drop_column('forged_achievements', 'destroyed_at')
```

---

## Route Implementation Example

```python
# app/routes/forge_routes.py

@router.post("/destroy")
async def destroy_forged_item(
    request: DestroyRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_db)
):
    """Permanently destroy a forged item (vendor sale, player delete)"""

    # Find the item
    forged = session.query(ForgedAchievement).filter(
        ForgedAchievement.token_id == request.token_id,
        ForgedAchievement.user_id == current_user.id,
        ForgedAchievement.destroyed_at.is_(None)
    ).first()

    if not forged:
        raise HTTPException(404, "Item not found or not owned by you")

    if not forged.claimed_in_game:
        raise HTTPException(400, "Item not claimed in game")

    if forged.bridge_status != "in_game":
        raise HTTPException(400, "Cannot destroy bridged item")

    # Calculate gold for vendor sales
    gold_received = 0
    if request.reason == "vendor_sale":
        gold_received = VENDOR_SELL_VALUES.get(forged.item_rarity.lower(), 100)

    # Soft delete - transfer to treasury
    forged.previous_owner_id = forged.user_id
    forged.destroyed_at = datetime.utcnow()
    forged.destroyed_reason = request.reason
    forged.destroyed_by_user_id = current_user.id
    forged.user_id = TREASURY_USER_ID  # Or handle via wallet transfer
    forged.claimed_in_game = False

    session.commit()

    return {
        "success": True,
        "gold_received": gold_received,
        "item_name": forged.item_name,
        "transferred_to": "treasury"
    }


@router.post("/unclaim-from-game")
async def unclaim_from_game(
    request: UnclaimRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_db)
):
    """Unclaim item from game - still exists, can be re-claimed"""

    forged = session.query(ForgedAchievement).filter(
        ForgedAchievement.token_id == request.token_id,
        ForgedAchievement.user_id == current_user.id,
        ForgedAchievement.destroyed_at.is_(None)
    ).first()

    if not forged:
        raise HTTPException(404, "Item not found")

    forged.claimed_in_game = False
    session.commit()

    return {
        "success": True,
        "item_name": forged.item_name
    }
```

---

## Testing Checklist

- [ ] Player deletes forged item → backend `/destroy` called → item gone from `/me/forged-items`
- [ ] Player sells forged item to vendor → backend `/destroy` with `vendor_sale` → gold returned
- [ ] Can't destroy item that's bridged out
- [ ] Can't destroy item you don't own
- [ ] Admin can restore destroyed items
- [ ] Destroyed items don't reappear on sync
- [ ] Unclaimed items can be re-claimed from Armory
