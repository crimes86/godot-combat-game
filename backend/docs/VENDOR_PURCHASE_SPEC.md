# Vendor Purchase Validation Spec

**Status:** Spec for Backend Engineer
**Priority:** High (Security Fix)
**Affects:** Client + Backend only (no Godot server changes needed)

---

## Problem

Currently, vendor purchases are entirely client-side:
1. Client checks if player has enough gold locally
2. Client deducts gold from local `CharacterStats`
3. Client adds item to local inventory
4. Later, the character state is synced to backend via `/api/characters/save`

**Security Issue:** A hacked client can bypass price checks and obtain any item for free. The backend has no way to validate that gold was actually spent.

---

## Solution Overview

Add server-side purchase validation:
1. Client requests purchase from backend
2. Backend validates gold balance and item availability
3. Backend deducts gold and grants item atomically
4. Client syncs updated inventory from response

**No Godot dedicated server changes needed** - the game server doesn't handle economy, only multiplayer physics/combat.

---

## New API Endpoint

### `POST /api/vendor/purchase`

**Auth:** Bearer token (same as other authenticated endpoints)

**Request Body:**
```json
{
    "item_id": "rusty_blade",
    "vendor_type": "weapons",
    "quantity": 1
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `item_id` | string | Yes | ID from shop JSON files |
| `vendor_type` | string | Yes | One of: `weapons`, `armor`, `misc`, `tools` |
| `quantity` | int | No | Default 1. For stackable items only. |

**Success Response (200):**
```json
{
    "success": true,
    "item": {
        "id": "rusty_blade",
        "name": "Rusty Blade",
        "weapon_type": "sword",
        "base_damage": 5,
        "...": "full item data"
    },
    "gold_spent": 50,
    "new_gold_balance": 450
}
```

**Error Responses:**

| Code | Error | Description |
|------|-------|-------------|
| 400 | `INSUFFICIENT_GOLD` | Player doesn't have enough gold |
| 400 | `ITEM_NOT_FOUND` | Item ID doesn't exist in catalog |
| 400 | `INVALID_VENDOR_TYPE` | Unknown vendor type |
| 400 | `LEVEL_REQUIREMENT_NOT_MET` | Player level too low |
| 401 | `UNAUTHORIZED` | Invalid/missing auth token |
| 500 | `PURCHASE_FAILED` | Database transaction failed |

**Error Response Format:**
```json
{
    "success": false,
    "error": "INSUFFICIENT_GOLD",
    "message": "You need 50 gold but only have 30",
    "required_gold": 50,
    "current_gold": 30
}
```

---

## Backend Implementation Details

### 1. Item Catalog (Server-side Source of Truth)

Load shop data from JSON files at startup:
- `data/shop_weapons.json` - weapons array
- `data/shop_armor.json` - armor array
- `data/shop_misc.json` - items array (misc)

```python
# app/services/vendor_service.py

import json
from pathlib import Path

class VendorService:
    def __init__(self):
        self.catalogs = {}
        self._load_catalogs()

    def _load_catalogs(self):
        data_dir = Path(__file__).parent.parent.parent / "data"

        # Weapons
        with open(data_dir / "shop_weapons.json") as f:
            self.catalogs["weapons"] = {
                item["id"]: item for item in json.load(f)["weapons"]
            }

        # Armor
        with open(data_dir / "shop_armor.json") as f:
            self.catalogs["armor"] = {
                item["id"]: item for item in json.load(f)["armor"]
            }

        # Misc
        with open(data_dir / "shop_misc.json") as f:
            self.catalogs["misc"] = {
                item["id"]: item for item in json.load(f)["items"]
            }

    def get_item(self, vendor_type: str, item_id: str) -> dict | None:
        return self.catalogs.get(vendor_type, {}).get(item_id)

    def get_price(self, vendor_type: str, item_id: str) -> int | None:
        item = self.get_item(vendor_type, item_id)
        return item.get("price") if item else None
```

### 2. Purchase Validation Logic

```python
# app/routes/vendor_routes.py

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from app.services.vendor_service import VendorService
from app.dependencies import get_current_user, get_db

router = APIRouter(prefix="/api/vendor", tags=["vendor"])
vendor_service = VendorService()

class PurchaseRequest(BaseModel):
    item_id: str
    vendor_type: str  # "weapons", "armor", "misc", "tools"
    quantity: int = 1

class PurchaseResponse(BaseModel):
    success: bool
    item: dict | None = None
    gold_spent: int = 0
    new_gold_balance: int = 0
    error: str | None = None
    message: str | None = None

@router.post("/purchase", response_model=PurchaseResponse)
async def purchase_item(
    request: PurchaseRequest,
    user = Depends(get_current_user),
    db = Depends(get_db)
):
    # 1. Validate vendor type
    if request.vendor_type not in ["weapons", "armor", "misc", "tools"]:
        raise HTTPException(400, detail={
            "error": "INVALID_VENDOR_TYPE",
            "message": f"Unknown vendor type: {request.vendor_type}"
        })

    # 2. Get item from catalog
    item = vendor_service.get_item(request.vendor_type, request.item_id)
    if not item:
        raise HTTPException(400, detail={
            "error": "ITEM_NOT_FOUND",
            "message": f"Item not found: {request.item_id}"
        })

    # 3. Get player's current character
    character = get_active_character(user, db)  # Implement based on your model

    # 4. Check level requirement
    required_level = item.get("required_level", 1)
    if character.level < required_level:
        raise HTTPException(400, detail={
            "error": "LEVEL_REQUIREMENT_NOT_MET",
            "message": f"Requires level {required_level}, you are level {character.level}"
        })

    # 5. Calculate total cost
    price = item.get("price", 0)
    total_cost = price * request.quantity

    # 6. Check gold balance
    if character.gold < total_cost:
        raise HTTPException(400, detail={
            "error": "INSUFFICIENT_GOLD",
            "message": f"You need {total_cost} gold but only have {character.gold}",
            "required_gold": total_cost,
            "current_gold": character.gold
        })

    # 7. Atomic transaction: deduct gold + add item
    try:
        character.gold -= total_cost
        add_item_to_inventory(character, item, request.quantity)  # Implement
        db.commit()
    except Exception as e:
        db.rollback()
        raise HTTPException(500, detail={
            "error": "PURCHASE_FAILED",
            "message": "Transaction failed, please try again"
        })

    # 8. Return success
    return PurchaseResponse(
        success=True,
        item=item,
        gold_spent=total_cost,
        new_gold_balance=character.gold
    )
