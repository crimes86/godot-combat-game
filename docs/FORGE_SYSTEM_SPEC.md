# Forge System Specification

> Achievements become weapons and armor. The Forge is where digital trophies materialize into in-game power.

---

## Overview

The Forge system bridges the web-based NFT minting experience with in-game item acquisition. Players forge achievements on the web, then collect the resulting items in-game at the Forge.

### Core Loop

```
WEB: Browse achievements → Select → Mint NFT
                ↓
API: pending_forges[] updated, broadcast if Legendary+
                ↓
GAME: Armory/World shows "Items waiting at Forge"
                ↓
PLAYER: Opens Forge UI → Claims items → Equips
                ↓
GLOBAL: Feed announces legendary forges to all players
```

### Design Principles

1. **Anticipation over spectacle** - Build desire to "get in game and open that"
2. **Dual access** - Armory (convenient) + In-World (immersive)
3. **Social proof** - Others see what you forge, global feed for legendaries
4. **LPC compatible** - All items work with existing sprite system

---

## API Contract

### Profile Response Addition

```json
GET /api/me

{
  "user_id": 12345,
  "username": "VeteranPlayer",
  "pending_forges": [
    {
      "token_id": "0xabc123...",
      "forged_at": "2024-12-07T15:30:00Z",
      "achievement": {
        "provider": "steam",
        "app_id": "374320",
        "api_name": "THE_DARK_SOUL",
        "display_name": "The Dark Soul",
        "rarity_tier": "Legendary"
      },
      "unlocks": {
        "item_id": "coiled_sword",
        "item_type": "weapon",
        "item_name": "Coiled Sword",
        "item_rarity": "legendary"
      },
      "is_earned": true
    }
  ],
  "forged_items": [
    // Already claimed items
  ]
}
```

### Claim Endpoint

```json
POST /api/forge/claim

Request:
{
  "token_ids": ["0xabc123..."]
}

Response:
{
  "claimed": [
    {
      "token_id": "0xabc123...",
      "item_id": "coiled_sword",
      "success": true
    }
  ]
}
```

### Global Feed Endpoint

```json
GET /api/forge/feed?since={timestamp}&min_rarity=legendary

Response:
{
  "events": [
    {
      "event_id": "evt_123",
      "timestamp": "2024-12-07T15:30:00Z",
      "username": "DarkLord99",
      "achievement_name": "The Dark Soul",
      "item_name": "Coiled Sword",
      "item_rarity": "legendary",
      "is_earned": true
    }
  ]
}
```

---

## UI Components

### 1. Armory Integration

**Location:** Armory.gd - Middle or Right column

**Elements:**
- Forge button with pending count badge
- Glowing/pulsing animation when items pending
- Opens ForgeUI as overlay

```
┌─────────────────────────────────┐
│  ⚒️ THE FORGE                   │
│                                 │
│  🔥 2 items ready to claim      │
│                                 │
│  [ OPEN FORGE ]  ← Glows/pulses │
│                                 │
│  [ Browse Forgeable → ]         │
│    Opens web in browser         │
└─────────────────────────────────┘
```

### 2. ForgeUI (Shared Component)

**File:** `scripts/ui/ForgeUI.gd`
**Scene:** `scenes/ui/ForgeUI.tscn`

**Can be opened from:**
- Armory (overlay)
- In-world Forge object (popup)

```
┌──────────────────────────────────────────────────────┐
│                  ⚒️ THE FORGE ⚒️                     │
│──────────────────────────────────────────────────────│
│                                                      │
│  PENDING ITEMS                                       │
│  ┌────────┐  ┌────────┐  ┌────────┐                 │
│  │   ??   │  │   ??   │  │        │  ← Silhouettes  │
│  │  ⚔️?   │  │  🛡️?   │  │        │    until claimed│
│  │        │  │        │  │        │                 │
│  │ Epic   │  │ Legend │  │        │                 │
│  └────────┘  └────────┘  └────────┘                 │
│                                                      │
│           [ CLAIM NEXT ]  [ CLAIM ALL ]             │
│                                                      │
│──────────────────────────────────────────────────────│
│  GLOBAL FORGE FEED                     [Legendary+] │
│                                                      │
│  ⚔️ 2m ago  DarkLord99 forged Coiled Sword         │
│  🛡️ 15m ago AshKetchum forged Grass Crest Shield   │
│  ⚔️ 1h ago  VetPlayer forged Moonlight Greatsword  │
│                                                      │
│──────────────────────────────────────────────────────│
│  [ BROWSE FORGEABLE ACHIEVEMENTS → ]                 │
│──────────────────────────────────────────────────────│
│                               [ CLOSE ]              │
└──────────────────────────────────────────────────────┘
```

