# Guest Progress Sync Spec

**Status:** Pending Implementation
**Priority:** Medium (UX improvement)

## Overview

When a guest user authenticates in-game, their local progress should be preserved if the account is brand new. This endpoint receives guest progress and initializes the character if one doesn't exist.

## Endpoint

### `POST /api/character/initialize`

Initialize character with guest progress (only if character doesn't exist).

**Auth:** Bearer token (required - user just authenticated)

**Request Body:**
```json
{
    "gold": 150,
    "level": 3,
    "experience": 450,
    "inventory": [
        {"id": "health_potion", "name": "Health Potion", "quantity": 5, "type": "consumable"},
        {"id": "iron_sword", "name": "Iron Sword", "quantity": 1, "type": "weapon"}
    ],
    "equipped_weapon": "iron_sword",
    "equipped_armor": "leather_chest",
    "equipped_tool": "iron_pickaxe"
}
```

**Response (201 - Character Created):**
```json
{
    "success": true,
    "message": "Character initialized with guest progress",
    "character": {
        "gold": 150,
        "level": 3,
        "experience": 450,
        "is_new": true
    }
}
```

**Response (200 - Character Exists):**
```json
{
    "success": true,
    "message": "Existing character loaded",
    "character": {
        "gold": 5000,
        "level": 15,
        "experience": 12500,
        "is_new": false
    }
}
```

The client should check `is_new`:
- `true` → Guest progress was applied, continue playing
- `false` → Existing character loaded, update local state to match server

## Client Behavior

When `is_new: false`:
1. Show message: "Welcome back! Loading your existing character..."
2. Update local CharacterStats with server values
3. Refresh inventory from server
4. Continue playing with existing character

## Security Notes

- Only accepts reasonable starting values (cap gold at 1000, level at 5 for initialization)
- Validates inventory items exist in item database
- Logs initialization for anti-cheat review
- Cannot be called again after character exists (idempotent - just returns existing)

## Implementation Notes

### Backend (FastAPI)

```python
@router.post("/character/initialize")
async def initialize_character(
    request: CharacterInitRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Check if character exists
    character = db.query(Character).filter(Character.user_id == current_user.id).first()

    if character:
        # Return existing character
        return {
            "success": True,
            "message": "Existing character loaded",
            "character": {
                "gold": character.gold,
                "level": character.level,
                "experience": character.experience,
                "is_new": False
            }
        }

    # Create new character with guest progress (capped values)
    character = Character(
        user_id=current_user.id,
        gold=min(request.gold, 1000),  # Cap at 1000
        level=min(request.level, 5),    # Cap at level 5
        experience=min(request.experience, 2000),
        # ... inventory handling
    )
    db.add(character)
    db.commit()

    return {
        "success": True,
        "message": "Character initialized with guest progress",
        "character": {..., "is_new": True}
    }
```

### Godot Client

Already implemented in `AuthOverlay.gd`:
- Captures progress before auth
- Sends to `/api/character/initialize` after auth success
- Handles response and updates local state if needed
