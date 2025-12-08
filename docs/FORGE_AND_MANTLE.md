# Forge & Mantle Integration

> Achievements become weapons and armor. The Forge is where digital trophies materialize into in-game power.

This document consolidates the Forge system specification, Armory scene design, and asset generation guides.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [API Contract](#api-contract)
3. [Armory Scene](#armory-scene)
4. [Forge UI](#forge-ui)
5. [Claim Sequence](#claim-sequence)
6. [Asset Checklist](#asset-checklist)
7. [Asset Generation Guide](#asset-generation-guide)
8. [Icon Standards](#icon-standards)
9. [Implementation Checklist](#implementation-checklist)

---

## System Overview

The Forge system bridges the web-based NFT minting experience with in-game item acquisition. Players forge achievements on the web, then collect the resulting items in-game at the Forge.

### Core Loop

```
WEB: Browse achievements -> Select -> Mint NFT
                |
API: pending_forges[] updated, broadcast if Legendary+
                |
GAME: Armory/World shows "Items waiting at Forge"
                |
PLAYER: Opens Forge UI -> Claims items -> Equips
                |
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

## Armory Scene

The Armory is a **staging area** where players:
1. See their gaming identity visualized
2. Claim new cosmetic unlocks
3. Preview their character
4. Choose to enter the game world

**Critical principle:** This scene must feel welcoming to ALL players, especially those with no gaming history. It's an invitation, not a gate.

### Player Types

| Type | Description | Experience Goal |
|------|-------------|-----------------|
| **Guest** | No Mantle account, just wants to try the game | "Jump right in, see what it's about" |
| **New Player** | Has Mantle account, no providers linked | "Your journey starts here" |
| **Casual** | 1 provider, some achievements | "Look what you've earned" |
| **Veteran** | Multiple providers, high tier | "Behold your legacy" |
| **Returning** | Has pending unlocks | "New rewards await!" |

### Scene Layout

```
+-----------------------------------------------------------------------------+
|                              MANTLE ARMORY                                   |
|                                                                              |
|  +--------------+                    +-------------------------------+      |
|  |              |                    |                               |      |
|  |   LEFT       |                    |         CENTER                |      |
|  |   PANEL      |                    |                               |      |
|  |              |                    |      Character Display        |      |
|  |  - Mantle    |                    |      (animated, rotatable)    |      |
|  |    Card      |                    |                               |      |
|  |              |                    |                               |      |
|  |  - Provider  |                    |                               |      |
|  |    Badges    |                    |                               |      |
|  |              |                    |                               |      |
|  |  - Pending   |                    |                               |      |
|  |    Unlocks   |                    |                               |      |
|  |              |                    +-------------------------------+      |
|  +--------------+                                                           |
|                                                                              |
|  +----------------------------------------------------------------------+   |
|  |                         ACTION BAR                                    |   |
|  |   [Claim Rewards]    [Manage Loadout]    [ENTER WORLD]               |   |
|  +----------------------------------------------------------------------+   |
|                                                                              |
+-----------------------------------------------------------------------------+
```

### Experience By Player Type

#### Guest (No Account)

**Goal:** Zero friction. Let them play immediately.

```
Scene State:
- Minimal UI, clean and inviting
- Character: Randomized basic appearance
- Background: Warm, welcoming lighting

UI Shows:
+--------------------------------------------+
|                                            |
|   Welcome, Traveler                        |
|                                            |
|   "Every legend starts somewhere."         |
|                                            |
|   +------------------------------------+   |
|   |         [ENTER WORLD]              |   | <- BIG, primary button
|   |         Start your adventure       |   |
|   +------------------------------------+   |
|                                            |
|   +------------------------------------+   |
|   |    [Create Account / Sign In]      |   | <- Secondary, subtle
|   |    Link your gaming history        |   |
|   +------------------------------------+   |
|                                            |
|   "Players who link accounts unlock       |
|    cosmetics from their gaming history"   |
|                                            |
+--------------------------------------------+

No shame. No "you're missing out." Just an invitation.
```

**Flow:**
1. Guest clicks "Enter World"
2. Spawns with basic randomized appearance
3. Plays the game
4. Sees other players with cool cosmetics
5. Curiosity drives them to create account later

#### New Player (Account, No Providers)

**Goal:** Excitement about potential, not shame about emptiness.

```
Scene State:
- Armory is "new" - clean, torches lit, empty but ready
- Character: Basic gear, but standing proudly
- Mantle Card: Shows "Initiate" tier

UI Shows:
+--------------------------------------------+
|                                            |
|   Welcome, [Username]                      |
|   ===========================              |
|                                            |
|   +-----------------+                      |
|   |   INITIATE      |  Your Mantle tier    |
|   |   ------------  |                      |
|   |   0 achievements|  Link a gaming       |
|   |   0 providers   |  platform to begin   |
|   +-----------------+                      |
|                                            |
|   Your armory awaits your history.         |
|                                            |
|   +-------------------------------------+  |
|   |  [Link Steam]  [Link Battle.net]    |  | <- Optional, not blocking
|   |  [Link Xbox]   [Link PlayStation]   |  |
|   +-------------------------------------+  |
|                                            |
|   +-------------------------------------+  |
|   |           [ENTER WORLD]             |  | <- Still primary
|   |      Play now, link later           |  |
|   +-------------------------------------+  |
|                                            |
+--------------------------------------------+

Message: "You can always link accounts later from the menu."
```

**Key:** The "Enter World" button is ALWAYS available and prominent. Linking is optional.

#### Casual Player (1 Provider, Some Achievements)

**Goal:** Show them what they've earned, make them feel good.

```
Scene State:
- Armory has some items on racks
- Character wearing tier-appropriate armor
- Warm, appreciative tone

UI Shows:
+--------------------------------------------+
|                                            |
|   Welcome back, [Username]                 |
|   =========================================|
|                                            |
|   +-----------------+   +---------------+  |
|   |   SILVER        |   | STEAM check   |  |
|   |   ------------  |   | 523 cheevos   |  |
|   |   523 total     |   | Last sync: 2d |  |
|   |   Score: 523    |   +---------------+  |
|   +-----------------+                      |
|                                            |
|   Your achievements unlocked:              |
|   - Silver Tier Armor Set                  |
|   - Steam Verified Badge                   |
|   - 2 Weapon Skins                         |
|                                            |
|   +-------------------------------------+  |
|   |           [ENTER WORLD]             |  |
|   +-------------------------------------+  |
|                                            |
|   [Sync Achievements]  [Link Another]      |
|                                            |
+--------------------------------------------+
```

#### Veteran (High Tier, Multiple Providers)

**Goal:** Make them feel like a legend. This is their reward.

```
Scene State:
- Armory is FULL - weapons, armor, trophies everywhere
- Dramatic lighting, particle effects
- Character has aura, glowing elements

UI Shows:
+--------------------------------------------+
|                                            |
|   =========================================|
|   ||         MYTHIC CHAMPION              ||
|   ||           [Username]                 ||
|   =========================================|
|                                            |
|   +-----------------+   +---------------+  |
|   |   MYTHIC *      |   | STEAM check   |  |
|   |   ------------  |   | BATTLE.NET    |  |
|   |   7,847 total   |   | XBOX check    |  |
|   |   Score: 9,023  |   | PSN check     |  |
|   +-----------------+   +---------------+  |
|                                            |
|   Your legend speaks:                      |
|   - 12 Legendary Achievements              |
|   - 5 Forged Items (On-Chain)              |
|   - Full Mythic Armor Set                  |
|                                            |
|   +-------------------------------------+  |
|   |          [ENTER WORLD]              |  |
|   |       "Let them see you."           |  |
|   +-------------------------------------+  |
|                                            |
+--------------------------------------------+
```

#### Returning Player (Pending Unlocks)

**Goal:** Excitement, anticipation, reward.

```
Scene State:
- Glowing chest/forge in center
- Pulsing light effect
- Sound: Gentle chime loop

UI Shows:
+--------------------------------------------+
|                                            |
|   Welcome back, [Username]                 |
|                                            |
|   +====================================+   |
|   |   ** 3 NEW REWARDS AWAIT **        |   | <- Animated, attention-grabbing
|   +====================================+   |
|                                            |
|   Since your last visit:                   |
|   - Synced 47 new achievements             |
|   - Reached GOLD tier!                     |
|   - 1 item ready to forge                  |
|                                            |
|   +-------------------------------------+  |
|   |        [CLAIM REWARDS]              |  | <- Primary, pulsing
|   +-------------------------------------+  |
|                                            |
|   [Skip for now]           [Enter World]   | <- Always available
|                                            |
+--------------------------------------------+
```

### Scene Structure

```
ArmoryScene (Node2D or Control)
+-- Background
|   +-- ArmoryEnvironment (animated background)
|   +-- AmbientParticles
+-- CharacterDisplay
|   +-- CharacterSprite (LPC layers)
|   +-- AuraEffect
|   +-- GroundEffect
+-- LeftPanel
|   +-- MantleCard
|   +-- ProviderBadges
|   +-- PendingUnlocksCounter
+-- ActionBar
|   +-- ClaimButton
|   +-- LoadoutButton
|   +-- EnterWorldButton
+-- ClaimSequence (hidden until needed)
|   +-- Forge
|   +-- ItemRevealContainer
|   +-- SummaryPanel
+-- LoadoutPreview (hidden until needed)
|   +-- CharacterPreview
|   +-- EquipmentList
|   +-- LockedItemsList
+-- ForgeArea (hidden until needed)
    +-- ForgeableList
    +-- WalletInfo
    +-- ForgeButton
```

### Sound Design

| Moment | Sound | Notes |
|--------|-------|-------|
| Enter Armory | Ambient hum, crackling fire | Warm, inviting |
| Pending unlocks | Gentle repeating chime | Anticipation |
| Claim start | Low rumble, building | Excitement builds |
| Item reveal (Common) | Soft chime | Subtle |
| Item reveal (Rare) | Brighter chime | Noticeable |
| Item reveal (Epic) | Harmonic chord | Impressive |
| Item reveal (Legendary) | Full fanfare + reverb | EPIC moment |
| Tier upgrade | Orchestral hit | Celebration |
| Item equip | Satisfying click/snap | Tactile feedback |
| Forge strike | Metallic clang | Impactful |
| Enter World | Whoosh + adventure sting | Forward momentum |

### Visual Polish - Lighting by Player Type

| Type | Lighting | Atmosphere |
|------|----------|------------|
| Guest | Warm, soft, inviting | "Come on in" |
| New Player | Clean, bright, potential | "Fresh start" |
| Casual | Comfortable, homey | "Your space" |
| Veteran | Dramatic, epic, reverent | "Behold" |
| Pending | Glowing, pulsing | "Something awaits" |

---

## Forge UI

### Armory Integration

**Location:** Armory.gd - Middle or Right column

**Elements:**
- Forge button with pending count badge
- Glowing/pulsing animation when items pending
- Opens ForgeUI as overlay

```
+-------------------------------+
|  FORGE THE FORGE              |
|                               |
|  FIRE 2 items ready to claim  |
|                               |
|  [ OPEN FORGE ]  <- Glows     |
|                               |
|  [ Browse Forgeable -> ]      |
|    Opens web in browser       |
+-------------------------------+
```

### ForgeUI (Shared Component)

**File:** `scripts/ui/ForgeUI.gd`
**Scene:** `scenes/ui/ForgeUI.tscn`

**Can be opened from:**
- Armory (overlay)
- In-world Forge object (popup)

```
+------------------------------------------------------+
|                  FORGE THE FORGE                     |
|------------------------------------------------------|
|                                                      |
|  PENDING ITEMS                                       |
|  +--------+  +--------+  +--------+                  |
|  |   ??   |  |   ??   |  |        |  <- Silhouettes  |
|  |  ??    |  |  ??    |  |        |    until claimed |
|  |        |  |        |  |        |                  |
|  | Epic   |  | Legend |  |        |                  |
|  +--------+  +--------+  +--------+                  |
|                                                      |
|           [ CLAIM NEXT ]  [ CLAIM ALL ]              |
|                                                      |
|------------------------------------------------------|
|  GLOBAL FORGE FEED                     [Legendary+]  |
|                                                      |
|  SWORD 2m ago  DarkLord99 forged Coiled Sword       |
|  SHIELD 15m ago AshKetchum forged Grass Crest Shield|
|  SWORD 1h ago  VetPlayer forged Moonlight Greatsword|
|                                                      |
|------------------------------------------------------|
|  [ BROWSE FORGEABLE ACHIEVEMENTS -> ]                |
|------------------------------------------------------|
|                               [ CLOSE ]              |
+------------------------------------------------------+
```

### In-World Forge Object

**Location:**
- Town/safe zone near spawn
- Visible, central location
- Near other services (vendor, blacksmith)

**Visual Design:**
```
     +===============+
     |   FIRE FIRE   |  <- Animated flames (GPUParticles2D)
     |  +---------+  |
     |  |  ANVIL  |  |  <- Anvil sprite
     |  +---------+  |
     +=================+

When items pending:
- Flames burn brighter/higher
- Subtle pulsing glow on ground
- Floating indicator: "FIRE 2"
```

---

## Claim Sequence

When player clicks "Claim Rewards":

### Phase 1: Build Anticipation (2-3 seconds)

```
- Screen dims slightly
- Chest/forge glows brighter
- Particles intensify
- Sound: Building rumble
- Camera slowly pushes in on character
```

### Phase 2: Reveal Items (3-5 seconds each)

```
For each item:

1. RISE
   - Item emerges from forge with light beam
   - Slow motion float upward
   - Sound: Ethereal whoosh

2. DISPLAY
   - Item card fades in beside it:
   +----------------------------------+
   |  * COILED SWORD                  |
   |  --------------------------------|
   |  Weapon Skin - Legendary         |
   |                                  |
   |  "The Dark Soul"                 |
   |  Dark Souls III - 100%           |
   |                                  |
   |  [EARNED] - You completed this   |
   +----------------------------------+
   - Sound: Achievement chime (pitch varies by rarity)
   - Particles burst outward

3. EQUIP
   - Item flies toward character
   - Attaches to appropriate slot
   - Character briefly glows
   - Sound: Satisfying "click"

4. PAUSE
   - 1 second pause
   - Next item begins
```

### Phase 3: Tier Upgrade (If Applicable)

```
If player crossed a tier threshold:

1. Current armor dissolves into particles
2. New tier armor materializes piece by piece
3. Tier name appears in large text:

        +=======================+
        |    TIER ACHIEVED      |
        |        GOLD           |
        +=======================+

4. Aura effect fades in (if applicable)
5. Sound: Triumphant fanfare
```

### Phase 4: Summary

```
+----------------------------------------------------+
|                                                    |
|              REWARDS CLAIMED                       |
|              ===============                       |
|                                                    |
|   +1 Weapon Skin    Coiled Sword (Legendary)      |
|   +1 Cape           Ashen One                      |
|   +1 Walk Effect    Ember Steps                    |
|                                                    |
|   +----------------------------------------------+ |
|   |  INITIATE -> GOLD                            | |
|   |  New armor set unlocked!                     | |
|   +----------------------------------------------+ |
|                                                    |
|   +-------------+    +--------------------------+  |
|   |  [PREVIEW]  |    |     [ENTER WORLD]        |  |
|   |  See loadout|    |   Show them who you are  |  |
|   +-------------+    +--------------------------+  |
|                                                    |
|   [CAMERA Screenshot]                              |
|                                                    |
+----------------------------------------------------+
```

---

## Asset Checklist

### Directory Structure

```
assets/
+-- equipment/forged/           # Forged item sprites
|   +-- weapons/
|   |   +-- {item_name}/
|   |       +-- walk.png
|   |       +-- slash.png
|   |       +-- thrust.png
|   |       +-- hurt.png
|   +-- armor/
|   |   +-- head/{item_name}/
|   |   +-- chest/{item_name}/
|   |   +-- legs/{item_name}/
|   |   +-- hands/{item_name}/
|   |   +-- feet/{item_name}/
|   +-- capes/{item_name}/
|   +-- shields/{item_name}/
|   +-- tools/{item_name}/
|
+-- icons/forged/               # Inventory icons (64x64)
    +-- weapons/
    +-- armor/
    +-- accessories/
    +-- capes/
    +-- shields/
    +-- tools/
```

### Priority 1: Elden Ring (Most Popular)

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Margit's Shackle | Accessory | Common | Icon only | [ ] |
| Grafted Blade Greatsword | Weapon (Greatsword) | Common | Greatsword + golden tint | [ ] |
| Carian Royal Crown | Head Armor | Uncommon | Crown/tiara + blue glow | [ ] |
| Starscourge Greatswords | Weapon (Greatsword) | Uncommon | Paired swords + purple | [ ] |
| Hand of Malenia | Weapon (Katana) | Rare | Katana + red/pink petals | [ ] |
| Elden Armory Pauldrons | Chest Armor | Epic | Plate shoulder + gold | [ ] |
| Elden Lord's Crown | Head Armor | Legendary | Ornate crown + golden rays | [ ] |

**Elden Ring Visual Effects:**
- `golden_glow` - Subtle gold particle aura
- `moonlight_aura` - Blue/white ethereal glow
- `gravity_particles` - Purple floating rocks
- `purple_glow` - Purple tint on weapon
- `scarlet_rot_trail` - Red particles while moving
- `flower_petals` - Pink petals floating
- `golden_sparkle` - Sparkle particles
- `erdtree_blessing` - Golden light rays
- `golden_leaves` - Falling leaf particles
- `light_rays` - Volumetric light beams

### Priority 2: Dark Souls 3

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Coiled Sword Fragment | Accessory | Common | Icon only | [ ] |
| Farron Greatsword | Weapon (Greatsword) | Uncommon | Greatsword + wolf motif | [ ] |
| Dragonslayer Swordspear | Weapon (Spear) | Rare | Ornate spear + lightning | [ ] |
| Coiled Sword | Weapon (Sword) | Legendary | Twisted sword + fire | [ ] |

**Dark Souls 3 Visual Effects:**
- `ember_glow` - Orange/red pulsing glow
- `wolf_blood_aura` - Blue-gray misty aura
- `lightning_crackle` - Electric arcs
- `storm_particles` - Wind/cloud particles
- `ember_trail` - Fire particles while moving
- `flame_idle_glow` - Fire effect when standing
- `heat_distortion` - Screen distortion shader

### Priority 3: Stardew Valley

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Farmer's Straw Hat | Head Armor | Common | Straw hat | [ ] |
| Master Farmer's Hoe | Weapon (Tool) | Uncommon | Golden hoe/pickaxe | [ ] |
| Stardrop Pendant | Accessory | Epic | Icon only + particles | [ ] |
| Prairie King's Crown | Head Armor | Legendary | Pixel art crown | [ ] |

**Stardew Valley Visual Effects:**
- `golden_sparkle` - Gold star particles
- `stardust_trail` - Rainbow sparkle trail
- `healing_aura` - Green healing particles
- `pixel_sparkle` - 8-bit style sparkles
- `retro_trail` - Pixelated motion trail

### Priority 4: Hollow Knight

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Pure Nail | Weapon (Sword) | Uncommon | Thin sword + white | [ ] |
| Shade Cloak | Cape | Rare | Black flowing cape | [ ] |
| Void Heart Charm | Accessory | Legendary | Icon only | [ ] |

**Hollow Knight Visual Effects:**
- `void_particles` - Black/purple particles
- `void_trail` - Dark smoke trail
- `shadow_dash` - Blur on movement
- `void_aura` - Dark pulsing aura
- `shadow_tendrils` - Wispy dark extensions
- `dark_burst` - Explosion of darkness

### Priority 5: Hades

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Stygian Blade | Weapon (Sword) | Common | Red-tinted sword | [ ] |
| Adamant Rail | Weapon (Ranged) | Uncommon | Crossbow/gun | [ ] |
| Prince's Laurel Crown | Head Armor | Epic | Laurel wreath | [ ] |

**Hades Visual Effects:**
- `blood_red_glow` - Red ambient glow
- `infernal_glow` - Orange/red fire
- `divine_glow` - Golden godly light
- `laurel_particles` - Green leaves floating

### Priority 6: Terraria

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Eye of Cthulhu Shield | Shield | Common | Eye-themed shield | [ ] |
| Terra Blade | Weapon (Sword) | Legendary | Green glowing sword | [ ] |

**Terraria Visual Effects:**
- `eerie_glow` - Unsettling red/purple
- `terra_beam` - Green projectile trail
- `green_glow` - Nature green aura
- `sword_projectile` - Ranged swing effect

### Priority 7: Sekiro

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Gyoubu's Broken Horn Spear | Weapon (Spear) | Common | Ornate spear | [ ] |
| Mortal Blade | Weapon (Katana) | Legendary | Red katana | [ ] |

**Sekiro Visual Effects:**
- `crimson_slash` - Red slash trail
- `death_kanji` - Japanese character overlay
- `blood_mist` - Red particle mist

### Priority 8: The Witcher 3

| Item | Type | Rarity | LPC Source | Status |
|------|------|--------|------------|--------|
| Witcher's Silver Sword | Weapon (Sword) | Common | Silver-tinted sword | [ ] |
| Grandmaster Wolf Chest | Chest Armor | Legendary | Ornate medium armor | [ ] |

**Witcher 3 Visual Effects:**
- `silver_gleam` - Silver reflection
- `wolf_school_glow` - Amber medallion glow
- `danger_sense` - Alert particles

### Asset Counts Summary

| Game | Common | Uncommon | Rare | Epic | Legendary | Total |
|------|--------|----------|------|------|-----------|-------|
| Elden Ring | 2 | 2 | 1 | 1 | 1 | 7 |
| Dark Souls 3 | 1 | 1 | 1 | 0 | 1 | 4 |
| Stardew Valley | 1 | 1 | 0 | 1 | 1 | 4 |
| Hollow Knight | 0 | 1 | 1 | 0 | 1 | 3 |
| Hades | 1 | 1 | 0 | 1 | 0 | 3 |
| Terraria | 1 | 0 | 0 | 0 | 1 | 2 |
| Sekiro | 1 | 0 | 0 | 0 | 1 | 2 |
| The Witcher 3 | 1 | 0 | 0 | 0 | 1 | 2 |
| **TOTAL** | **8** | **6** | **3** | **3** | **7** | **27** |

**By Asset Type:**
- Weapons: 15
- Head Armor: 6
- Chest Armor: 2
- Capes: 1
- Shields: 1
- Accessories (icon only): 4
- **Full sprite sheets needed**: 23
- **Icons only**: 4

---

## Asset Generation Guide

**Generator URL:** https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/

### BATCH 1: Common Tier (Do These First)

*These have 40%+ unlock rates - most players will have access*

#### 1. Grafted Blade Greatsword (Elden Ring)
**Achievement:** Godrick the Grafted (72.3% unlock)
**Item Type:** Weapon - Greatsword

**Generator Settings:**
- Go to: Weapons -> Swords
- Select: `Greatsword` or `Longsword` (largest available)
- Color: Golden/brass tint if available

**Export:**
- Download the sprite sheet
- Save animations to: `assets/equipment/forged/weapons/grafted_blade/`
  - `walk.png`
  - `slash.png`
  - `thrust.png`
  - `hurt.png`

**Icon:** Crop a 64x64 from the idle frame -> `assets/icons/forged/weapons/grafted_blade.png`

#### 2. Coiled Sword Fragment (Dark Souls 3)
**Achievement:** Iudex Gundyr (85.2% unlock)
**Item Type:** Accessory (Icon only)

**This is icon-only** - no sprite sheet needed.

**Create a 64x64 icon** showing:
- A twisted/coiled sword fragment
- Orange/ember glow
- Save to: `assets/icons/forged/accessories/coiled_sword_fragment.png`

*Can be hand-drawn or extracted from existing sword sprite*

#### 3. Farmer's Straw Hat (Stardew Valley)
**Achievement:** Greenhorn (89.4% unlock)
**Item Type:** Head Armor - Hat

**Generator Settings:**
- Go to: Head -> Hats
- Select: `Straw Hat` or `Farmer Hat` if available
- If not available, use `Bandana` or simple hat
- Color: Yellow/tan straw color

**Export:**
- Save to: `assets/equipment/forged/armor/head/straw_hat/`
  - `walk.png`
  - `slash.png`
  - `thrust.png`
  - `hurt.png`

**Icon:** `assets/icons/forged/armor/farmers_straw_hat.png`

#### 4. Stygian Blade (Hades)
**Achievement:** Escaped Tartarus (76.8% unlock)
**Item Type:** Weapon - Sword

**Generator Settings:**
- Go to: Weapons -> Swords
- Select: `Longsword` or `Broadsword`
- Color: Dark red/crimson tint

**Export:**
- Save to: `assets/equipment/forged/weapons/stygian_blade/`

**Icon:** `assets/icons/forged/weapons/stygian_blade.png`

#### 5. Eye of Cthulhu Shield (Terraria)
**Achievement:** Slayer of Worlds (54.2% unlock)
**Item Type:** Shield

**Generator Settings:**
- Go to: Equipment -> Shields
- Select: Round shield
- Color: Red/purple eye theme if possible

**Export:**
- Save to: `assets/equipment/forged/shields/eye_shield/`
  - `walk.png` (shield visible while walking)

**Icon:** `assets/icons/forged/shields/eye_shield.png`

#### 6. Gyoubu's Broken Horn Spear (Sekiro)
**Achievement:** Gyoubu Masataka Oniwa (68.4% unlock)
**Item Type:** Weapon - Spear

**Generator Settings:**
- Go to: Weapons -> Polearms/Spears
- Select: `Spear` or `Pike`
- Color: Standard metal, slightly worn

**Export:**
- Save to: `assets/equipment/forged/weapons/gyoubu_spear/`

**Icon:** `assets/icons/forged/weapons/gyoubu_spear.png`

#### 7. Witcher's Silver Sword (The Witcher 3)
**Achievement:** Lilac and Gooseberries (81.3% unlock)
**Item Type:** Weapon - Sword

**Generator Settings:**
- Go to: Weapons -> Swords
- Select: `Longsword`
- Color: Silver/bright metal tint

**Export:**
- Save to: `assets/equipment/forged/weapons/witcher_silver_sword/`

**Icon:** `assets/icons/forged/weapons/witcher_silver_sword.png`

#### 8. Margit's Shackle (Elden Ring)
**Achievement:** Margit, the Fell Omen (78.5% unlock)
**Item Type:** Accessory (Icon only)

**This is icon-only** - no sprite sheet needed.

**Create a 64x64 icon** showing:
- A broken chain/shackle
- Dark metal with golden runes
- Save to: `assets/icons/forged/accessories/margits_shackle.png`

### BATCH 2-5: See full checklist above

For complete generation instructions for Uncommon, Rare, Epic, and Legendary tiers, follow the same pattern as Common tier items.

### Using the Splitter Tool

We have a Python script that automates splitting full LPC spritesheets into individual animation files.

**Workflow:**

1. **Go to the LPC Generator:** https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/
2. **Configure your item** (select weapon, armor, colors)
3. **Download the full spritesheet** (PNG button)
4. **Run the splitter tool:**

```batch
# Windows (from project root):
tools\split_spritesheet.bat downloaded.png assets\equipment\forged\weapons\item_name\ weapon

# Or directly with Python:
python tools/lpc_spritesheet_splitter.py split downloaded.png assets/equipment/forged/weapons/item_name/ --type weapon
```

**Item Types:**
- `weapon` - Extracts walk, slash, thrust, hurt
- `armor` - Extracts walk, slash, thrust, hurt
- `shield` - Extracts walk only
- `cape` - Extracts walk, slash, thrust, hurt
- `all` - Extracts all animations including spellcast/shoot

**Creating Icons:**

```batch
python tools/lpc_spritesheet_splitter.py icon downloaded.png assets/icons/forged/weapons/item_name.png --frame 0,8
```

The `--frame X,Y` specifies which frame to use (default 0,8 = first frame of walk animation facing down).

---

## Icon Standards

All forge icons must follow these standards for consistent shop/vendor grid presentation.

**Tool Location:** `assets/icons/forged/icon_standards.py`

### Spec

| Property | Value |
|----------|-------|
| Canvas Size | 64x64 pixels |
| Format | PNG with transparency (RGBA) |
| Min Padding | 4px from edge |
| Centering | All content centered in canvas |

### Orientation by Category

| Category | Orientation |
|----------|-------------|
| **Weapons** | Diagonal ~45 deg, tip pointing **upper-right**, handle lower-left |
| **Armor** | Upright, centered (crowns/helmets/hats) |
| **Shields** | Upright, centered |
| **Accessories** | Natural orientation, centered |

### Validation Commands

```bash
# Check if new icons meet standards
python assets/icons/forged/icon_standards.py --validate

# Auto-fix centering on all icons
python assets/icons/forged/icon_standards.py --fix

# Fix a weapon's orientation to point upper-right
python assets/icons/forged/icon_standards.py --orient weapons/new_sword.png upper-right

# Orientation options: upper-right, upper-left, flip-h, flip-v, rotate-N

# Regenerate preview grid
python assets/icons/forged/icon_standards.py --preview
```

### Workflow for New Icons

1. **Create/export** the 64x64 icon
2. **Run validation:** `python icon_standards.py --validate`
3. **Fix centering:** `python icon_standards.py --fix` (auto-centers all)
4. **Check orientation:** If weapon points wrong way, use `--orient` to flip
5. **Preview:** `python icon_standards.py --preview` to see grid

### Preview Grid

The preview grid (`assets/icons/forged/preview_grid.png`) shows all icons in a shop-style layout. Regenerate after adding new icons to verify visual consistency.

---

## Implementation Checklist

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

### Phase 6: Armory Scene (Launch Blocking)
- [ ] Basic scene structure
- [ ] Guest mode (Enter World button works)
- [ ] Authenticated mode (shows Mantle card)
- [ ] Character display with current tier armor
- [ ] Enter World transitions to game

### Phase 7: Armory Rewards (Launch Target)
- [ ] Pending unlocks detection
- [ ] Basic claim sequence (items appear)
- [ ] Tier upgrade detection and display
- [ ] Summary screen

### Phase 8: Armory Polish (Post-Launch)
- [ ] Full claim animation with particles
- [ ] Sound design implementation
- [ ] Loadout preview system
- [ ] Forge sub-area
- [ ] Screenshot/share button
- [ ] Locked items with "how to unlock"

---

## Achievement -> Item Mapping

**File:** `scripts/systems/ForgeItemDB.gd`

```gdscript
extends Node

# Maps achievement API names to in-game items
const FORGE_ITEMS = {
    # DARK SOULS 3
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
    # ... more items
}

# Lookup function
func get_item_for_achievement(provider: String, app_id: String, api_name: String) -> Dictionary:
    var key = "%s_%s_%s" % [provider, app_id, api_name]
    return FORGE_ITEMS.get(key, {})
```

### Item Rarity Tiers

| Rarity | Source | Visual Treatment |
|--------|--------|------------------|
| Rare | Rare achievements (< 10% unlock) | Blue glow, subtle particles |
| Epic | Epic achievements (< 5% unlock) | Purple glow, medium particles |
| Legendary | Legendary achievements (< 1% unlock) | Orange glow, fire/special particles |
| Mythic | Ultra-rare / special events | Pink/magenta, heavy effects |

---

## Key Files

```
scripts/
+-- systems/
|   +-- ForgeItemDB.gd        # Achievement -> Item mapping
|   +-- GlobalForgeFeed.gd    # Legendary feed polling
+-- ui/
|   +-- ForgeUI.gd            # Main forge interface
|   +-- ForgeItemCard.gd      # Individual item display
|   +-- ForgeFeedEntry.gd     # Feed list item
|   +-- Armory.gd             # Armory scene controller
+-- world/
    +-- ForgeObject.gd        # In-world interactable

scenes/
+-- ui/
|   +-- ForgeUI.tscn
|   +-- ForgeItemCard.tscn
|   +-- ForgeFeedEntry.tscn
|   +-- Armory.tscn
+-- world/
    +-- Forge.tscn            # In-world forge object
```

---

## The Golden Rule

**Every player type should feel good leaving the Armory.**

- Guest: "That was easy, let's see what this game is about"
- New Player: "Can't wait to link my Steam and see what I get"
- Casual: "Cool, I have some stuff. Let's play"
- Veteran: "I look AMAZING. Time to show off"
- Returning: "New rewards! This game keeps giving"

The Armory is not a gate. It's a gift shop where everything is already paid for.
