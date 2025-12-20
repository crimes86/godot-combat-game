# Godot Engineer Handoff

> **For API details, see `API_CONTRACT.md`. This document covers vision, game design, and cosmetic systems.**

---

## What This Is

Ashbane is NOT competing with TrueAchievements. The web dashboard is the **authentication layer** for the Godot game.

**The flow:**
1. Player launches Godot game
2. Logs in via browser → links Steam/Xbox/Battle.net
3. Backend aggregates their real gaming achievements
4. Their gaming history transforms into in-game cosmetics
5. A 10-year veteran LOOKS like a battle-hardened legend
6. A fresh account looks like a peasant

**Why it matters:** You can't fake a decade of Steam achievements. The flex is real and verifiable.

---

## Core Principle: Cosmetic Only

**Non-negotiable.** Ashbane tier affects ONLY visuals:

| Affected | NOT Affected |
|----------|--------------|
| Character appearance | Damage output |
| Armor/weapon skins | Health/stats |
| Auras and effects | Movement speed |
| Titles and badges | Abilities |
| Emotes | Drop rates |

A fresh Initiate can beat a Mythic in PvP if they're better. The Mythic just looks cooler.

---

## The Tier System

| Tier | Min Score | Color | Visual Direction |
|------|-----------|-------|------------------|
| Initiate | 0 | #666666 | Worn, basic gear |
| Bronze | 100 | #CD7F32 | Bronze trim |
| Silver | 500 | #C0C0C0 | Silver highlights |
| Gold | 1000 | #FFD700 | Gold accents, subtle glow |
| Platinum | 2000 | #E5E4E2 | Platinum + soft blue glow |
| Diamond | 3000 | #B9F2FF | Crystal effects, sparkles |
| Legendary | 5000 | #FF6600 | Fire/ember effects |
| Mythic | 7500 | #FF00FF | Ethereal aura, particles |

**Note:** Pure achievement count only. Multi-platform rewards handled via separate Ashbane-specific achievements.

---

## Achievement → Cosmetic Mapping

### Category 1: Tier-Based (Automatic)

Every player gets cosmetics matching their tier:

```gdscript
var TIER_COSMETICS = {
    "initiate": {
        "armor_set": "cloth_basic",
        "effects": [],
        "title_prefix": ""
    },
    "bronze": {
        "armor_set": "leather_bronze_trim",
        "effects": ["bronze_accent"],
    },
    "gold": {
        "armor_set": "plate_gold",
        "effects": ["gold_trim", "subtle_glow"],
        "title_prefix": "Honored "
    },
    "mythic": {
        "armor_set": "ethereal_mythic",
        "effects": ["mythic_aura", "particle_trail", "ground_runes"],
        "title_prefix": "Mythic "
    }
}
```

### Category 2: Provider-Specific

Linking platforms unlocks themed accents:

```gdscript
var PROVIDER_COSMETICS = {
    "steam": {
        "badge": "steam_verified_badge",
        "accent_color": Color(0.1, 0.1, 0.1)
    },
    "battlenet": {
        "badge": "blizzard_verified_badge",
        "shoulder_effect": "ice_crystals"
    },
    "xbox": {
        "badge": "xbox_verified_badge",
        "aura_tint": Color(0.0, 0.8, 0.0, 0.3)
    },
    "playstation": {
        "badge": "psn_verified_badge",
        "aura_tint": Color(0.0, 0.3, 0.8, 0.3)
    }
}
```

### Category 3: Specific Achievements

Individual achievements (especially forged) unlock items:

```gdscript
var ACHIEVEMENT_COSMETICS = {
    # Dark Souls 3 - 100%
    "steam_374320_THE_DARK_SOUL": {
        "cape": "ashen_one_cape",
        "weapon_skin": "coiled_sword",
        "walk_effect": "ember_footsteps"
    },
    # Elden Ring
    "steam_1245620_ELDEN_LORD": {
        "crown": "elden_crown",
        "aura": "erdtree_blessing"
    },
    # WoW Thunderfury
    "battlenet_wow_thunderfury": {
        "weapon_skin": "thunderfury_blessed_blade",
        "attack_effect": "chain_lightning"
    }
}
```

### Category 4: Milestones

```gdscript
var MILESTONE_COSMETICS = {
    100: {"title": "Achiever"},
    500: {"title": "Dedicated", "cape_trim": "silver_thread"},
    1000: {"title": "Veteran", "portrait_frame": "veteran_frame"},
    5000: {"title": "Mythic Hunter", "ground_effect": "mythic_footsteps"},
    10000: {"title": "The Completionist", "full_transformation": true}
}
```

---

## The Transformation Moment

