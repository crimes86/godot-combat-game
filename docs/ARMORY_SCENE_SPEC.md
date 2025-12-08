# Mantle Armory Scene Specification

> **For Godot Engineer:** This is a dedicated Godot scene that sits between authentication and the game world. It handles all player types gracefully - from guests to Mythic veterans.

---

## Overview

The Armory is a **staging area** where players:
1. See their gaming identity visualized
2. Claim new cosmetic unlocks
3. Preview their character
4. Choose to enter the game world

**Critical principle:** This scene must feel welcoming to ALL players, especially those with no gaming history. It's an invitation, not a gate.

---

## Player Types

| Type | Description | Experience Goal |
|------|-------------|-----------------|
| **Guest** | No Mantle account, just wants to try the game | "Jump right in, see what it's about" |
| **New Player** | Has Mantle account, no providers linked | "Your journey starts here" |
| **Casual** | 1 provider, some achievements | "Look what you've earned" |
| **Veteran** | Multiple providers, high tier | "Behold your legacy" |
| **Returning** | Has pending unlocks | "New rewards await!" |

---

## Scene Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MANTLE ARMORY                                   │
│                                                                              │
│  ┌──────────────┐                    ┌─────────────────────────────────┐    │
│  │              │                    │                                 │    │
│  │   LEFT       │                    │         CENTER                  │    │
│  │   PANEL      │                    │                                 │    │
│  │              │                    │      Character Display          │    │
│  │  - Mantle    │                    │      (animated, rotatable)      │    │
│  │    Card      │                    │                                 │    │
│  │              │                    │                                 │    │
│  │  - Provider  │                    │                                 │    │
│  │    Badges    │                    │                                 │    │
│  │              │                    │                                 │    │
│  │  - Pending   │                    │                                 │    │
│  │    Unlocks   │                    │                                 │    │
│  │              │                    └─────────────────────────────────┘    │
│  └──────────────┘                                                           │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         ACTION BAR                                    │   │
│  │   [Claim Rewards]    [Manage Loadout]    [ENTER WORLD]               │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Experience By Player Type

### 1. Guest (No Account)

**Goal:** Zero friction. Let them play immediately.

```
Scene State:
- Minimal UI, clean and inviting
- Character: Randomized basic appearance
- Background: Warm, welcoming lighting

UI Shows:
┌────────────────────────────────────────────┐
│                                            │
│   Welcome, Traveler                        │
│                                            │
│   "Every legend starts somewhere."         │
│                                            │
│   ┌────────────────────────────────────┐   │
│   │         [ENTER WORLD]              │   │ ← BIG, primary button
│   │         Start your adventure       │   │
│   └────────────────────────────────────┘   │
│                                            │
│   ┌────────────────────────────────────┐   │
│   │    [Create Account / Sign In]      │   │ ← Secondary, subtle
│   │    Link your gaming history        │   │
│   └────────────────────────────────────┘   │
│                                            │
│   "Players who link accounts unlock       │
│    cosmetics from their gaming history"   │
│                                            │
└────────────────────────────────────────────┘

No shame. No "you're missing out." Just an invitation.
```

**Flow:**
1. Guest clicks "Enter World"
2. Spawns with basic randomized appearance
3. Plays the game
4. Sees other players with cool cosmetics
5. Curiosity drives them to create account later

### 2. New Player (Account, No Providers)

**Goal:** Excitement about potential, not shame about emptiness.

```
Scene State:
- Armory is "new" - clean, torches lit, empty but ready
- Character: Basic gear, but standing proudly
- Mantle Card: Shows "Initiate" tier

UI Shows:
┌────────────────────────────────────────────┐
│                                            │
│   Welcome, [Username]                      │
│   ═══════════════════                      │
│                                            │
│   ┌─────────────────┐                      │
│   │   INITIATE      │  Your Mantle tier    │
│   │   ────────────  │                      │
│   │   0 achievements│  Link a gaming       │
│   │   0 providers   │  platform to begin   │
│   └─────────────────┘                      │
│                                            │
│   Your armory awaits your history.         │
│                                            │
│   ┌─────────────────────────────────────┐  │
│   │  [Link Steam]  [Link Battle.net]    │  │ ← Optional, not blocking
│   │  [Link Xbox]   [Link PlayStation]   │  │
│   └─────────────────────────────────────┘  │
│                                            │
│   ┌─────────────────────────────────────┐  │
│   │           [ENTER WORLD]             │  │ ← Still primary
│   │      Play now, link later           │  │
│   └─────────────────────────────────────┘  │
│                                            │
└────────────────────────────────────────────┘

Message: "You can always link accounts later from the menu."
```

