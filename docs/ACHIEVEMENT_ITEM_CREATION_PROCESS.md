# Achievement-to-Item Creation Process

Complete workflow from "we want to add this achievement" to "item is live in Dreadland."

## Prerequisites

Before starting, read these documents:
- `docs/FORGE_ITEM_PHILOSOPHY.md` - Core principles, item hierarchy, quotas
- `docs/FORGE_ACHIEVEMENT_SHORTLIST.md` - Curated achievement list by provider
- `docs/GODOT_ITEM_HANDOFF.md` - Technical specs for sprites and effects

---

## Phase 1: Achievement Selection

### Step 1.1: Check Quotas

Before proposing any new achievement, verify we have room:

```
Current Allocation (target 30-40 total):
├── Steam: 20-25 slots
├── Battle.net: 5-8 slots
├── PlayStation: 4-6 slots
├── Xbox: 2-4 slots
├── Discord: 3-4 slots
├── GitHub: 3-4 slots
├── Reddit: 2-3 slots
├── Twitch: 2-3 slots
├── Roblox: 2-3 slots
└── Other: 2-3 slots

Check: GET /api/catalog/mappings to see current count
```

### Step 1.2: The Pitch Test

Every achievement MUST pass this test:

> "A casual gamer hears about Dreadland and thinks:
> 'I did [X] in [Game] - that HAS to count for something here!'"

**Document the pitch:**
```
PITCH TEST TEMPLATE:
━━━━━━━━━━━━━━━━━━━━
Achievement: _________________
Game: _________________
Provider: _________________

Pitch: "I did [achievement] in [game]"
Expected Reaction: _________________

Holy Shit Factor (1-10): ___
Recognition Factor (1-10): ___
━━━━━━━━━━━━━━━━━━━━
Pass if both factors >= 7
```

### Step 1.3: Verify Achievement Data

For **Steam**:
```bash
# Get achievement details from Steam API
curl "https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?gameid={APP_ID}"

# Verify API name matches expected format
```

For **Battle.net**:
```python
# Check our WoW achievement database
# File: backend/app/data/wow_achievements.json
# Search by achievement name or ID
```

For **PlayStation/Xbox**:
- Use platform-specific APIs
- Verify achievement exists and get exact identifier

### Step 1.4: Check for Duplicates