### 3. Pending Item Card (Pre-Claim)

Shows silhouette with rarity glow, teasing what's inside:

```
┌────────────────┐
│    ░░░░░░░░    │  ← Silhouette shape hints at item type
│   ░░░⚔️░░░░   │
│    ░░░░░░░░    │
│                │
│  ── ? ? ? ──   │  ← Name hidden
│   LEGENDARY    │  ← Rarity shown (builds anticipation)
│                │
│  From: Steam   │
│  THE_DARK_SOUL │  ← Achievement shown
└────────────────┘
```

### 4. Claim Sequence (Per Item)

**Duration:** 3-4 seconds total
**Tone:** Satisfying reveal, not explosive

```gdscript
# Claim sequence steps
func _claim_sequence(pending_item: Dictionary):
    # Step 1: Silhouette pulses (1s)
    # - Glow intensifies
    # - Subtle particle buildup
    await _pulse_silhouette(1.0)

    # Step 2: Reveal (1s)
    # - Silhouette fades out
    # - Actual item sprite fades in
    # - Rarity-colored flash
    await _reveal_item(pending_item)

    # Step 3: Item card (1.5s)
    # - Card slides in from side
    # - Shows: name, stats, provenance badge
    # - Subtle sound effect
    await _show_item_card(pending_item)

    # Step 4: Choice
    # - "EQUIP NOW" or "TO INVENTORY"
    # - If weapon/armor, preview on character
    var choice = await _show_equip_choice()

    # Step 5: Finalize
    _add_to_inventory(pending_item)
    _mark_claimed_api(pending_item.token_id)
```

### 5. Revealed Item Card

```
┌────────────────────────────────────┐
│  ┌──────────┐                      │
│  │          │   COILED SWORD       │
│  │   ⚔️     │   ════════════       │
│  │          │   Legendary Weapon   │
│  └──────────┘                      │
│                                    │
│  "A sword twisted by the First    │
│   Flame, wielded by those who     │
│   linked the fire."               │
│                                    │
│  ┌────────────────────────────┐   │
│  │ ⭐ EARNED - Original Holder │   │  ← Gold badge
│  └────────────────────────────┘   │
│                                    │
│  From: The Dark Soul (Steam)       │
│  Forged: Dec 7, 2024              │
│                                    │
│  [ EQUIP NOW ]  [ TO INVENTORY ]  │
└────────────────────────────────────┘
```

---

## In-World Forge Object

### Location
- Town/safe zone near spawn
- Visible, central location
- Near other services (vendor, blacksmith)

### Visual Design
```
     ╔═══════════════╗
     ║   🔥 🔥 🔥   ║  ← Animated flames (GPUParticles2D)
     ║  ┌───────┐   ║
     ║  │ ANVIL │   ║  ← Anvil sprite
     ║  └───────┘   ║
     ╚═══════════════╝

When items pending:
- Flames burn brighter/higher
- Subtle pulsing glow on ground
- Floating indicator: "🔥 2"
```

### Interaction
```gdscript
# ForgeObject.gd
extends Area2D

@export var forge_ui_scene: PackedScene

func _on_body_entered(body):
    if body.is_in_group("player"):
        _show_interaction_prompt()
        # "Press E to open Forge (2 items waiting)"

func _on_interact():
    var pending = MantleAuth.get_pending_forges()
    if pending.size() > 0:
        var ui = forge_ui_scene.instantiate()
        ui.open_from_world(self)
        get_tree().current_scene.add_child(ui)
    else:
        # Show "no items" message or open browse anyway
        _show_empty_forge_message()
```

---

## Achievement → Item Mapping

### Database Structure

**File:** `scripts/systems/ForgeItemDB.gd`