**Key:** The "Enter World" button is ALWAYS available and prominent. Linking is optional.

### 3. Casual Player (1 Provider, Some Achievements)

**Goal:** Show them what they've earned, make them feel good.

```
Scene State:
- Armory has some items on racks
- Character wearing tier-appropriate armor
- Warm, appreciative tone

UI Shows:
┌────────────────────────────────────────────┐
│                                            │
│   Welcome back, [Username]                 │
│   ═════════════════════════                │
│                                            │
│   ┌─────────────────┐   ┌───────────────┐  │
│   │   SILVER        │   │ STEAM ✓       │  │
│   │   ────────────  │   │ 523 cheevos   │  │
│   │   523 total     │   │ Last sync: 2d │  │
│   │   Score: 523    │   └───────────────┘  │
│   └─────────────────┘                      │
│                                            │
│   Your achievements unlocked:              │
│   • Silver Tier Armor Set                  │
│   • Steam Verified Badge                   │
│   • 2 Weapon Skins                         │
│                                            │
│   ┌─────────────────────────────────────┐  │
│   │           [ENTER WORLD]             │  │
│   └─────────────────────────────────────┘  │
│                                            │
│   [Sync Achievements]  [Link Another]      │
│                                            │
└────────────────────────────────────────────┘
```

### 4. Veteran (High Tier, Multiple Providers)

**Goal:** Make them feel like a legend. This is their reward.

```
Scene State:
- Armory is FULL - weapons, armor, trophies everywhere
- Dramatic lighting, particle effects
- Character has aura, glowing elements

UI Shows:
┌────────────────────────────────────────────┐
│                                            │
│   ═══════════════════════════════════════  │
│   ║         MYTHIC CHAMPION              ║  │
│   ║           [Username]                 ║  │
│   ═══════════════════════════════════════  │
│                                            │
│   ┌─────────────────┐   ┌───────────────┐  │
│   │   MYTHIC ✦      │   │ STEAM ✓       │  │
│   │   ────────────  │   │ BATTLE.NET ✓  │  │
│   │   7,847 total   │   │ XBOX ✓        │  │
│   │   Score: 9,023  │   │ PSN ✓         │  │
│   └─────────────────┘   └───────────────┘  │
│                                            │
│   Your legend speaks:                      │
│   • 12 Legendary Achievements              │
│   • 5 Forged Items (On-Chain)              │
│   • Full Mythic Armor Set                  │
│                                            │
│   ┌─────────────────────────────────────┐  │
│   │          [ENTER WORLD]              │  │
│   │       "Let them see you."           │  │
│   └─────────────────────────────────────┘  │
│                                            │
└────────────────────────────────────────────┘
```

### 5. Returning Player (Pending Unlocks)

**Goal:** Excitement, anticipation, reward.

```
Scene State:
- Glowing chest/forge in center
- Pulsing light effect
- Sound: Gentle chime loop

UI Shows:
┌────────────────────────────────────────────┐
│                                            │
│   Welcome back, [Username]                 │
│                                            │
│   ╔════════════════════════════════════╗   │
│   ║   ✨ 3 NEW REWARDS AWAIT ✨        ║   │ ← Animated, attention-grabbing
│   ╚════════════════════════════════════╝   │
│                                            │
│   Since your last visit:                   │
│   • Synced 47 new achievements             │
│   • Reached GOLD tier!                     │
│   • 1 item ready to forge                  │
│                                            │
│   ┌─────────────────────────────────────┐  │
│   │        [CLAIM REWARDS]              │  │ ← Primary, pulsing
│   └─────────────────────────────────────┘  │
│                                            │
│   [Skip for now]           [Enter World]   │ ← Always available
│                                            │
└────────────────────────────────────────────┘
```

