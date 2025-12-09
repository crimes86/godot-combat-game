# Forge Item Effects System

Design document for passive effects and active abilities granted by forged items.

## Overview

Forged items are **not just cosmetic** - they grant gameplay power that reflects the achievement's prestige. This creates real incentive to pursue difficult achievements in other games.

```
POWER SOURCES IN DREADLAND:

┌─────────────────────────────────────────────────────────────────┐
│                    PASSIVE EFFECTS (3 slots)                    │
│  Always-on bonuses from equipped items                          │
│  Sources: Forged items OR Native Dreadland gear                 │
├─────────────────────────────────────────────────────────────────┤
│                    ACTIVE ABILITIES (4-6 slots)                 │
│  Cooldown-based abilities on the ability bar                    │
│  Sources: Class skills, Forged legendaries, Native drops        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Part 1: Passive Effects

### 1.1 Effect Slot System

Players have **3 Passive Effect Slots**. Only 3 effects can be active simultaneously, regardless of how many effect-granting items are equipped.

```
PASSIVE EFFECT SLOTS
━━━━━━━━━━━━━━━━━━━━
[Slot 1] ████████████  "I Have Never Known Defeat" (Lifesteal)
[Slot 2] ████████████  "Link the Fire" (Death Prevention)
[Slot 3] ████████████  "Embrace the Void" (Bonus Damage)

Equipped items with effects NOT in slots:
- Moonveil: "Transient Moonlight" [DISABLED - drag to slot to enable]
- Terra Blade: "Terra Beam" [DISABLED - drag to slot to enable]
```

**Why 3 slots?**
- Forces meaningful choices
- Prevents "stack everything" meta
- Creates build diversity
- Keeps native-only players competitive

### 1.2 Effect Power Scaling

Effect strength scales with the achievement's effort_score:

```python
EFFORT_SCORE → EFFECT_POWER
━━━━━━━━━━━━━━━━━━━━━━━━━━━
90-100 (Legendary+)  →  100% power
80-89  (Legendary)   →  90% power
60-79  (Epic)        →  75% power
40-59  (Rare)        →  50% power

# Example: Lifesteal effect
# Base: 3% of damage healed
# Legendary (95 effort): 3.0% lifesteal
# Epic (70 effort): 2.25% lifesteal
# Rare (50 effort): 1.5% lifesteal
```

### 1.3 Effect Categories

```
OFFENSIVE EFFECTS
━━━━━━━━━━━━━━━━━
├── Projectile Generation
│   └── Attacks spawn additional projectiles
├── Damage Over Time
│   └── Attacks apply burning/bleeding/poison
├── Damage Amplification
│   └── Bonus damage under conditions (combo, enemy HP, etc.)
├── Area of Effect
│   └── Attacks deal splash damage
└── On-Kill Triggers
    └── Effects that proc when killing enemies

DEFENSIVE EFFECTS
━━━━━━━━━━━━━━━━━
├── Damage Mitigation
│   └── Flat or percentage damage reduction
├── Healing
│   └── Lifesteal, regeneration, burst heals
├── Death Prevention
│   └── Survive fatal damage once per cooldown
├── Shielding
│   └── Absorb damage before HP
└── Crowd Control Resistance
    └── Reduced stun/slow duration

UTILITY EFFECTS
━━━━━━━━━━━━━━━
├── Movement
│   └── Speed boosts, enhanced dodges
├── Resource Management
│   └── Stamina/mana regeneration, reduced costs
├── Detection
│   └── Enemy highlighting, danger sense
└── Economy
    └── Increased drop rates, gold find
```

### 1.4 Complete Passive Effect Definitions

#### Offensive Effects

```yaml
LIFESTEAL:
  id: "lifesteal"
  name: "I Have Never Known Defeat"
  description: "Heal for {power}% of damage dealt"
  base_power: 3.0
  scaling: percentage  # power * base_power
  trigger: on_hit
  source_items: ["hand_of_malenia"]
  native_equivalent: "Vampiric Enchantment"

EXECUTE_DAMAGE:
  id: "execute_damage"
  name: "Sever Immortality"
  description: "Deal {power}% bonus damage to enemies above 50% HP"
  base_power: 25.0
  scaling: percentage
  trigger: on_hit
  condition: "target.hp_percent > 50"
  source_items: ["mortal_blade"]
  native_equivalent: "Executioner's Edge"