```gdscript
extends Node

# Maps achievement API names to in-game items
const FORGE_ITEMS = {
    # ═══════════════════════════════════════════════════
    # DARK SOULS 3
    # ═══════════════════════════════════════════════════
    "steam_374320_THE_DARK_SOUL": {
        "item_id": "coiled_sword",
        "item_name": "Coiled Sword",
        "item_type": "weapon",
        "weapon_class": "sword",
        "slot": "weapon",
        "rarity": "legendary",
        "description": "A sword twisted by the First Flame.",
        "lore": "Wielded by those who linked the fire.",
        "sprites": {
            "icon": "res://assets/icons/weapons/coiled_sword.png",
            "walk": "res://assets/equipment/weapons/coiled_sword/walk.png",
            "slash": "res://assets/equipment/weapons/coiled_sword/slash.png",
            "thrust": "res://assets/equipment/weapons/coiled_sword/thrust.png",
            "hurt": "res://assets/equipment/weapons/coiled_sword/hurt.png"
        },
        "effects": ["ember_trail", "flame_idle_glow"],
        "stats": {
            "damage_bonus": 5,
            "fire_damage": 3
        },
        "cosmetic_only": false
    },

    # ═══════════════════════════════════════════════════
    # ELDEN RING
    # ═══════════════════════════════════════════════════
    "steam_1245620_ELDEN_LORD": {
        "item_id": "elden_crown",
        "item_name": "Elden Lord's Crown",
        "item_type": "armor",
        "slot": "head",
        "rarity": "legendary",
        "description": "Crown of the Elden Lord.",
        "sprites": {
            "icon": "res://assets/icons/armor/elden_crown.png",
            "walk": "res://assets/equipment/armor/head/elden_crown/walk.png",
            # ... etc
        },
        "effects": ["golden_glow", "erdtree_particles"],
        "stats": {},
        "cosmetic_only": true  # Pure flex, no stats
    },

    # ═══════════════════════════════════════════════════
    # WORLD OF WARCRAFT (Battle.net)
    # ═══════════════════════════════════════════════════
    "battlenet_wow_THUNDERFURY": {
        "item_id": "thunderfury",
        "item_name": "Thunderfury, Blessed Blade",
        "item_type": "weapon",
        "weapon_class": "sword",
        "slot": "weapon",
        "rarity": "legendary",
        "description": "Did someone say...?",
        "sprites": {
            "icon": "res://assets/icons/weapons/thunderfury.png",
            # ...
        },
        "effects": ["chain_lightning_idle", "electric_trail"],
        "stats": {
            "damage_bonus": 3,
            "lightning_damage": 5
        },
        "cosmetic_only": false
    }
}

# Lookup function
func get_item_for_achievement(provider: String, app_id: String, api_name: String) -> Dictionary:
    var key = "%s_%s_%s" % [provider, app_id, api_name]
    return FORGE_ITEMS.get(key, {})

# Get all forgeable achievements that have item mappings
func get_all_forgeable() -> Array:
    return FORGE_ITEMS.keys()
```

### Item Rarity Tiers

| Rarity | Source | Visual Treatment |
|--------|--------|------------------|
| Rare | Rare achievements (< 10% unlock) | Blue glow, subtle particles |
| Epic | Epic achievements (< 5% unlock) | Purple glow, medium particles |
| Legendary | Legendary achievements (< 1% unlock) | Orange glow, fire/special particles |
| Mythic | Ultra-rare / special events | Pink/magenta, heavy effects |

---

## Global Forge Feed

### Purpose
- Social proof: "Others are forging cool stuff"
- FOMO: "I want that too"
- Discovery: "I didn't know that achievement unlocked THAT"

### Implementation

```gdscript
# GlobalForgeFeed.gd
extends Node

signal new_forge_event(event: Dictionary)

const POLL_INTERVAL = 30.0  # seconds
const MIN_RARITY = "legendary"  # Only show legendary+

var _last_event_time: String = ""
var _poll_timer: Timer

func _ready():
    _start_polling()

func _start_polling():
    _poll_timer = Timer.new()
    _poll_timer.wait_time = POLL_INTERVAL
    _poll_timer.timeout.connect(_fetch_feed)
    add_child(_poll_timer)
    _poll_timer.start()
    _fetch_feed()  # Initial fetch

func _fetch_feed():
    var url = MantleAuth.get_api_base() + "/api/forge/feed"
    url += "?min_rarity=" + MIN_RARITY
    if _last_event_time != "":
        url += "&since=" + _last_event_time
    # ... HTTP request ...

func _on_feed_response(events: Array):
    for event in events:
        new_forge_event.emit(event)
        _last_event_time = event.get("timestamp", _last_event_time)
```