---

## The Claim Sequence

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
   ┌──────────────────────────────────┐
   │  ✦ COILED SWORD                  │
   │  ─────────────────────────────── │
   │  Weapon Skin • Legendary         │
   │                                  │
   │  "The Dark Soul"                 │
   │  Dark Souls III - 100%           │
   │                                  │
   │  [EARNED] - You completed this   │
   └──────────────────────────────────┘
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

        ╔═══════════════════════╗
        ║    TIER ACHIEVED      ║
        ║        GOLD           ║
        ╚═══════════════════════╝

4. Aura effect fades in (if applicable)
5. Sound: Triumphant fanfare
```

### Phase 4: Summary

```
┌────────────────────────────────────────────────────┐
│                                                    │
│              REWARDS CLAIMED                       │
│              ═══════════════                       │
│                                                    │
│   +1 Weapon Skin    Coiled Sword (Legendary)      │
│   +1 Cape           Ashen One                      │
│   +1 Walk Effect    Ember Steps                    │
│                                                    │
│   ┌──────────────────────────────────────────┐    │
│   │  INITIATE → GOLD                         │    │
│   │  New armor set unlocked!                 │    │
│   └──────────────────────────────────────────┘    │
│                                                    │
│   ┌─────────────┐    ┌─────────────────────────┐  │
│   │  [PREVIEW]  │    │     [ENTER WORLD]       │  │
│   │  See loadout│    │   Show them who you are │  │
│   └─────────────┘    └─────────────────────────┘  │
│                                                    │
│   [📸 Screenshot]                                  │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

## The Loadout Preview

Accessed via "Preview" or "Manage Loadout":

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              LOADOUT                                         │
│                                                                              │
│  ┌───────────────────────────────────┐    ┌───────────────────────────────┐ │
│  │                                   │    │  EQUIPPED                     │ │
│  │                                   │    │  ─────────                    │ │
│  │                                   │    │                               │ │
│  │        [CHARACTER MODEL]          │    │  Head:    Elden Crown ✓      │ │
│  │        (slowly rotating)          │    │  Cape:    Ashen One ✓        │ │
│  │                                   │    │  Weapon:  Coiled Sword ✓     │ │
│  │                                   │    │  Aura:    Ember Glow ✓       │ │
│  │                                   │    │  Effect:  Ember Steps ✓      │ │
│  │                                   │    │                               │ │
│  └───────────────────────────────────┘    │  ─────────                    │ │
│                                           │  AVAILABLE (tap to equip)     │ │
│  ┌───────────────────────────────────┐    │                               │ │
│  │ ← Rotate                Rotate → │    │  • Steam Badge               │ │
│  └───────────────────────────────────┘    │  • Golden Wrench             │ │
│                                           │  • Blizzard Shoulder         │ │
│                                           │                               │ │
│                                           │  ─────────                    │ │
│                                           │  LOCKED (grayed)              │ │
│                                           │                               │ │
│                                           │  🔒 Thunderfury               │ │
│                                           │     "Obtain in WoW"           │ │
│                                           │                               │ │
│                                           │  🔒 Mythic Aura               │ │
│                                           │     "Reach Mythic tier"       │ │
│                                           └───────────────────────────────┘ │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  [SAVE LOADOUT]                           [BACK TO ARMORY]           │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key features:**
- Character rotates (drag or arrow buttons)
- Tap equipped item to unequip
- Tap available item to equip
- Locked items show "how to unlock" on hover/tap
- Changes preview in real-time

---

## The Forge Sub-Area