```

### 3. Database Considerations

The character's gold is currently stored in a JSON blob (`character_data` column in Characters table). You have two options:

**Option A: Keep gold in JSON blob (simpler)**
- Parse `character_data` JSON to get/set gold
- Risk of race conditions if multiple purchases happen simultaneously

**Option B: Add `gold` column to Characters table (recommended)**
- Add migration: `ALTER TABLE characters ADD COLUMN gold INTEGER DEFAULT 100`
- Enables atomic updates with database-level locking
- Prevents race conditions

```python
# Alembic migration for Option B
def upgrade():
    op.add_column('characters', sa.Column('gold', sa.Integer(),
                  nullable=False, server_default='100'))

def downgrade():
    op.drop_column('characters', 'gold')
```

### 4. Inventory Storage

Items are stored in the `character_data` JSON blob under `inventory`. When adding purchased items:

```python
def add_item_to_inventory(character, item: dict, quantity: int = 1):
    """Add item to character's inventory in character_data blob."""
    data = json.loads(character.character_data or "{}")

    if "inventory" not in data:
        data["inventory"] = []

    # Check if item is stackable and already exists
    if item.get("stackable", False):
        for inv_item in data["inventory"]:
            if inv_item.get("id") == item["id"]:
                inv_item["quantity"] = inv_item.get("quantity", 1) + quantity
                character.character_data = json.dumps(data)
                return

    # Add new item entry
    new_item = {
        "id": item["id"],
        "name": item["name"],
        "type": item.get("type", item.get("weapon_type", "misc")),
        "quantity": quantity,
        # Include other relevant fields
    }
    data["inventory"].append(new_item)
    character.character_data = json.dumps(data)
```

---

## Client-Side Changes (Godot)

### Current Flow (Vendor.gd)
```gdscript
func _on_buy_button_pressed():
    var price = selected_item.price
    if CharacterStats.gold >= price:
        CharacterStats.gold -= price
        InventoryManager.add_item(selected_item)
        # ... update UI
```

### New Flow
```gdscript
func _on_buy_button_pressed():
    var item_data = {
        "item_id": selected_item.id,
        "vendor_type": current_vendor_type,
        "quantity": 1
    }

    # Show loading indicator
    buy_button.disabled = true

    # Call backend
    var response = await AshbaneAuth.post_authenticated(
        "/api/vendor/purchase",
        item_data
    )

    buy_button.disabled = false

    if response.success:
        # Update local state from server response
        CharacterStats.gold = response.new_gold_balance
        InventoryManager.add_item(response.item)
        show_notification("Purchased " + response.item.name)
    else:
        # Show error
        show_notification(response.message)
```

Key changes:
1. Don't modify gold locally before server confirms
2. Use server response to update gold balance
3. Handle error cases gracefully
4. Disable buy button during request to prevent double-purchases

---

## Shop Data Files Location

Copy these files to the backend data folder (if not already there):
- `data/shop_weapons.json` (335 lines, 24 weapons)
- `data/shop_armor.json` (882 lines, 46 armor pieces)
- `data/shop_misc.json` (30 lines, 2 items)

These become the **server-side source of truth** for prices and item stats.

---

## Testing Checklist

1. [ ] Purchase succeeds with sufficient gold
2. [ ] Purchase fails with insufficient gold (no gold deducted)
3. [ ] Purchase fails for non-existent item
4. [ ] Level requirement enforced
5. [ ] Quantity multiplier works for stackables
6. [ ] Race condition: two rapid purchases don't overdraft
7. [ ] Inventory correctly updated in database
8. [ ] Client receives and displays errors properly

---

## Migration Path

1. **Phase 1:** Deploy backend with new endpoint (backwards compatible)
2. **Phase 2:** Update Godot client to use new endpoint
3. **Phase 3:** Remove client-side purchase logic (validation only)

The endpoint can be deployed first without breaking existing clients. Old clients will still work (just insecure), new clients will be secure.

---

## Security Notes

- All price data comes from server-side JSON files
- Client-provided prices are **never trusted**
- Gold balance is validated server-side before any deduction
- Database transactions ensure atomicity
- Rate limiting recommended (prevent purchase spam)

---

## Files to Create/Modify

### Backend (New Files)
- `app/routes/vendor_routes.py` - New route file
- `app/services/vendor_service.py` - Item catalog service

### Backend (Modify)
- `app/main.py` - Include new router
- `data/` - Ensure shop JSON files are present

### Client (Modify)
- `scripts/systems/Vendor.gd` - Call backend instead of local purchase
- `scripts/systems/AshbaneAuth.gd` - May need new helper method

---

## Questions for Backend Engineer

1. Is `character.gold` in a dedicated column or JSON blob? If blob, recommend migrating to column.
2. What's the current `get_active_character()` pattern? Need to retrieve current character for user.
3. Any existing rate limiting middleware to apply to this endpoint?