### Toast Notification (In-Game)

```
┌─────────────────────────────────────────┐
│ ⚔️ DarkLord99 forged [Coiled Sword]    │
│    from "The Dark Soul"                 │
└─────────────────────────────────────────┘
     ↑ Appears bottom-right, fades after 5s
```

---

## Visual Effects (LPC Compatible)

### Item-Specific Effects

| Effect ID | Description | Implementation |
|-----------|-------------|----------------|
| `ember_trail` | Embers fall from weapon while moving | GPUParticles2D child of weapon sprite |
| `flame_idle_glow` | Subtle orange pulse when idle | AnimationPlayer modulating weapon |
| `chain_lightning_idle` | Occasional electric arc | Line2D with shader |
| `golden_glow` | Soft gold ambient light | PointLight2D with low energy |
| `erdtree_particles` | Floating golden leaves | GPUParticles2D |

### Forge UI Effects

| Element | Effect |
|---------|--------|
| Pending silhouette | Pulsing glow matching rarity color |
| Reveal moment | Flash + particles burst outward |
| Item card appear | Slide in from right with subtle bounce |
| Claim button | Gentle pulse when items pending |

---

## File Structure

```
scripts/
├── systems/
│   ├── ForgeItemDB.gd        # Achievement → Item mapping
│   └── GlobalForgeFeed.gd    # Legendary feed polling
├── ui/
│   ├── ForgeUI.gd            # Main forge interface
│   ├── ForgeItemCard.gd      # Individual item display
│   └── ForgeFeedEntry.gd     # Feed list item
└── world/
    └── ForgeObject.gd        # In-world interactable

scenes/
├── ui/
│   ├── ForgeUI.tscn
│   ├── ForgeItemCard.tscn
│   └── ForgeFeedEntry.tscn
└── world/
    └── Forge.tscn            # In-world forge object
```

---

## Integration Checklist

### Phase 1: Core Forge UI
- [ ] Create ForgeUI.gd and ForgeUI.tscn
- [ ] Pending items display with silhouettes
- [ ] Claim sequence animation
- [ ] Item card reveal
- [ ] Add to inventory integration

### Phase 2: Armory Integration
- [ ] Add Forge button to Armory
- [ ] Pending count badge
- [ ] Pulsing animation when items waiting
- [ ] Open ForgeUI as overlay

### Phase 3: In-World Forge
- [ ] Create Forge.tscn world object
- [ ] Interaction prompt
- [ ] Visual effects (flames, glow)
- [ ] Connect to ForgeUI

### Phase 4: Global Feed
- [ ] GlobalForgeFeed.gd polling
- [ ] Feed display in ForgeUI
- [ ] Toast notifications during gameplay

### Phase 5: Item Effects
- [ ] Implement effect system for forged items
- [ ] Ember trail particles
- [ ] Glow effects
- [ ] Provenance badge on equipped items

---

## Open Questions

1. **Stats vs Cosmetic Only?**
   - Should forged items have stat bonuses?
   - Or purely cosmetic with provenance flex?
   - Recommendation: Cosmetic primary, minor stat bonuses for legendary+

2. **Trading Impact**
   - If someone trades a forged NFT, do they lose the item in-game?
   - Recommendation: Yes, ownership = access. Re-verify on login.

3. **Duplicate Forges**
   - Can multiple players forge the same achievement?
   - Each gets unique NFT but same item type?
   - Recommendation: Yes, but "First Forger" gets special variant?

4. **Offline Forging**
   - What if player forges while offline/not logged in?
   - Recommendation: Items queue, claimed on next login

---

## Success Metrics

- **Anticipation:** Players check web, then rush to game to claim
- **Social:** Global feed creates FOMO, players share clips
- **Retention:** Daily login to check for new forgeable achievements
- **Virality:** "How did you get that sword?" → explains forge system