PROJECTILE_ATTACK:
  id: "projectile_attack"
  name: "Terra Beam"
  description: "Attacks fire a projectile dealing {power}% of attack damage"
  base_power: 30.0
  scaling: percentage
  trigger: on_attack
  cooldown: 0.5  # seconds between projectiles
  source_items: ["terra_blade"]
  native_equivalent: "Enchanted Bowstring"

MAGIC_WAVE:
  id: "magic_wave"
  name: "Transient Moonlight"
  description: "Heavy attacks release a magic wave dealing {power}% damage"
  base_power: 40.0
  scaling: percentage
  trigger: on_heavy_attack
  source_items: ["moonveil"]
  native_equivalent: "Arcane Blade Enchant"

CHAIN_LIGHTNING:
  id: "chain_lightning"
  name: "Lightning Stake"
  description: "Heavy attacks chain lightning to {count} nearby enemies"
  base_power: 20.0  # damage per chain
  count: 3
  chain_range: 150  # pixels
  trigger: on_heavy_attack
  source_items: ["dragonslayer_swordspear"]
  native_equivalent: "Storm Caller's Wrath"

COMBO_DAMAGE:
  id: "combo_damage"
  name: "Infernal Combo"
  description: "Every 3rd consecutive hit deals {power}% bonus damage"
  base_power: 30.0
  scaling: percentage
  trigger: on_hit
  combo_count: 3
  source_items: ["stygian_blade"]
  native_equivalent: "Berserker's Fury"

DASH_DAMAGE:
  id: "dash_damage"
  name: "Wolf Blood"
  description: "Attacks during/after dodge deal {power}% bonus damage"
  base_power: 20.0
  window: 0.5  # seconds after dodge
  trigger: on_hit
  condition: "player.recently_dodged"
  source_items: ["farron_greatsword"]
  native_equivalent: "Predator's Instinct"

GRAVITY_PULL:
  id: "gravity_pull"
  name: "Starcaller Cry"
  description: "Heavy attacks pull nearby enemies toward you"
  pull_range: 200
  pull_force: 150
  trigger: on_heavy_attack
  cooldown: 3.0
  source_items: ["radahns_greatswords"]
  native_equivalent: "Graviton Hammer"

CHARGED_DAMAGE:
  id: "charged_damage"
  name: "Nail Arts"
  description: "Fully charged attacks deal {power}% bonus damage"
  base_power: 50.0
  trigger: on_charged_attack
  source_items: ["pure_nail"]
  native_equivalent: "Focused Strike"

MONSTER_SLAYER:
  id: "monster_slayer"
  name: "Silver Blade"
  description: "Deal {power}% bonus damage to non-human enemies"
  base_power: 15.0
  trigger: on_hit
  condition: "target.type != human"
  source_items: ["witcher_silver_sword"]
  native_equivalent: "Beastslayer's Mark"
```

#### Defensive Effects

```yaml
DEATH_PREVENTION:
  id: "death_prevention"
  name: "Link the Fire"
  description: "Survive fatal damage with 1 HP and explode for {power} fire damage (once per {cooldown}s)"
  base_power: 100.0  # explosion damage
  explosion_radius: 120
  cooldown: 60.0
  trigger: on_fatal_damage
  source_items: ["coiled_sword"]
  native_equivalent: "Phoenix Amulet"

MAX_HP_BONUS:
  id: "max_hp_bonus"
  name: "Erdtree's Favor"
  description: "Increase maximum HP by {power}%"
  base_power: 10.0
  trigger: passive
  source_items: ["elden_lord_crown"]
  native_equivalent: "Titan's Vitality"

MAGIC_SHIELD:
  id: "magic_shield"
  name: "Carian Phalanx"
  description: "Magic missiles orbit you, auto-targeting attackers ({count} missiles, {damage} each)"
  count: 3
  damage: 15
  recharge_time: 10.0  # seconds to regenerate one missile
  trigger: on_enemy_attack
  source_items: ["carian_crown"]
  native_equivalent: "Arcane Barrier"

OUT_OF_COMBAT_REGEN:
  id: "ooc_regen"
  name: "Farmer's Resilience"
  description: "Regenerate {power}% HP per second when out of combat"
  base_power: 2.0
  ooc_threshold: 5.0  # seconds without taking/dealing damage
  trigger: passive
  source_items: ["straw_hat"]
  native_equivalent: "Meditation"