Separate area for minting NFTs:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                               THE FORGE                                      │
│                                                                              │
│   "Bind your achievements to the chain. Once forged, yours forever."        │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  FORGEABLE (Rare+, Original Claims Only)                             │   │
│  ├──────────────────────────────────────────────────────────────────────┤   │
│  │                                                                      │   │
│  │  ☐ The Dark Soul        Legendary    Dark Souls III                 │   │
│  │  ☐ Elden Lord           Epic         Elden Ring                     │   │
│  │  ☐ Against All Odds     Rare         Hades                          │   │
│  │  ☑ Completion           Rare         Hollow Knight                  │   │
│  │                                                                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌────────────────────────────────────┐                                     │
│  │  Wallet: 0x1234...5678 ✓           │                                     │
│  │  Selected: 1 achievement           │                                     │
│  │  Gas estimate: ~$0.02              │                                     │
│  └────────────────────────────────────┘                                     │
│                                                                              │
│  ┌─────────────────────┐    ┌─────────────────────────────────────────┐    │
│  │  [BACK TO ARMORY]   │    │         [FORGE SELECTED]                │    │
│  └─────────────────────┘    └─────────────────────────────────────────┘    │
│                                                                              │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│  ALREADY FORGED                                                              │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  ⚒ Thunderfury       Legendary   WoW        Token #1847             │    │
│  │  ⚒ Golden Wrench     Legendary   TF2        Token #2103             │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Forge animation:**
1. Selected items float to central anvil
2. Anvil glows hot
3. Hammer strikes (3 times, sparks fly)
4. Items transform - ornate glow effect added
5. "FORGED" stamp appears on each
6. Blockchain confirmation message
7. Items return to collection with permanent glow

---

## Navigation Flow

```
                                    ┌─────────────────┐
                                    │   GAME START    │
                                    └────────┬────────┘
                                             │
                              ┌──────────────┴──────────────┐
                              ▼                             ▼
                       [Has Token]                    [No Token]
                              │                             │
                              ▼                             ▼
                        GET /api/me                   Show Armory
                              │                       (Guest Mode)
                   ┌──────────┴──────────┐                 │
                   ▼                     ▼                 │
              [Success]             [401 Error]            │
                   │                     │                 │
                   ▼                     ▼                 │
             Show Armory           Clear token             │
             (Full Mode)           Show Armory ◄───────────┘
                   │               (Guest Mode)
                   │                     │
                   ▼                     ▼
        ┌──────────────────────────────────────────┐
        │              MANTLE ARMORY               │
        ├──────────────────────────────────────────┤
        │                                          │
        │   [Claim Rewards] ──► Claim Sequence     │
        │          │                  │            │
        │          ▼                  ▼            │
        │   [Manage Loadout] ──► Loadout Preview   │
        │          │                  │            │
        │          ▼                  ▼            │
        │   [The Forge] ──────► Forge Sub-Area     │
        │          │                  │            │
        │          ▼                  ▼            │
        │   [Link Provider] ──► Opens Browser      │
        │          │                  │            │
        │          ▼                  ▼            │
        │   [ENTER WORLD] ─────────────────────────┼───► Game World
        │                                          │
        └──────────────────────────────────────────┘
```

---

## Technical Implementation

### Scene Structure

```
ArmoryScene (Node2D or Control)
├── Background
│   ├── ArmoryEnvironment (animated background)
│   └── AmbientParticles
├── CharacterDisplay
│   ├── CharacterSprite (LPC layers)
│   ├── AuraEffect
│   └── GroundEffect
├── LeftPanel
│   ├── MantleCard
│   ├── ProviderBadges
│   └── PendingUnlocksCounter
├── ActionBar
│   ├── ClaimButton
│   ├── LoadoutButton
│   └── EnterWorldButton
├── ClaimSequence (hidden until needed)
│   ├── Forge
│   ├── ItemRevealContainer
│   └── SummaryPanel
├── LoadoutPreview (hidden until needed)
│   ├── CharacterPreview
│   ├── EquipmentList
│   └── LockedItemsList
└── ForgeArea (hidden until needed)
    ├── ForgeableList
    ├── WalletInfo
    └── ForgeButton
```

### Key Scripts