Before adding:
- [ ] Achievement not already mapped (check `items.json`)
- [ ] No similar item exists (e.g., don't add 3 fire swords)
- [ ] Doesn't overlap with cross-platform version

---

## Phase 2: Item Design

### Step 2.1: Choose Item Type

Distribute across types to avoid "everyone has a sword":

| Type | Current | Max | Notes |
|------|---------|-----|-------|
| weapon | ~15 | 18 | Variety of weapon_types |
| armor_head | ~4 | 6 | Crowns, helms, hats |
| accessory | ~8 | 12 | Badges, talismans |
| cape | ~1 | 3 | Reserved for prestige |
| shield | ~1 | 3 | |
| armor_chest | ~1 | 3 | RARE - Dreadland domain |

### Step 2.2: Create Item Specification

```json
{
  "item_id": "snake_case_unique_id",
  "item_name": "Display Name",
  "item_type": "weapon|armor_head|accessory|cape|shield",
  "weapon_type": "sword|katana|spear|etc (if weapon)",
  "description": "One line description.",
  "lore": "One line of flavor text.",
  "base_rarity": "rare|epic|legendary",
  "theme": "existing_theme_or_new",
  "visuals": {
    "icon_url": "/static/items/icons/{item_id}.png",
    "sprite_folder": "weapons/{item_id}",
    "effect": "effect_name_from_ForgeVisualEffects",
    "glow_color": "#HEXCOLOR"
  },
  "has_sprites": false,
  "has_icon": false
}
```

### Step 2.3: Assign Theme

If the game doesn't have a theme, create one:

```json
"new_theme_name": {
  "display_name": "Game Name",
  "app_ids": ["12345"],
  "color": "#HEXCOLOR",
  "effects": ["effect1", "effect2", "effect3"]
}
```

Add to `items.json` under `themes`.

### Step 2.4: Register Effect (if new)

If the item needs a new visual effect, add to `ForgeVisualEffects.gd` under `EFFECT_CONFIGS`:

```gdscript
"new_effect_name": {
    "type": "particles|glow|trail|aura",
    "color": Color(R, G, B, A),           # Primary color
    "secondary_color": Color(R, G, B, A), # Optional gradient
    "intensity": 1.0-1.5,
    "particle_count": 8-20,
    "gravity": 0,                          # Positive = fall, negative = rise
    "trigger": "always|on_attack|on_kill"  # When effect activates
},
```

**Effect Types:**
- `particles` - Floating particles around weapon (blood_particles, cell_particles)
- `glow` - Radial glow emanating from weapon
- `trail` - Motion trail following weapon swings
- `aura` - Pulsing aura surrounding player

**Important:** The effect name in `items.json` → `visuals.effect` must match a key in `EFFECT_CONFIGS`.

---

## Phase 3: Add to items.json

### Step 3.1: Add Achievement Mapping

In `backend/data/items.json`, under `achievement_mappings`:

```json
"achievement_mappings": {
  // ... existing mappings ...
  "{app_id}:{API_NAME}": "{item_id}"
}
```

**Key Format:**
- Steam: `374320:THE_DARK_SOUL`
- WoW: `battlenet:{achievement_id}`
- PlayStation: `psn:{trophy_id}`
- Xbox: `xbox:{achievement_id}`
- Discord: `discord:BADGE_NAME`
- GitHub: `github:BADGE_NAME`

### Step 3.2: Add Item Definition

In `items` array:

```json
{
  "item_id": "your_item_id",
  // ... full item spec from Step 2.2 ...
  "has_sprites": false,
  "has_icon": false
}
```

### Step 3.3: Update Version

```json
{
  "version": "1.X.0",
  "_changelog": "vX.X.0: Added [item_name] for [achievement]"
}
```

---

## Phase 4: Create Assets

### Step 4.1: Create Icon (Required First)

**Specifications:**
- Size: 64x64 PNG
- Format: RGBA with transparency
- Weapons: 45° diagonal, tip upper-right
- Armor/Shields/Capes: Upright, centered
- Padding: 4px minimum from edge

**Method A: Extract from Walk Sprite (Best for weapons)**

For weapons, extract the horizontal frame from walk.png (row 0, frame 7). This matches gun icons for consistency:

```python
# Extract weapon icon from walk sprite (Python)
from PIL import Image
from pathlib import Path

walk_path = Path('assets/equipment/forged/weapons/{item_id}/walk.png')
icon_out = Path('assets/icons/forged/weapons/{item_id}.png')

img = Image.open(walk_path).convert('RGBA')
FRAME_SIZE = 64
frame_col = 7     # Frame 7 - horizontal position (0-indexed)
frame_row = 0     # Row 0 - up-facing direction (weapon shown horizontal)

# Extract frame
x, y = frame_col * FRAME_SIZE, frame_row * FRAME_SIZE
frame = img.crop((x, y, x + FRAME_SIZE, y + FRAME_SIZE))

# Crop to content and scale to fill 64x64 with padding
bbox = frame.getbbox()
weapon = frame.crop((max(0, bbox[0]-2), max(0, bbox[1]-2),
                     min(64, bbox[2]+2), min(64, bbox[3]+2)))
scale = min(56 / weapon.width, 56 / weapon.height)
weapon_scaled = weapon.resize((int(weapon.width * scale), int(weapon.height * scale)), Image.Resampling.NEAREST)

# Center in 64x64 canvas
canvas = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
canvas.paste(weapon_scaled, ((64 - weapon_scaled.width) // 2, (64 - weapon_scaled.height) // 2), weapon_scaled)
canvas.save(icon_out, 'PNG')
```

**Method B: Generate from Walk Sprite (with tinting)**

```bash
python tools/lpc_sprite_tinter.py icon <sprite_path> <icon_path> --preset <preset> --frame X,Y
# Presets: golden, silver, crimson, purple, blue, green, dark, ember, white, infernal
```

**Method C: Manual Creation**

- Reference: Source game's item art
- Create: Aseprite, Photoshop, GIMP
- Validate: `python assets/icons/forged/icon_standards.py --validate`

**Enhance to 256x256 (Required):**

After creating the 64x64 icon, run the enhancer:

```bash
python tools/icon_enhancer.py --source forged --preview
```

This creates 256x256 versions in `assets/icons/enhanced/forged/` using EPX+Lanczos upscaling.

**Export to:**
```
assets/icons/forged/{category}/{item_id}.png      # 64x64 base
assets/icons/enhanced/forged/{category}/{item_id}.png  # 256x256 (auto-generated)

Categories:
- weapons/
- armor/
- shields/
- accessories/
- capes/
```

### Step 4.2: Create Sprites (If Applicable)

Accessories don't need sprites. Weapons/Armor do.

**Standard LPC Sprite Requirements (64px tiles):**

| Animation | Dimensions | Required |
|-----------|------------|----------|
| walk.png | 576x256 (9 frames x 4 dirs @ 64px) | YES |
| slash.png | 384x256 (6 frames x 4 dirs @ 64px) | YES (weapons) |
| thrust.png | 512x256 (8 frames x 4 dirs @ 64px) | Optional |
| hurt.png | 384x64 (6 frames x 1 dir @ 64px) | Optional |

**Oversize LPC Sprites (128px tiles) - For prestige weapons:**

| Animation | Dimensions | Required |
|-----------|------------|----------|
| walk.png | 832x256 (13 frames x 4 dirs @ 64px) | YES |
| slash.png | 768x512 (6 frames x 4 dirs @ 128px) | YES |
| slash2.png | 768x512 (6 frames x 4 dirs @ 128px) | Optional (multi-slash) |
| slash3.png | 768x512 (6 frames x 4 dirs @ 128px) | Optional (multi-slash) |
| hurt.png | 832x64 (13 frames x 1 dir @ 64px) | Optional |

**Multi-Slash Weapons:**
For prestige weapons with attack variety, add `slash2.png` and/or `slash3.png`. The game automatically cycles through available slash animations on each attack.

Set `"multi_slash": true` in items.json to flag these weapons.

**Tools:**
- [Universal LPC Generator](https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/)
- Manual pixel art in Aseprite

**Export to:**
```
assets/equipment/forged/
├── weapons/{item_id}/
│   ├── walk.png
│   ├── slash.png
│   ├── slash2.png      # Optional multi-slash variant
│   ├── slash3.png      # Optional multi-slash variant
│   └── hurt.png        # Optional
├── armor/head/{item_id}/
│   └── ...
├── shields/{item_id}/
│   └── walk.png (only walk needed)
└── capes/{item_id}/
    └── ...
```

### Step 4.3: Update Flags

After creating assets, update `items.json`:

```json
{
  "item_id": "your_item_id",
  // ...
  "has_sprites": true,   // Set to true
  "has_icon": true,      // Set to true
  "multi_slash": true    // Add if using slash2/slash3 variants
}
```

---

## Phase 5: Backend Integration

### Step 5.1: Verify Theme Registration

If new theme, ensure `item_forge_service.py` can detect it:

```python
# In GAME_THEMES dict
"1245620": "elden_ring",  # app_id -> theme_name
```

### Step 5.2: Test Mapping

```bash
# Preview what item an achievement would produce
curl -X POST "http://localhost:8000/api/forge/preview" \
  -H "Content-Type: application/json" \
  -d '{"achievement_id": 123}'
```

### Step 5.3: Verify Effort Scoring

Check that the achievement's effort_score maps to expected rarity:
- 80-100 → legendary
- 60-79 → epic
- 40-59 → rare

---

## Phase 6: Godot Integration

### Step 6.1: Update ForgeItemDB.gd

Add the item to `FORGE_ITEMS` dictionary in `scripts/systems/ForgeItemDB.gd`:

```gdscript
# Key format: "{provider}_{appid}_{achievement_api_name}"
"psn_BLOODBORNE_PLATINUM": {
    "item_id": "saw_cleaver",
    "item_name": "Saw Cleaver",
    "item_type": ItemType.WEAPON,
    "weapon_class": WeaponClass.SWORD,
    "rarity": ItemRarity.LEGENDARY,
    "description": "A trick weapon of the Hunters.",
    "lore": "Tonight, Gehrman joins the hunt.",
    "achievement_name": "Bloodborne Platinum",
    "unlock_percent": 6.8,
    "sprites": {
        "icon": FORGED_ICONS_BASE + "weapons/saw_cleaver.png",
        "walk": FORGED_ITEMS_BASE + "weapons/saw_cleaver/walk.png",
        "slash": FORGED_ITEMS_BASE + "weapons/saw_cleaver/slash.png",
        "slash2": FORGED_ITEMS_BASE + "weapons/saw_cleaver/slash2.png",  # Multi-slash
        "hurt": FORGED_ITEMS_BASE + "weapons/saw_cleaver/hurt.png"
    },
    "effects": ["blood_particles"],   # Must exist in ForgeVisualEffects.gd
    "glow_color": "#8B0000",
    "stats": {"damage_bonus": 4},
    "cosmetic_only": false,
    "multi_slash": true                # Enable slash variant cycling
},
```

**Required fields:**
- `item_id` - Must match items.json
- `sprites.icon` - Path to 64x64 icon
- `sprites.slash` - Path to slash animation
- `effects` - Array of effect names from ForgeVisualEffects.gd
- `glow_color` - Hex color for theme glow

**Optional for multi-slash:**
- `sprites.slash2`, `sprites.slash3` - Additional slash variants
- `multi_slash: true` - Flag to enable cycling

### Step 6.2: Update Armory.gd FORGE_CATALOG (CRITICAL!)

**⚠️ THIS STEP IS OFTEN FORGOTTEN!** Add the item to `FORGE_CATALOG` array in `scripts/ui/Armory.gd`:

```gdscript
{"id": "halo_battle_rifle", "name": "BR55 Battle Rifle", "game": "Halo", "achievement": "Legendary Campaign",
 "rarity": "Epic", "category": "weapons", "icon": "res://assets/icons/forged/weapons/halo_battle_rifle.png",
 "lore": "The UNSC's precision workhorse. Three-round burst, zero margin for error."},
```

**Why both files?**
- `ForgeItemDB.gd` → Backend/game item data (stats, effects, sprites)
- `Armory.gd` `FORGE_CATALOG` → UI display in Mantle Armory (browsing, previewing)

### Step 6.3: Update ForgeVisualEffects (if new effect)

Add effect config to:
`scripts/systems/ForgeVisualEffects.gd`

### Step 6.4: Test In-Game

1. Link provider account with the achievement
2. Navigate to Armory
3. Verify item appears with correct:
   - Name and description
   - Effect/glow
   - Sprite (if applicable)

---

## Phase 7: Quality Assurance

### Checklist Before Merge

**Design & Assets:**
- [ ] Pitch test documented and passes
- [ ] Native equivalent effect exists (forged power must be earnable in Dreadland)
- [ ] Quota not exceeded for provider
- [ ] No duplicate mappings
- [ ] Icon created and validated (64x64, proper orientation)
- [ ] Sprites created (if weapon/armor)

**Backend (items.json):**
- [ ] Achievement mapping added to `achievement_mappings`
- [ ] Item definition added to `items` array
- [ ] `has_sprites` and `has_icon` flags updated
- [ ] Theme exists or created
- [ ] Version and changelog updated

**Godot (BOTH files required!):**
- [ ] `ForgeItemDB.gd` → `FORGE_ITEMS` dict updated
- [ ] `Armory.gd` → `FORGE_CATALOG` array updated ⚠️
- [ ] Effect exists in `ForgeVisualEffects.gd` or created

**Testing:**
- [ ] Backend preview returns correct item
- [ ] Item appears in Armory UI
- [ ] Godot displays item correctly with effects
- [ ] Market impact considered (won't flood similar item supply)

---

## Phase 8: Provenance & Economy Setup

### Step 8.1: Verify Scarcity Tracking

Ensure the item's scarcity can be tracked:

```
SCARCITY VERIFICATION:
━━━━━━━━━━━━━━━━━━━━━
- [ ] Achievement global % known (for supply estimation)
- [ ] Provider API returns achievement unlock dates
- [ ] is_original_claim tracking enabled for this achievement
```

### Step 8.2: Configure Provenance Fields

Each forged item should support:

```json
{
  "provenance": {
    "original_achievement_date": "2007-05-15",  // When achievement was earned
    "forged_date": "2024-12-08",                // When item was created
    "forged_by": "user_id_hash",                // Original forger (anonymizable)
    "trade_count": 0,                           // Increments on each trade
    "current_owner": "user_id"
  }
}
```

### Step 8.3: Set Trading Parameters

Determine trading rules for this item:

```
TRADING CONFIG:
━━━━━━━━━━━━━━
- Tradeable: YES (all forged items are tradeable)
- Trade cooldown: 24 hours after acquisition
- Trade tax: 5% gold sink
- Marketplace eligible: YES
```

### Step 8.4: Estimate Market Position

Document expected market behavior:

```
MARKET ESTIMATION:
━━━━━━━━━━━━━━━━━
Item: [item_name]
Achievement %: [X%]
Estimated supply in Dreadland: [low/medium/high]
Expected price tier: [budget/mid/premium/whale]
Similar items: [list competing items]
```

---

## Quick Reference: File Locations

| What | Where |
|------|-------|
| **Backend** | |
| Item catalog | `backend/data/items.json` |
| Achievement mappings | `backend/data/items.json` → `achievement_mappings` |
| Theme definitions | `backend/data/items.json` → `themes` |
| Effort scoring | `backend/app/services/effort_scoring.py` |
| Item generation | `backend/app/services/item_forge_service.py` |
| **Godot (BOTH required!)** | |
| Item database | `scripts/systems/ForgeItemDB.gd` → `FORGE_ITEMS` |
| **Armory UI catalog** | `scripts/ui/Armory.gd` → `FORGE_CATALOG` ⚠️ |
| Visual effects | `scripts/systems/ForgeVisualEffects.gd` |
| **Assets** | |
| Forged sprites | `assets/equipment/forged/` |
| Forged icons | `assets/icons/forged/` |
| Icon validator | `assets/icons/forged/icon_standards.py` |
| **Economy design** | `docs/FORGE_ECONOMY_DESIGN.md` |
| **Provenance system** | `docs/FORGE_PROVENANCE_SYSTEM.md` |

---

## Example: Adding "Embrace the Void" (Hollow Knight)

### 1. Pitch Test
```
Achievement: Embrace the Void
Game: Hollow Knight (367520)
Pitch: "I completed Embrace the Void"
Reaction: "You beat 42 bosses without dying?!"
Holy Shit Factor: 10/10
Recognition Factor: 9/10
PASS
```

### 2. Item Spec
```json
{
  "item_id": "void_heart",
  "item_name": "Void Heart",
  "item_type": "accessory",
  "weapon_type": null,
  "description": "A heart touched by the abyss.",
  "lore": "Only those who embraced the void can wield it.",
  "base_rarity": "legendary",
  "theme": "hollow_knight",
  "visuals": {
    "icon_url": "/static/items/icons/void_heart.png",
    "sprite_folder": null,
    "effect": "void_aura",
    "glow_color": "#1A0033"
  },
  "has_sprites": false,
  "has_icon": false
}
```

### 3. Add Mapping
```json
"367520:EMBRACE_THE_VOID": "void_heart"
```

### 4. Create Icon
- 64x64 PNG of heart shape
- Dark purple/black palette
- Pulsing void effect implied

### 5. Test
- Verify appears in Armory when HK achievement present
- Verify void_aura effect applies
- Verify "Ancient Mythic Void Heart" name if old achievement

---

## Appendix: Provider-Specific Notes

### Steam
- Most straightforward: app_id:API_NAME format
- Global % available for all achievements
- Effort scoring: `100 - global_percent`

### Battle.net (WoW)
- Use achievement ID from our database
- Format: `battlenet:{achievement_id}`
- Check `is_feat_of_strength` and `is_legacy` flags

### PlayStation
- Platinum trophies are the main target
- PS-exclusive games only (Bloodborne, etc.)
- Verify trophy_id format

### Xbox
- Focus on high gamerscore achievements (100+)
- Halo LASO achievements are prime targets
- Cross-platform games: prefer Steam version

### Discord/GitHub/Reddit
- Focus on UNOBTAINABLE legacy badges
- These are the "Scarab Lords" of social platforms
- Lower priority than gaming achievements

---

---

## Phase 9: Godot → Backend Handoff

**When to trigger:** After all Godot assets are complete and verified in-game.

### Step 9.1: Godot Completion Checklist

Before handing off to backend, verify:

```
GODOT COMPLETION CHECKLIST:
━━━━━━━━━━━━━━━━━━━━━━━━━━
Item ID: _______________

Assets:
- [ ] Icon 64x64 created at assets/icons/forged/{category}/{item_id}.png
- [ ] Icon 256x256 enhanced at assets/icons/enhanced/forged/{category}/{item_id}.png
- [ ] Sprites created (if applicable) at assets/equipment/forged/{category}/{item_id}/
- [ ] All sprites imported in Godot (check .import files exist)

Code:
- [ ] ForgeItemDB.gd entry added with correct sprites paths
- [ ] ForgeVisualEffects.gd effect registered (if new effect)
- [ ] Armory.gd FORGE_CATALOG entry added

In-Game Verification:
- [ ] Item displays correctly in Armory UI
- [ ] Item equips correctly on character
- [ ] Visual effect renders properly
- [ ] No console errors related to item

READY FOR BACKEND: [ ]
```

### Step 9.2: Create Backend Handoff Ticket

Document the following for backend implementation:

```
BACKEND HANDOFF TICKET:
━━━━━━━━━━━━━━━━━━━━━━━
Item: [item_name]
Item ID: [item_id]
Achievement: [provider]:[achievement_api_name]
Provider: [steam/battlenet/psn/xbox]
App ID: [app_id if applicable]

Godot Status: COMPLETE
Asset Locations:
- Icon: assets/icons/forged/{category}/{item_id}.png
- Sprites: assets/equipment/forged/{category}/{item_id}/

Required Backend Work:
1. [ ] Add to items.json (items array)
2. [ ] Add achievement mapping
3. [ ] Add theme (if new)
4. [ ] Test forge preview API
5. [ ] Enable minting
6. [ ] Verify bridging works
```

---

## Phase 10: Backend Blockchain Integration

### Step 10.1: Update items.json (if not done)

Ensure the item is in the items array with:

```json
{
  "item_id": "your_item_id",
  "item_name": "Display Name",
  "item_type": "shield",
  "has_sprites": true,
  "has_icon": true,
  // ... full spec
}
```

### Step 10.2: Add Achievement Mapping

In `backend/data/items.json` under `achievement_mappings`:

```json
"achievement_mappings": {
  "{app_id}:{API_NAME}": "{item_id}"
}
```

### Step 10.3: Verify Item Forge Service

Test that the item is recognized:

```bash
# Check item lookup
curl "http://localhost:8000/api/catalog/item/{item_id}"

# Preview forge result for achievement
curl -X POST "http://localhost:8000/api/forge/preview" \
  -H "Content-Type: application/json" \
  -d '{"provider": "steam", "achievement_id": "ACHIEVEMENT_API_NAME", "app_id": "12345"}'
```

### Step 10.4: Enable Minting

Minting is automatic if:
1. Item exists in items.json
2. Achievement mapping exists
3. User has verified the achievement through provider OAuth
4. `DEV_MODE=false` (or true for simulated mints)

Test minting flow:

```bash
# 1. User must have linked provider account with achievement
# 2. User requests forge
curl -X POST "http://localhost:8000/api/wallet/forge" \
  -H "Authorization: Bearer {session_token}" \
  -H "Content-Type: application/json" \
  -d '{"achievement_credit_id": 123}'

# Response includes:
# - forged_item record (database)
# - token_id (if minted to chain)
# - transaction_hash (if real mint)
```

### Step 10.5: Verify Bridge Support

Items are bridgeable if minted. Test bridge-out:

```bash
# Check item is bridgeable
curl "http://localhost:8000/api/wallet/items/{forged_item_id}"

# Bridge out to external wallet
curl -X POST "http://localhost:8000/api/wallet/bridge-out" \
  -H "Authorization: Bearer {session_token}" \
  -d '{"forged_item_id": 123, "to_address": "0x..."}'
```

### Step 10.6: Verify Trading Support

All forged items are tradeable. Test trading:

```bash
# Create trade offer
curl -X POST "http://localhost:8000/api/trading/offer" \
  -H "Authorization: Bearer {session_token}" \
  -d '{"forged_item_id": 123, "price_gold": 1000}'

# Accept trade
curl -X POST "http://localhost:8000/api/trading/accept/{offer_id}" \
  -H "Authorization: Bearer {buyer_token}"
```

---

## Phase 11: Full QA Testing Checklist

### 11.1: Asset Verification

```
ASSET QA:
━━━━━━━━
- [ ] Icon displays at 64x64 without artifacts
- [ ] Icon displays at 256x256 without artifacts
- [ ] Sprites load in Godot without import errors
- [ ] Walk animation plays smoothly (all 4 directions)
- [ ] Slash animation plays smoothly (if weapon)
- [ ] Thrust animation plays smoothly (if applicable)
- [ ] Hurt animation plays smoothly (if applicable)
- [ ] No clipping with character body
- [ ] Effect renders at expected intensity
```

### 11.2: Godot UI Verification

```
GODOT UI QA:
━━━━━━━━━━━
- [ ] Item appears in Armory catalog
- [ ] Item shows correct name, description, lore
- [ ] Item shows correct rarity color
- [ ] Item shows correct achievement source
- [ ] Item equips to correct slot
- [ ] Item unequips correctly
- [ ] Item saves/loads with character state
- [ ] Tooltip shows correct stats
```

### 11.3: Backend API Verification

```
BACKEND API QA:
━━━━━━━━━━━━━━
- [ ] GET /api/catalog/item/{item_id} returns item
- [ ] POST /api/forge/preview returns correct item for achievement
- [ ] Item appears in user's forgeable items (if they have achievement)
- [ ] Rarity tier matches expected (based on effort score)
```

### 11.4: Minting Verification

```
MINTING QA:
━━━━━━━━━━
Test Account Requirements:
- User with linked provider account
- User has the required achievement
- User has connected wallet (or DEV_MODE=true)

Tests:
- [ ] Forge request creates database record (ForgedItem)
- [ ] DEV_MODE: Simulated mint succeeds, fake token_id assigned
- [ ] PROD_MODE: Real mint succeeds, real token_id assigned
- [ ] Transaction hash logged (if real mint)
- [ ] Item appears in user's inventory after forge
- [ ] Duplicate forge attempt blocked (one per achievement per user)
- [ ] Provenance recorded (forged_by, forged_date, achievement_date)
```

### 11.5: Trading Verification

```
TRADING QA:
━━━━━━━━━━
Test Account Requirements:
- Two user accounts
- One user owns the forged item
- Both users have sufficient gold

Tests:
- [ ] Seller can create trade offer
- [ ] Offer appears in marketplace
- [ ] Buyer can view offer details
- [ ] Buyer can accept offer
- [ ] Item transfers to buyer's inventory
- [ ] Gold transfers from buyer to seller (minus 5% tax)
- [ ] Trade cooldown enforced (24 hours)
- [ ] Provenance updated (trade_count++, current_owner)
- [ ] Trade history recorded
```

### 11.6: Bridge Verification

```
BRIDGE QA (if blockchain enabled):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Test Account Requirements:
- User owns forged item
- User has connected external wallet
- Contract deployed and configured

Bridge-Out Tests:
- [ ] Item can be selected for bridge-out
- [ ] Confirmation shows correct destination wallet
- [ ] Bridge transaction submits to chain
- [ ] Item status changes to "bridged_out"
- [ ] Item removed from in-game inventory
- [ ] NFT appears in external wallet (OpenSea, etc.)

Bridge-In Tests:
- [ ] User can initiate bridge-in from external wallet
- [ ] System detects incoming transfer
- [ ] Item status changes to "bridged_in"
- [ ] Item appears in user's in-game inventory
- [ ] Provenance maintained through bridge cycle
```

### 11.7: Edge Cases

```
EDGE CASE QA:
━━━━━━━━━━━━
- [ ] User without achievement cannot forge item
- [ ] User cannot forge same achievement twice
- [ ] Item displays gracefully if sprites missing (fallback)
- [ ] API handles invalid item_id gracefully
- [ ] Trade fails gracefully if buyer has insufficient gold
- [ ] Bridge fails gracefully if contract unavailable
- [ ] Concurrent trade attempts handled (no double-spend)
```

---

## Quick Reference: Complete Item Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│                    ITEM CREATION FLOW                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Phase 1-2: Design & Selection                              │
│  └─> Achievement chosen, item spec created                  │
│                                                             │
│  Phase 3: items.json (Backend)                              │
│  └─> Item definition + achievement mapping                  │
│                                                             │
│  Phase 4: Assets (Godot)                                    │
│  └─> Icons + Sprites created                                │
│                                                             │
│  Phase 5-6: Godot Integration                               │
│  └─> ForgeItemDB.gd + Armory.gd + Effects                   │
│                                                             │
│  ════════════════════════════════════════════════════════   │
│  ▶▶▶ HANDOFF CHECKPOINT: Godot Complete ◀◀◀                │
│  ════════════════════════════════════════════════════════   │
│                                                             │
│  Phase 7: Backend Verification                              │
│  └─> API tests, forge preview works                         │
│                                                             │
│  Phase 8: Provenance & Economy                              │
│  └─> Trading params, market estimation                      │
│                                                             │
│  Phase 9-10: Blockchain Integration                         │
│  └─> Minting enabled, bridge verified                       │
│                                                             │
│  Phase 11: Full QA                                          │
│  └─> All test checklists pass                               │
│                                                             │
│  ════════════════════════════════════════════════════════   │
│  ▶▶▶ ITEM LIVE ◀◀◀                                         │
│  ════════════════════════════════════════════════════════   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Version History

- v1.0 (2024-12) - Initial process document
- v1.1 (2024-12) - Added Phase 8: Provenance & Economy Setup, updated QA checklist for trading system
- v1.2 (2024-12) - Added multi-slash weapon support, 128px oversize sprite specs, icon extraction from sprites, enhanced effect config documentation
- v1.3 (2024-12) - Added Phase 9: Godot→Backend Handoff, Phase 10: Blockchain Integration, Phase 11: Full QA Testing Checklist with mint/trade/bridge verification