PERFECT_DODGE_DAMAGE:
  id: "perfect_dodge_damage"
  name: "Embrace the Void"
  description: "After not taking damage for {window}s, next attack deals {power}% bonus damage"
  base_power: 50.0
  window: 4.0
  trigger: on_hit
  condition: "player.time_since_damage > window"
  source_items: ["void_heart"]
  native_equivalent: "Patient Hunter"

ENHANCED_DODGE:
  id: "enhanced_dodge"
  name: "Shadow Dash"
  description: "Dodge rolls grant {power} additional invincibility frames"
  base_power: 4  # extra i-frames
  trigger: on_dodge
  source_items: ["shade_cloak"]
  native_equivalent: "Assassin's Reflexes"
```

#### Utility Effects

```yaml
MOVEMENT_SPEED:
  id: "movement_speed"
  name: "Boost"
  description: "Increase movement speed by {power}%"
  base_power: 5.0
  trigger: passive
  source_items: ["discord_nitro_badge"]
  native_equivalent: "Swift Boots"

RESPAWN_SPEED:
  id: "respawn_speed"
  name: "Preserved Code"
  description: "Respawn {power}% faster after death"
  base_power: 25.0
  trigger: on_death
  source_items: ["arctic_code_badge"]
  native_equivalent: "Soul Anchor"

DROP_RATE:
  id: "drop_rate"
  name: "OG Status"
  description: "Increase item drop rates by {power}%"
  base_power: 5.0
  trigger: passive
  source_items: ["early_supporter_badge"]
  native_equivalent: "Lucky Charm"

STAGGER:
  id: "stagger"
  name: "Bind"
  description: "Heavy attacks stagger enemies for {power}s"
  base_power: 0.5
  trigger: on_heavy_attack
  source_items: ["margits_shackle"]
  native_equivalent: "Stunning Blow"

DANGER_SENSE:
  id: "danger_sense"
  name: "Witcher Senses"
  description: "Highlight enemies through walls within {range} units"
  range: 300
  trigger: passive
  source_items: ["witcher_silver_sword"]  # secondary effect
  native_equivalent: "Hunter's Vision"
```

---

## Part 2: Active Abilities (Ability Bar)

### 2.1 Ability Bar Design

```
ABILITY BAR (Future Implementation)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[ Q ]    [ E ]    [ R ]    [ F ]    [ 1 ]    [ 2 ]
 ███      ███      ███      ███      ███      ███
Class    Class    Forged   Forged   Item     Item
Skill 1  Skill 2  Active   Active   Consumable Consumable

SLOTS:
├── 2 Class Skills (from character class)
├── 2 Active Ability Slots (from gear/forged items)
└── 2 Consumable Slots (potions, bombs, etc.)
```

### 2.2 Active Ability Sources

```
ACTIVE ABILITY SOURCES:
━━━━━━━━━━━━━━━━━━━━━━━
1. Class Skills (fixed by class choice)
   - Warrior: Charge, War Cry
   - Rogue: Backstab, Smoke Bomb
   - Mage: Fireball, Teleport

2. Forged Legendaries (from prestigious achievements)
   - Only LEGENDARY tier items can grant actives
   - These are the ultra-rare abilities

3. Native Dreadland Drops
   - Boss weapons with actives
   - Quest reward items
   - Crafted ultimate gear
```

### 2.3 Forged Active Abilities

Only **Legendary** items (effort_score 80+) can grant active abilities. These are the crown jewels.

```yaml
# ═══════════════════════════════════════════════════════════════
# LEGENDARY WEAPON ACTIVES
# ═══════════════════════════════════════════════════════════════

WATERFOWL_DANCE:
  id: "waterfowl_dance"
  name: "Waterfowl Dance"
  description: "Launch into the air and perform a devastating flurry of slashes"
  source_item: "hand_of_malenia"
  source_achievement: "SHARDBEARER_MALENIA"
  type: "offensive"
  cooldown: 30.0
  duration: 2.0
  damage_per_hit: 15
  hit_count: 12
  grants_invulnerability: true
  animation: "waterfowl_dance"
  native_equivalent: "Bladestorm (Warrior Ultimate)"

MORTAL_DRAW:
  id: "mortal_draw"
  name: "Mortal Draw"
  description: "Sheathe and draw the blade for a devastating strike"
  source_item: "mortal_blade"
  source_achievement: "IMMORTAL_SEVERANCE"
  type: "offensive"
  cooldown: 20.0
  charge_time: 0.8
  damage_multiplier: 3.0
  armor_pierce: 100  # ignores armor
  animation: "iaijutsu_draw"
  native_equivalent: "Assassinate (Rogue Ultimate)"