**Critical for virality.** When a player logs in with linked accounts:

1. Character stands in basic gear
2. API response arrives with profile
3. Camera zooms slightly
4. Particles swirl around character
5. Armor materializes layer by layer (boots → legs → chest → arms → head)
6. Tier aura fades in
7. Achievement-specific items appear
8. Flash - transformation complete
9. **Other players nearby SEE this happen**

**The viral loop:**
```
Player transforms → Shares clip → Friend asks "how?"
→ Links accounts → Transforms → Shares → Repeat
```

---

## LPC Sprite Layer Mapping

Map Ashbane cosmetics to the 9-layer system:

| Layer | LPC Purpose | Ashbane Effect |
|-------|-------------|---------------|
| 0 | Shadow | Tier-based shadow intensity |
| 1 | Body | Tier body glow/tint |
| 2 | Head | Achievement head cosmetics |
| 3 | Hair | Player choice (no effect) |
| 4 | Pants | Tier leg armor |
| 5 | Shirt | Tier chest armor |
| 6 | Arms | Tier arm armor |
| 7 | Boots | Tier boots |
| 8 | Hands | Tier gloves |
| 9 | Weapon | Achievement weapon skins |
| 10+ | Effects | Auras, particles (additive) |

---

## Required Autoloads

### AshbaneAuth

Handles authentication. Key responsibilities:
- Device auth flow (see `API_CONTRACT.md` for endpoints)
- Token persistence to `user://Ashbane_session.dat`
- Profile fetching and caching
- Badge lookups for other players in multiplayer

Signals:
- `auth_completed(user_data: Dictionary)`
- `auth_failed(error: String)`
- `profile_updated(profile: Dictionary)`

### AshbaneCosmetics

Handles visual translation. Key responsibilities:
- Calculate cosmetics from profile data
- Apply cosmetics to LPC sprite layers
- Manage transformation sequence
- Cache cosmetic resources

---

## Multiplayer Considerations

### Badge Display
Every player shows their tier badge. Fetch via `/api/player/{id}/badge`.

### Earned vs Traded
Forged items show provenance:
- **EARNED** (gold badge) → Player unlocked the achievement
- **TRADED** (silver badge) → Player bought the NFT

### Verification
Use `/api/wallet/check-ownership` to verify players aren't spoofing forged cosmetics.

---

## Armory UX Principles

The Armory is a staging scene between auth and game world. Key principles:

### Player Types

| Type | Experience Goal |
|------|-----------------|
| **Guest** | Zero friction. "Enter World" is primary, linking is optional |
| **New Player** | "Your armory awaits" - show potential, not shame |
| **Casual** | "Look what you've earned" - appreciation |
| **Veteran** | "Behold your legacy" - reverence |
| **Returning** | "New rewards await!" - excitement |

### Guest Experience (Critical)

Guests must be able to play immediately:
- Big "Enter World" button, no login required
- "Link accounts" is secondary/subtle
- No shame messaging about missing content
- They see cool players in-game → curiosity drives account creation later

### Claim Sequence

When players have new unlocks:
1. Build anticipation (glow, particles, sound)
2. Reveal items one by one with fanfare
3. Show tier upgrade if applicable
4. Summary with screenshot option

### The Golden Rule

**Every player type should feel good leaving the Armory.**
- Guest: "That was easy, let's see what this game is about"
- Veteran: "I look AMAZING. Time to show off"

---

## Build Priority

### Phase 1: Launch Required
1. [ ] AshbaneAuth with device auth flow
2. [ ] Token persistence
3. [ ] Tier → armor set mapping
4. [ ] Badge display in multiplayer

### Phase 2: Virality Required
5. [ ] Transformation sequence
6. [ ] Provider badges
7. [ ] Higher tier particle effects

### Phase 3: Depth
8. [ ] Specific achievement cosmetics
9. [ ] Forged item integration
10. [ ] Earned/traded distinction

---

## Key Concepts

### is_original_claim
- `true` = First to claim (counts toward score, can forge)
- `false` = Previously claimed by someone else (display only)

### Forging
Only Rare+ achievements with `is_original_claim=true` can become NFTs on Base network.

### Provenance
Forged items track original earner vs current owner. Earned = prestige. Traded = still valid ownership.

---

## Reference Documents

| Document | Contents |
|----------|----------|
| `API_CONTRACT.md` | All endpoints, request/response formats, auth flow |
| `ACHIEVEMENT_VERIFICATION.md` | Anti-exploit system details |
| `godot_examples/ForgedItemManager.gd` | Example forged item code |

---

## The Mission

Make players' real gaming history visible through cosmetics. The transformation moment should make them share clips.

The auth layer is done. Now we need the visual identity system.