#### ArmoryManager.gd

```gdscript
extends Control

signal entered_world
signal claim_completed

enum ArmoryState { GUEST, NEW_PLAYER, CASUAL, VETERAN, PENDING_UNLOCKS }

var current_state: ArmoryState
var pending_items: Array = []
var profile: Dictionary = {}

func _ready():
    determine_state()
    setup_ui_for_state()

func determine_state():
    if not MantleAuth.is_logged_in():
        current_state = ArmoryState.GUEST
        return

    profile = await MantleAuth.get_profile()
    pending_items = calculate_pending_unlocks()

    if pending_items.size() > 0:
        current_state = ArmoryState.PENDING_UNLOCKS
    elif profile.providers.size() == 0:
        current_state = ArmoryState.NEW_PLAYER
    elif profile.total_achievements < 1000:
        current_state = ArmoryState.CASUAL
    else:
        current_state = ArmoryState.VETERAN

func setup_ui_for_state():
    match current_state:
        ArmoryState.GUEST:
            show_guest_ui()
        ArmoryState.NEW_PLAYER:
            show_new_player_ui()
        ArmoryState.PENDING_UNLOCKS:
            show_pending_ui()
        _:
            show_standard_ui()

func calculate_pending_unlocks() -> Array:
    var last_claimed = load_last_claimed_timestamp()
    var pending = []

    for ach in profile.get("achievements", []):
        if ach.date_credited > last_claimed:
            pending.append({"type": "achievement", "data": ach})

    for forged in profile.get("forged_items", []):
        if forged.forged_at > last_claimed:
            pending.append({"type": "forged", "data": forged})

    # Check for tier upgrade
    var last_tier = load_last_tier()
    if profile.mantle.tier != last_tier:
        pending.append({"type": "tier_upgrade", "data": profile.mantle})

    return pending

func _on_enter_world_pressed():
    save_last_claimed_timestamp()
    save_last_tier(profile.mantle.tier)
    entered_world.emit()

func _on_claim_rewards_pressed():
    $ClaimSequence.start(pending_items)
```

#### ClaimSequence.gd

```gdscript
extends Control

signal sequence_completed

var items_to_claim: Array = []
var current_index: int = 0

func start(items: Array):
    items_to_claim = items
    current_index = 0
    visible = true
    await play_anticipation()
    await reveal_items()
    await show_summary()
    sequence_completed.emit()

func play_anticipation():
    # Dim background
    $Dimmer.modulate.a = 0
    var tween = create_tween()
    tween.tween_property($Dimmer, "modulate:a", 0.7, 1.0)

    # Intensify forge glow
    tween.parallel().tween_property($Forge, "energy", 3.0, 2.0)

    # Play building sound
    $BuildupSound.play()

    await tween.finished

func reveal_items():
    for item in items_to_claim:
        await reveal_single_item(item)
        await get_tree().create_timer(0.5).timeout

func reveal_single_item(item: Dictionary):
    var reveal_node = $ItemReveal

    # Item rises from forge
    reveal_node.position.y = 100
    reveal_node.modulate.a = 0

    var tween = create_tween()
    tween.tween_property(reveal_node, "position:y", 0, 1.0).set_ease(Tween.EASE_OUT)
    tween.parallel().tween_property(reveal_node, "modulate:a", 1.0, 0.5)

    # Show item card
    await tween.finished
    $ItemCard.display(item)

    # Play sound based on rarity
    play_reveal_sound(item.data.get("rarity_tier", "Common"))

    # Particles
    $RevealParticles.emitting = true

    await get_tree().create_timer(2.0).timeout

    # Item flies to character
    tween = create_tween()
    tween.tween_property(reveal_node, "position", $Character.position, 0.5)
    tween.parallel().tween_property(reveal_node, "modulate:a", 0, 0.3)

    await tween.finished

    # Apply to character
    MantleCosmetics.apply_item($Character, item)

func play_reveal_sound(rarity: String):
    match rarity:
        "Legendary":
            $LegendaryChime.play()
        "Epic":
            $EpicChime.play()
        "Rare":
            $RareChime.play()
        _:
            $CommonChime.play()

func show_summary():
    $SummaryPanel.populate(items_to_claim)
    $SummaryPanel.visible = true

    # Animate in
    $SummaryPanel.modulate.a = 0
    var tween = create_tween()
    tween.tween_property($SummaryPanel, "modulate:a", 1.0, 0.5)
```