COMET_AZUR:
  id: "comet_azur"
  name: "Comet Azur"
  description: "Channel a devastating beam of magic"
  source_item: "moonveil"  # if we add sorcery staff
  source_achievement: "LEGEND"
  type: "offensive"
  cooldown: 45.0
  channel_duration: 3.0
  damage_per_second: 50
  mana_cost: 100
  immobilizes_caster: true
  animation: "comet_azur"
  native_equivalent: "Arcane Torrent (Mage Ultimate)"

STARCALLER_CRY:
  id: "starcaller_cry_active"
  name: "Starcaller Cry"
  description: "Slam weapons into the ground, creating gravity wells"
  source_item: "radahns_greatswords"
  source_achievement: "SHARDBEARER_RADAHN"
  type: "utility"
  cooldown: 25.0
  pull_radius: 300
  stun_duration: 1.5
  animation: "gravity_slam"
  native_equivalent: "Earthquake (Warrior)"

DESCENDING_DARK:
  id: "descending_dark"
  name: "Descending Dark"
  description: "Concentrate void energy and slam down, dealing massive AoE"
  source_item: "void_heart"
  source_achievement: "EMBRACE_THE_VOID"
  type: "offensive"
  cooldown: 35.0
  requires: "airborne"  # must be jumping
  damage: 150
  aoe_radius: 180
  invuln_frames: 15
  animation: "void_slam"
  native_equivalent: "Meteor Strike (Mage)"

ONE_MIND:
  id: "one_mind"
  name: "One Mind"
  description: "Enter a focused state, unleashing a flurry of rapid slashes"
  source_item: "kusabimaru"  # if we add this
  source_achievement: "ALL_SKILLS"
  type: "offensive"
  cooldown: 40.0
  duration: 1.5
  hits: 20
  damage_per_hit: 8
  animation: "one_mind"
  native_equivalent: "Blade Fury (Rogue)"

# ═══════════════════════════════════════════════════════════════
# LEGENDARY ARMOR/ACCESSORY ACTIVES
# ═══════════════════════════════════════════════════════════════

ERDTREE_BLESSING:
  id: "erdtree_blessing"
  name: "Erdtree's Blessing"
  description: "Call upon the Erdtree to heal you and nearby allies"
  source_item: "elden_lord_crown"
  source_achievement: "ELDEN_LORD"
  type: "defensive"
  cooldown: 60.0
  heal_amount: 50  # % of max HP
  heal_radius: 200  # for allies
  buff_duration: 10.0
  animation: "erdtree_heal"
  native_equivalent: "Divine Intervention (Healer)"

SHADE_SOUL:
  id: "shade_soul"
  name: "Shade Soul"
  description: "Become incorporeal, passing through enemies and attacks"
  source_item: "shade_cloak"
  source_achievement: "VOID"
  type: "utility"
  cooldown: 25.0
  duration: 2.0
  grants_invulnerability: true
  pass_through_enemies: true
  speed_boost: 50  # %
  animation: "shadow_form"
  native_equivalent: "Phase Shift (Rogue)"

WRATH_OF_THE_GODS:
  id: "wrath_of_the_gods"
  name: "Wrath of the Gods"
  description: "Release a shockwave that damages and knockbacks all nearby enemies"
  source_item: "coiled_sword"  # alternative active
  source_achievement: "THE_DARK_SOUL"
  type: "defensive"
  cooldown: 35.0
  damage: 80
  knockback_force: 300
  aoe_radius: 200
  animation: "wrath_explosion"
  native_equivalent: "Repel (Paladin)"
```

### 2.4 Active Ability Slots Rules

```
ACTIVE ABILITY RULES:
━━━━━━━━━━━━━━━━━━━━

1. CLASS SKILLS ARE FIXED
   - Your class determines slots 1-2
   - Cannot be swapped for forged abilities

2. FORGED/NATIVE SLOTS (2 slots)
   - Can equip ANY active from gear
   - Forged legendaries compete with native ultimates
   - Choose based on build/playstyle

3. ONE ACTIVE PER ITEM
   - Items grant EITHER passive OR active
   - Cannot get both from same item
   - Player chooses which mode (for items that have both)

4. COOLDOWN SHARING
   - Similar abilities share cooldown category
   - Can't stack 2 invuln abilities
