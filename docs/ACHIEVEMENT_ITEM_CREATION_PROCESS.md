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

If the item needs a new effect, add to `ForgeVisualEffects.gd`:

```gdscript
"new_effect_name": {
    "type": "particles|glow|trail|aura",
    "color": Color(R, G, B, A),
    "intensity": 1.0-1.5,
    "particle_count": 8-20,
    // ... other properties
},
```

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
- Armor/Shields: Upright, centered
- Padding: 4px minimum from edge

**Tools:**
- Reference: Source game's item art
- Create: Aseprite, Photoshop, GIMP
- Validate: `python assets/icons/forged/icon_standards.py --validate`

**Export to:**
```
assets/icons/forged/{category}/{item_id}.png

Categories:
- weapons/
- armor/
- shields/
- accessories/
```

### Step 4.2: Create Sprites (If Applicable)

Accessories don't need sprites. Weapons/Armor do.

**LPC Sprite Requirements:**

| Animation | Dimensions | Required |
|-----------|------------|----------|
| walk.png | 576x256 (9 frames x 4 dirs) | YES |
| slash.png | 384x256 (6 frames x 4 dirs) | YES (weapons) |
| thrust.png | 512x256 (8 frames x 4 dirs) | Optional |
| hurt.png | 384x64 (6 frames x 1 dir) | Optional |

**Tools:**
- [Universal LPC Generator](https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/)
- Manual pixel art in Aseprite

**Export to:**
```
assets/equipment/forged/
├── weapons/{item_id}/
│   ├── walk.png
│   ├── slash.png
│   └── (optional: thrust.png, hurt.png)
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
  "has_sprites": true,  // Set to true
  "has_icon": true      // Set to true
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

### Step 6.1: Update ForgeItemDB (if needed)

If new weapon type or animation fallback needed, update:
`scripts/systems/ForgeItemDB.gd`

### Step 6.2: Update ForgeVisualEffects (if new effect)

Add effect config to:
`scripts/systems/ForgeVisualEffects.gd`

### Step 6.3: Test In-Game

1. Link provider account with the achievement
2. Navigate to Armory
3. Verify item appears with correct:
   - Name and description
   - Effect/glow
   - Sprite (if applicable)

---

## Phase 7: Quality Assurance

### Checklist Before Merge

- [ ] Pitch test documented and passes
- [ ] Native equivalent effect exists (forged power must be earnable in Dreadland)
- [ ] Quota not exceeded for provider
- [ ] No duplicate mappings
- [ ] Icon created and validated (64x64, proper orientation)
- [ ] Sprites created (if weapon/armor)
- [ ] `has_sprites` and `has_icon` flags updated
- [ ] Theme exists or created
- [ ] Effect exists or created
- [ ] Backend preview returns correct item
- [ ] Godot displays item correctly
- [ ] Version and changelog updated
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
| Item catalog | `backend/data/items.json` |
| Achievement mappings | `backend/data/items.json` → `achievement_mappings` |
| Theme definitions | `backend/data/items.json` → `themes` |
| Effort scoring | `backend/app/services/effort_scoring.py` |
| Item generation | `backend/app/services/item_forge_service.py` |
| Visual effects | `scripts/systems/ForgeVisualEffects.gd` |
| Item database | `scripts/systems/ForgeItemDB.gd` |
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

## Version History

- v1.0 (2024-12) - Initial process document
- v1.1 (2024-12) - Added Phase 8: Provenance & Economy Setup, updated QA checklist for trading system