### Persistence

```gdscript
# Save/load last claimed timestamp
const CLAIM_FILE = "user://last_claimed.dat"

func save_last_claimed_timestamp():
    var file = FileAccess.open(CLAIM_FILE, FileAccess.WRITE)
    file.store_64(int(Time.get_unix_time_from_system()))

func load_last_claimed_timestamp() -> int:
    if not FileAccess.file_exists(CLAIM_FILE):
        return 0
    var file = FileAccess.open(CLAIM_FILE, FileAccess.READ)
    return file.get_64()

# Save/load last tier (for detecting upgrades)
const TIER_FILE = "user://last_tier.dat"

func save_last_tier(tier: String):
    var file = FileAccess.open(TIER_FILE, FileAccess.WRITE)
    file.store_string(tier)

func load_last_tier() -> String:
    if not FileAccess.file_exists(TIER_FILE):
        return "initiate"
    var file = FileAccess.open(TIER_FILE, FileAccess.READ)
    return file.get_as_text()
```

---

## Sound Design

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

---

## Visual Polish

### Lighting by Player Type

| Type | Lighting | Atmosphere |
|------|----------|------------|
| Guest | Warm, soft, inviting | "Come on in" |
| New Player | Clean, bright, potential | "Fresh start" |
| Casual | Comfortable, homey | "Your space" |
| Veteran | Dramatic, epic, reverent | "Behold" |
| Pending | Glowing, pulsing | "Something awaits" |

### Particle Systems Needed

1. **Ambient dust** - Floating in light beams
2. **Forge glow** - Warm orange emanating
3. **Item reveal** - Burst outward on reveal
4. **Tier upgrade** - Spiral around character
5. **Aura effects** - Per tier (Diamond sparkle, Legendary ember, Mythic ethereal)

---

## Mobile/Controller Considerations

- All buttons large enough for touch
- D-pad navigation support
- Clear focus states
- Skip option for claim sequence (hold button)
- Simplified loadout UI for controllers

---

## Implementation Priority

### Phase 1: Functional (Launch Blocking)

1. [ ] Basic scene structure
2. [ ] Guest mode (Enter World button works)
3. [ ] Authenticated mode (shows Mantle card)
4. [ ] Character display with current tier armor
5. [ ] Enter World transitions to game

### Phase 2: Rewarding (Launch Target)

6. [ ] Pending unlocks detection
7. [ ] Basic claim sequence (items appear)
8. [ ] Tier upgrade detection and display
9. [ ] Summary screen

### Phase 3: Delightful (Post-Launch)

10. [ ] Full claim animation with particles
11. [ ] Sound design implementation
12. [ ] Loadout preview system
13. [ ] Forge sub-area
14. [ ] Screenshot/share button
15. [ ] Locked items with "how to unlock"

---

## API Endpoints Used

| Endpoint | Purpose | See |
|----------|---------|-----|
| `GET /api/me` | Full profile with tier, achievements | API_CONTRACT.md |
| `GET /api/wallet/forged` | Forged NFT items | API_CONTRACT.md |
| `GET /api/tiers` | Tier definitions (cache on load) | API_CONTRACT.md |
| `POST /api/wallet/forge` | Forge new items | API_CONTRACT.md |

---

## The Golden Rule

**Every player type should feel good leaving the Armory.**

- Guest: "That was easy, let's see what this game is about"
- New Player: "Can't wait to link my Steam and see what I get"
- Casual: "Cool, I have some stuff. Let's play"
- Veteran: "I look AMAZING. Time to show off"
- Returning: "New rewards! This game keeps giving"

The Armory is not a gate. It's a gift shop where everything is already paid for.