```

### 2.5 Passive vs Active Mode

Some legendary items can function in either mode:

```
HAND OF MALENIA
━━━━━━━━━━━━━━━
PASSIVE MODE: "I Have Never Known Defeat"
  → 3% lifesteal on all attacks
  → Always active, no input needed

ACTIVE MODE: "Waterfowl Dance"
  → Devastating attack combo
  → 30 second cooldown
  → Takes ability slot

Player chooses ONE mode in the Armory UI.
Cannot have both simultaneously.
```

---

## Part 3: Balance Framework

### 3.1 Power Budget

Each effect has a "power budget" to ensure balance:

```
POWER BUDGET TIERS:
━━━━━━━━━━━━━━━━━━
Legendary Effect: 100 power budget
Epic Effect: 75 power budget
Rare Effect: 50 power budget

COST EXAMPLES:
- 1% lifesteal = 15 budget
- 1% max HP = 10 budget
- 1% move speed = 8 budget
- 1% damage boost = 12 budget

So a Legendary effect could be:
- 6.5% lifesteal (100 budget)
- 10% max HP (100 budget)
- 8% damage + 3% move speed (96 + ~24 = adjusted)
```

### 3.2 Native Equivalence Guarantee

**RULE: Every forged effect MUST have a native equivalent of equal or greater power.**

```
EQUIVALENCE TABLE:
━━━━━━━━━━━━━━━━━
Forged Effect              Native Source              Power
─────────────────────────────────────────────────────────────
Lifesteal (Malenia)        Vampiric Enchant (Drop)    Equal
Death Prevent (Coiled)     Phoenix Amulet (Boss)      Equal
+10% HP (Elden Lord)       Titan's Belt (PvP)         Equal
Waterfowl Dance            Bladestorm (Warrior Ult)   Equal
```

**Native items are harder to get** (require Dreadland grinding) **but same power level**.

### 3.3 Stacking Restrictions

```
CANNOT STACK:
━━━━━━━━━━━━
- Multiple lifesteal effects (pick highest)
- Multiple death prevention (pick one)
- Multiple invulnerability actives (shared cooldown)
- Same effect from forged + native (pick one)

CAN STACK:
━━━━━━━━━━
- Different effect categories
- Damage boost + lifesteal
- Speed + HP
- Offensive + Defensive + Utility (the intended build)
```

---

## Part 4: Player Progression

### 4.1 New Player Experience

```
HOUR 0: Fresh Account
━━━━━━━━━━━━━━━━━━━━━
- No effects active
- Basic gear only
- Gets stomped by veterans
- Sees cool effects on enemies
- Thinks: "How do I get that?"

OPTION A: Link accounts
- Discovers they have Elden Ring achievements
- Forges Hand of Malenia → Instant lifesteal
- Now competitive in mid-game

OPTION B: Grind Dreadland
- Plays through content
- Earns Vampiric Enchant from boss
- Same lifesteal, earned in-game

OPTION C: Buy from market
- Doesn't have achievements, doesn't want to grind
- Finds Hand of Malenia on marketplace
- Pays 15,000 gold or 5,000 credits
- Gets the effect immediately
```

### 4.2 Mid-Game Player

```
HOUR 50: Established Player
━━━━━━━━━━━━━━━━━━━━━━━━━━━
- Has 1-2 good effects
- Mix of forged and native
- Building toward a "build"
- Starting to stomp noobs themselves
- Eyeing legendary forged items

Goals:
- Get third effect slot filled
- Unlock an active ability
- Optimize effect synergies
```

### 4.3 End-Game Player

```
HOUR 200+: Veteran
━━━━━━━━━━━━━━━━━━━
- All 3 passive slots filled with optimal effects
- Active abilities unlocked
- Mix of best forged + best native
- Theory-crafting builds
- Helping noobs understand the system

Loadout Example:
PASSIVE 1: Lifesteal (Forged - Malenia)
PASSIVE 2: +10% HP (Native - Titan's Belt)
PASSIVE 3: Bonus damage on dodge (Forged - Wolf Blood)
ACTIVE: Waterfowl Dance (Forged - Malenia)
```

### 4.4 Effect-Driven Trading

Effects are what make forged items valuable in the economy. Visual appeal alone doesn't justify prices - combat utility does.

```
EFFECT VALUE DRIVERS:
━━━━━━━━━━━━━━━━━━━━
Tier 1 (Most Valuable):
├── Lifesteal - Universal utility, always relevant
├── Death Prevention - Safety net for any build
├── Waterfowl Dance - Best offensive active
└── Items with BOTH strong passive AND active

Tier 2 (High Value):
├── Damage amplifiers (execute, combo, etc.)
├── Defensive actives (invuln, heals)
└── Unique utility (gravity pull, lightning chain)

Tier 3 (Moderate Value):
├── Situational effects (monster slayer, dodge bonus)
├── Quality-of-life (move speed, respawn)
└── Items with niche but powerful effects

Tier 4 (Budget):
├── Common utility effects
├── Non-legendary items
└── Effects with easy native alternatives
```

```
EFFECT PRICING DYNAMICS:
━━━━━━━━━━━━━━━━━━━━━━━
Market prices naturally form around effect utility:

Hand of Malenia (lifesteal + Waterfowl Dance):
→ Premium price: Best-in-slot for many builds
→ High demand, limited supply (4.2% achievement)
→ Expected: 30,000-50,000 gold or 10,000-15,000 credits

Void Heart (void damage bonus + Descending Dark):
→ High price: Excellent effect combo
→ Ultra-rare supply (0.3% achievement)
→ Expected: 100,000+ gold or 25,000+ credits

Discord Nitro Badge (5% move speed):
→ Budget price: Nice-to-have, not essential
→ Common supply (many subscribers)
→ Expected: 500-2,000 gold

Meta shifts affect prices:
├── If dodge builds become meta → Wolf Blood prices rise
├── If boss content releases → Boss damage effects rise
└── If PvP season starts → PvP-relevant effects spike
```

```
TRADING CONSIDERATIONS FOR EFFECTS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
When buying:
- Does this effect fill a slot I need?
- Is the power level appropriate for the price?
- Can I get a native equivalent easier?

When selling:
- Is this effect currently in-demand?
- What's the competition on marketplace?
- Should I wait for a meta shift?

The economy self-balances:
- Rare effects command premium
- Common effects trend toward budget
- Native alternatives cap maximum prices
```

See `FORGE_ECONOMY_DESIGN.md` for full trading system details.

---

## Part 5: UI/UX Specifications

### 5.1 Armory Effect Management

```
┌─────────────────────────────────────────────────────────────┐
│  EQUIPPED EFFECTS                                    [3/3]  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                     │
│  │ SLOT 1  │  │ SLOT 2  │  │ SLOT 3  │                     │
│  │ ▓▓▓▓▓▓▓ │  │ ▓▓▓▓▓▓▓ │  │ ░░░░░░░ │                     │
│  │Lifesteal│  │Link Fire│  │ [Empty] │                     │
│  │  3.0%   │  │60s Cool │  │         │                     │
│  └─────────┘  └─────────┘  └─────────┘                     │
├─────────────────────────────────────────────────────────────┤
│  AVAILABLE EFFECTS (drag to slot)                          │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                     │
│  │Void     │  │Terra    │  │Wolf     │                     │
│  │+50% dmg │  │Projectile│  │Blood   │                     │
│  └─────────┘  └─────────┘  └─────────┘                     │
├─────────────────────────────────────────────────────────────┤
│  ACTIVE ABILITIES                                   [1/2]  │
│  ┌───────────────┐  ┌───────────────┐                      │
│  │ [ R ] Waterfowl│  │ [ F ] Empty   │                      │
│  │ Dance  30s CD  │  │               │                      │
│  └───────────────┘  └───────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Effect Tooltips

```
┌─────────────────────────────────────────┐
│ ★★★ LEGENDARY                          │
│ "I Have Never Known Defeat"             │
│─────────────────────────────────────────│
│ Heal for 3.0% of damage dealt          │
│                                         │
│ Source: Hand of Malenia                 │
│ Achievement: Shardbearer Malenia        │
│ From: Elden Ring (2.1% players)         │
│─────────────────────────────────────────│
│ Native Equivalent:                      │
│ "Vampiric Enchantment" - Zone 5 Boss    │
└─────────────────────────────────────────┘
```

### 5.3 Combat HUD

```
┌─────────────────────────────────────────────────────────────┐
│  HP ████████████████░░░░  85/100                           │
│                                                             │
│  EFFECTS ACTIVE:                                            │
│  [♥] Lifesteal  [🔥] Link Fire  [◆] Void Damage            │
│                                                             │
│  ABILITIES:                                                 │
│  [Q] Charge     [E] War Cry    [R] Waterfowl   [F] ────    │
│      READY          4.2s           READY         EMPTY      │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 6: Technical Implementation

### 6.1 Database Schema Updates

```python
# ForgedAchievement model additions
class ForgedAchievement(Base):
    # ... existing fields ...

    # Effect system
    passive_effect_id: Optional[str]      # "lifesteal", "death_prevention", etc.
    passive_effect_power: Optional[float] # 0.5-1.0 based on effort
    active_ability_id: Optional[str]      # "waterfowl_dance", etc.
    effect_mode: str                      # "passive" or "active" (player choice)

# New table for effect slot assignments
class PlayerEffectSlots(Base):
    __tablename__ = "player_effect_slots"

    id: int
    user_id: int
    slot_number: int  # 1, 2, or 3
    source_type: str  # "forged" or "native"
    source_item_id: str
    effect_id: str

# New table for ability bar assignments
class PlayerAbilityBar(Base):
    __tablename__ = "player_ability_bar"

    id: int
    user_id: int
    slot_key: str  # "R", "F", etc.
    source_type: str
    source_item_id: str
    ability_id: str
```

### 6.2 items.json Effect Schema

```json
{
  "item_id": "hand_of_malenia",
  "item_name": "Hand of Malenia",
  // ... existing fields ...

  "effects": {
    "passive": {
      "effect_id": "lifesteal",
      "name": "I Have Never Known Defeat",
      "description": "Heal for {power}% of damage dealt",
      "base_power": 3.0,
      "power_scaling": "effort_percentage"
    },
    "active": {
      "ability_id": "waterfowl_dance",
      "name": "Waterfowl Dance",
      "description": "Launch into the air and perform a devastating flurry of slashes",
      "cooldown": 30.0,
      "unlocked_at_rarity": "legendary"
    }
  },
  "native_equivalent": {
    "passive": "Vampiric Enchantment (Zone 5 Boss)",
    "active": "Bladestorm (Warrior Ultimate)"
  }
}
```

### 6.3 Godot Implementation

```gdscript
# EffectManager.gd
extends Node

signal effect_triggered(effect_id, data)

var active_passive_effects: Array[PassiveEffect] = []
var active_abilities: Dictionary = {}  # slot -> Ability

const MAX_PASSIVE_SLOTS = 3
const MAX_ABILITY_SLOTS = 2  # forged/native slots

func _process(delta):
    for effect in active_passive_effects:
        if effect.trigger == "passive":
            effect.apply_continuous(delta)

func on_player_hit(attacker, defender, damage) -> Dictionary:
    var modifications = {"damage": damage, "heal": 0}

    for effect in active_passive_effects:
        if effect.trigger == "on_hit":
            modifications = effect.apply_on_hit(attacker, defender, modifications)

    return modifications

func on_player_take_damage(player, damage, source) -> Dictionary:
    var modifications = {"damage": damage, "prevented": false}

    for effect in active_passive_effects:
        if effect.trigger == "on_take_damage":
            modifications = effect.apply_on_take_damage(player, modifications)
        if effect.trigger == "on_fatal_damage" and would_be_fatal(player, modifications.damage):
            modifications = effect.apply_on_fatal_damage(player, modifications)

    return modifications

func use_ability(slot: String):
    if slot in active_abilities:
        var ability = active_abilities[slot]
        if ability.is_ready():
            ability.execute()
```

---

## Part 7: Effect Balance Spreadsheet

```
PASSIVE EFFECTS BALANCE TABLE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Effect ID          | Base Power | Category  | Budget | Source Item
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
lifesteal          | 3.0%       | Offensive | 100    | hand_of_malenia
execute_damage     | 25.0%      | Offensive | 100    | mortal_blade
projectile_attack  | 30.0%      | Offensive | 90     | terra_blade
chain_lightning    | 20 dmg x3  | Offensive | 85     | dragonslayer
combo_damage       | 30.0%      | Offensive | 80     | stygian_blade
dash_damage        | 20.0%      | Offensive | 70     | farron_greatsword
charged_damage     | 50.0%      | Offensive | 75     | pure_nail
monster_slayer     | 15.0%      | Offensive | 60     | witcher_silver
death_prevention   | 1HP + 100  | Defensive | 100    | coiled_sword
max_hp_bonus       | 10.0%      | Defensive | 100    | elden_lord_crown
magic_shield       | 3x15 dmg   | Defensive | 85     | carian_crown
ooc_regen          | 2.0%/s     | Defensive | 70     | straw_hat
perfect_dodge_dmg  | 50.0%      | Defensive | 90     | void_heart
enhanced_dodge     | +4 iframe  | Defensive | 80     | shade_cloak
movement_speed     | 5.0%       | Utility   | 40     | discord_nitro
respawn_speed      | 25.0%      | Utility   | 30     | arctic_code
drop_rate          | 5.0%       | Utility   | 35     | early_supporter
stagger            | 0.5s       | Utility   | 50     | margits_shackle
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ACTIVE ABILITIES BALANCE TABLE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Ability ID         | Cooldown | Type      | Damage   | Source Item
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
waterfowl_dance    | 30s      | Offensive | 12x15    | hand_of_malenia
mortal_draw        | 20s      | Offensive | 3x base  | mortal_blade
starcaller_cry     | 25s      | Utility   | Pull+Stun| radahns_greatswords
descending_dark    | 35s      | Offensive | 150 AoE  | void_heart
erdtree_blessing   | 60s      | Defensive | 50% heal | elden_lord_crown
shade_soul         | 25s      | Utility   | Invuln   | shade_cloak
wrath_of_gods      | 35s      | Defensive | 80 + KB  | coiled_sword
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Appendix A: Native Dreadland Equivalents

Every forged effect must have a native equivalent. This table is the authoritative reference:

```
NATIVE EQUIVALENTS - PASSIVE EFFECTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Forged Effect            | Native Name              | Source
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
lifesteal                | Vampiric Enchantment     | Zone 5 Boss
death_prevention         | Phoenix Blessing         | Phoenix Amulet (Quest)
boss_damage              | Slayer's Mark            | Hunter's Guild reward
crit_chance              | Precision Gem            | Craftable (Jeweler)
damage_reduction         | Iron Will                | Zone 3 Boss
lightning_proc           | Lightning Enchantment    | Storm Temple chest
fire_aura                | Flame Enchantment        | Forge Master craft
regen                    | Regeneration             | Healer's Blessing
gravity_pull             | Magnetic Force           | Graviton Hammer (Zone 6)
magic_damage             | Arcane Infusion          | Wizard Tower reward
poise                    | Steadfast                | Heavy armor set bonus
void_damage              | Desperate Power          | Abyss Gauntlet (Boss)
soul_gather              | Mana Leech               | Warlock starting skill
execute_bonus            | Executioner              | Assassin Guild reward
on_kill_buff             | Frenzy                   | Berserker passive
armor_pierce             | Armor Break              | Penetrating weapons
move_speed               | Swiftfoot                | Light armor set bonus
monster_slayer           | Beast Slayer             | Hunter's Guild badge
stamina_regen            | Vigor                    | Endurance training
party_buff               | Battle Standard          | Rally Banner (Zone 4)
projectile_on_hit        | Ethereal Blade           | Spectral Sword (Boss)
dot_on_hit               | Poison                   | Venomous weapons
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NATIVE EQUIVALENTS - ACTIVE ABILITIES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Forged Ability           | Native Name              | Source
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
waterfowl_dance          | Blade Storm              | Warrior Ultimate
mortal_draw              | Executioner's Strike     | Assassin Ultimate
starcaller_cry           | Vortex                   | Graviton Staff active
lightning_bolt           | Thunder Strike           | Storm Mage skill
terra_beam               | Energy Wave              | Spellblade finisher
shadow_phase             | Ethereal Form            | Shadow Walker skill
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Native Item Creation Guidelines

When creating new native items to match forged effects:

1. **Same power level** - Native should be equal or 5-10% stronger (to reward pure grinding)
2. **Higher acquisition difficulty** - Require significant Dreadland progression
3. **Appropriate zone placement** - Higher-power effects in later zones
4. **Thematic consistency** - Native items should fit Dreadland's aesthetic, not mimic source games

---

## Related Documents

- `FORGE_ITEM_PHILOSOPHY.md` - Core design principles and twinking system
- `FORGE_ECONOMY_DESIGN.md` - Trading, monetization, market dynamics
- `FORGE_PROVENANCE_SYSTEM.md` - Blockchain backing and history tracking
- `ACHIEVEMENT_ITEM_CREATION_PROCESS.md` - Adding new items with effects

---

## Version History

- v1.0 (2024-12) - Initial effects system design
- v1.1 (2024-12) - Added Appendix A: Native Dreadland Equivalents consolidated reference
- v1.2 (2024-12) - Added Section 4.4: Effect-Driven Trading, marketplace path in new player experience, economy document cross-references
