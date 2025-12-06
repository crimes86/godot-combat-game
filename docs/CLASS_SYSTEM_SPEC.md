# Class System Specification

## Overview

The Class System is an emergent progression system where players develop their identity through gameplay rather than upfront selection. It consists of four interconnected systems:

1. **Weapon Skills** - EQ/Classic WoW-style weapon proficiency that must be leveled through use
2. **Runes** - World-dropped items that grant abilities and passive bonuses
3. **Discipline Affinity** - Tracks HOW you play (aggressive, tactical, supportive) and unlocks playstyle abilities
4. **Emergent Classes & Titles** - Identity that forms from your weapon mastery + discipline + runes

All players start as **"Adventurer"** and their class emerges organically from how they play.

### The Four Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 4: EMERGENT CLASS                                        │
│  Determined by: Weapon Skill + Discipline + Runes               │
│  Result: "Blademaster", "Assassin", "High Priest", etc.         │
└─────────────────────────────────────────────────────────────────┘
                              ▲
          ┌───────────────────┼───────────────────┐
          │                   │                   │
┌─────────┴─────────┐ ┌───────┴───────┐ ┌────────┴────────┐
│  WEAPON SKILLS    │ │  DISCIPLINE   │ │     RUNES       │
│  What you use     │ │  How you play │ │  What you find  │
│  Swords: 247/300  │ │  Warfare: 2.8k│ │  Blood Price    │
│  Daggers: 89/300  │ │  Finesse: 1.2k│ │  Last Stand     │
└───────────────────┘ └───────────────┘ └─────────────────┘
```

---

## System 1: Weapon Skills

### Core Concept

Each weapon TYPE has an independent skill level that determines your effectiveness with that weapon. You cannot simply equip a new weapon and perform at full capacity - you must invest time training with it.

**Critical Design Rule:** Weapon skill is **capped by player level**. A level 5 player with maxed sword skill is just as effective *for their level* as a level 30 with maxed sword skill. Low-level players are never penalized for being low level—only for being undertrained relative to their current cap.

### Level-Based Skill Cap

```
Weapon Skill Cap = Player Level × 10

Level 1  → Cap: 10
Level 5  → Cap: 50
Level 10 → Cap: 100
Level 15 → Cap: 150
Level 20 → Cap: 200
Level 25 → Cap: 250
Level 30 → Cap: 300 (maximum)
```

This means:
- You must be **level 30** to achieve Grandmaster (300 skill)
- Weapon skill progression is tied to character progression
- High-level players who swap weapons must grind to catch up

### Weapon Skill Types

| Skill | Associated Weapons | Primary Stat Synergy |
|-------|-------------------|---------------------|
| Swords | Longsword, Short Sword, Rapier | Strength/Agility |
| Daggers | Rusty Dagger, Stiletto, Kris | Agility |
| Maces | Morning Star, Bone Mace, Flanged Mace | Strength |
| Hammers | Warhammer, Maul, Sledge | Strength |
| Spears | Bronze Spear, Pike, Halberd | Strength/Agility |
| Staves | Healing Staff, Battle Staff, Wizard Staff | Vitality (for healing) |
| Axes | (Future) Battle Axe, Greataxe | Strength |
| Bows | (Future) Shortbow, Longbow, Crossbow | Agility |
| Shields | (Future) Buckler, Kite Shield, Tower Shield | Vitality |

### Skill Level Effects (Relative to Cap)

**Effectiveness is based on how full your skill bar is, NOT absolute numbers.**

This means a level 5 player with 50/50 swords (100% filled) performs identically to a level 30 with 300/300 swords (100% filled) - both have 0% miss chance and 100% damage for their level.

```
Fill Percentage    Miss Chance    Damage Modifier    Status
---------------    -----------    ---------------    ------
0-15%              25% miss       50% damage         "Untrained"
16-33%             20% miss       60% damage         "Novice"
34-50%             15% miss       70% damage         "Competent"
51-66%             10% miss       80% damage         "Skilled"
67-83%             5% miss        90% damage         "Expert"
84-99%             2% miss        95% damage         "Nearly Maxed"
100%               0% miss        100% damage        "Maxed"
```

### Example: Same Skill %, Different Levels

```
LEVEL 5 PLAYER (Cap: 50)
Sword Skill: 50/50 (100%)
→ Miss: 0%, Damage: 100%
→ Status: "Maxed for level"

LEVEL 30 PLAYER (Cap: 300)
Sword Skill: 300/300 (100%)
→ Miss: 0%, Damage: 100%
→ Status: "Grandmaster"

Both are equally effective relative to their level!
```

### Example: Weapon Swap Penalty (High Level)

```
LEVEL 30 PLAYER - MAIN WEAPON
Sword Skill: 300/300 (100%)
→ Miss: 0%, Damage: 100%

LEVEL 30 PLAYER - JUST PICKED UP DAGGERS
Dagger Skill: 30/300 (10%)
→ Miss: 25%, Damage: 50%
→ Needs to grind ~100 kills to catch up
```

### Skill Gain Formula

Skill points are gained through weapon use, with a **catch-up mechanic** that makes it faster to fill an empty bar:

```gdscript
# Base gain per action
SKILL_GAIN_HIT = 0.5          # Landing a hit
SKILL_GAIN_MISS = 0.1         # Missing (still learning)
SKILL_GAIN_KILL = 3.0         # Killing blow
SKILL_GAIN_CRIT = 1.0         # Critical hit bonus

# Catch-up mechanic: faster gains when far from cap
func add_skill(weapon_type: String, base_amount: float) -> void:
    var current = weapon_skills[weapon_type]
    var cap = CharacterStats.level * 10

    # Can't exceed cap
    if current >= cap:
        return

    # Faster gains when behind, slower when nearly capped
    var fill_ratio = current / float(cap)
    var catch_up_bonus = lerp(2.0, 0.5, fill_ratio)  # 2x at empty, 0.5x at full

    var gain = base_amount * catch_up_bonus
    weapon_skills[weapon_type] = min(current + gain, cap)
```

### Catch-Up Mechanic In Action

A level 20 player (cap: 200) picks up a new weapon:

```
Kill #1:   Skill 0→6    (fast catch-up, 2x bonus)
Kill #10:  Skill 42→47  (still catching up)
Kill #30:  Skill 120→123 (slowing down)
Kill #60:  Skill 185→186 (grinding now)
Kill #100: Skill 200/200 (capped for level)
```

**~100 kills to cap a new weapon at your current level.** That's 1-2 hours of focused grinding—enough to feel like investment, not enough to be punishing.

### When You Level Up

When you level up, your cap increases but skill doesn't auto-fill:

```
BEFORE LEVEL UP:
Level 10, Swords 100/100 (100% - maxed)

AFTER LEVEL UP:
Level 11, Swords 100/110 (91% - small gap opens)
```

This creates natural "maintenance" - a few kills after leveling catches you back up. You're never dramatically punished, just given a small goal.

### Skill Milestones & Unlocks

Since skill is level-gated, milestones require **both the level AND the skill**:

| Milestone | Requirement | Unlock |
|-----------|-------------|--------|
| Initiate | Level 5 + Skill 50 | Weapon proficiency established |
| Passive | Level 10 + Skill 100 | Weapon-specific passive unlocks |
| Rare Access | Level 15 + Skill 150 | Can equip Rare+ weapons of this type |
| Ability | Level 20 + Skill 200 | Weapon-specific ability unlocks |
| Legendary Access | Level 25 + Skill 250 | Can equip Legendary weapons of this type |
| Grandmaster | Level 30 + Skill 300 | Grandmaster passive, prestige title |

**Note:** A level 30 player who just picked up daggers would need ~100 kills to unlock dagger abilities (catching up from 0 to 200).

### Weapon-Specific Passives (Skill 100)

| Weapon Skill | Passive Name | Effect |
|--------------|--------------|--------|
| Swords | Blade Precision | +3% crit chance with swords |
| Daggers | Arterial Cuts | Crits cause bleed (2% HP/sec, 3s) |
| Maces | Crushing Blows | 10% chance to stagger (slow enemy) |
| Hammers | Armor Break | Attacks reduce target defense by 5% (stacks 3x) |
| Spears | Reach | +15% attack range |
| Staves | Focused Channeling | +20% healing power |

### Weapon-Specific Abilities (Skill 200)

| Weapon Skill | Ability Name | Effect | Cooldown |
|--------------|--------------|--------|----------|
| Swords | Blade Flurry | 3 rapid attacks at 50% damage each | 20s |
| Daggers | Eviscerate | 200% damage from behind, 100% otherwise | 15s |
| Maces | Concussive Slam | AOE stun (1.5s) around target | 30s |
| Hammers | Execution | 300% damage to enemies below 20% HP | 25s |
| Spears | Impale | Pierce through to hit 2nd enemy | 12s |
| Staves | Sanctuary | Place heal zone (heals 10 HP/sec, 8s duration) | 45s |

### Skill Display (UI Element)

The UI shows skill relative to your current level cap:

```
┌─────────────────────────────────────────────┐
│  WEAPON SKILLS                  Level: 15   │
│                                  Cap: 150   │
│                                             │
│  ⚔ Swords     ████████████████  150/150 ✓  │
│    [Maxed] Blade Precision ✓                │
│                                             │
│  🗡 Daggers    ████████░░░░░░░░   89/150    │
│    [59%] Arterial Cuts ✗ (need 100)         │
│                                             │
│  🔨 Maces      ██████░░░░░░░░░░   67/150    │
│    [45%] Crushing Blows ✗ (need 100)        │
│                                             │
│  ⚒ Hammers    ██░░░░░░░░░░░░░░   23/150    │
│    [15%] Undertrained                       │
│                                             │
│  🔱 Spears     ██████████░░░░░░   94/150    │
│    [63%]                                    │
│                                             │
│  🪄 Staves     █████░░░░░░░░░░░   45/150    │
│    [30%]                                    │
└─────────────────────────────────────────────┘
```

**Level 30 version (max cap):**

```
┌─────────────────────────────────────────────┐
│  WEAPON SKILLS                  Level: 30   │
│                                  Cap: 300   │
│                                             │
│  ⚔ Swords     ████████████████  300/300 ★  │
│    [GRANDMASTER] All unlocks ✓              │
│                                             │
│  🗡 Daggers    ████████████████  300/300 ★  │
│    [GRANDMASTER] All unlocks ✓              │
│                                             │
│  🔨 Maces      ██░░░░░░░░░░░░░░   45/300    │
│    [15%] Undertrained - 55 kills to passive │
└─────────────────────────────────────────────┘
```

---

## System 2: Runes

### Core Concept

Runes are rare world drops that grant abilities, passive bonuses, or special effects. They are slotted into Rune Slots (limited resource) and can be swapped in town. Runes provide build customization independent of weapon choice.

### Rune Slots

Players unlock rune slots as they progress:

| Slot | Unlock Requirement |
|------|--------------------|
| Slot 1 | Level 5 (tutorial completion) |
| Slot 2 | Level 15 |
| Slot 3 | Level 25 |
| Slot 4 | Any weapon skill reaches 200 |
| Slot 5 | Any weapon skill reaches 300 |
| Slot 6 | Two weapon skills reach 300 |

### Rune Categories

**Ability Runes** - Grant active abilities with cooldowns
```
[Rune of Sanguine Fury]
Type: Ability
Ability: Blood Price
Effect: Sacrifice 15% current HP to gain +30% damage for 10 seconds
Cooldown: 60 seconds
Drop Source: Crimson Hollow rare spawns
Drop Rate: 0.5%
```

**Passive Runes** - Grant permanent stat bonuses while slotted
```
[Rune of the Relentless]
Type: Passive
Effect: Chain multiplier decay rate reduced by 50%
Drop Source: Elite wolves (any zone)
Drop Rate: 1%
```

**Trait Runes** - Grant conditional bonuses
```
[Rune of Last Stand]
Type: Trait
Effect: +25% damage when below 30% HP
Drop Source: World bosses
Drop Rate: 2%
```

**Title Runes** - Grant cosmetic titles (plus minor bonus)
```
[Wolfbane Rune]
Type: Title
Requirement: Kill 500 wolves while slotted to activate
Effect: +5% damage vs wolves, grants title "Wolfbane"
Drop Source: Alpha Wolf (rare spawn)
Drop Rate: 0.3%
```

### Rune Rarity

| Rarity | Drop Rate Modifier | Slot Restriction | Trade |
|--------|-------------------|------------------|-------|
| Common | 1.0x | None | Yes |
| Uncommon | 0.5x | None | Yes |
| Rare | 0.2x | None | Yes |
| Epic | 0.05x | Level 20+ | Yes |
| Legendary | 0.01x | Level 25+ | No |
| Artifact | Boss drop only | Skill 250+ | No |

### Example Rune List

**Ability Runes:**
| Rune | Ability | Effect | Source |
|------|---------|--------|--------|
| Rune of Sanguine Fury | Blood Price | -15% HP, +30% damage (10s) | Crimson Hollow |
| Rune of the Tempest | Whirlwind | Spin attack hitting all nearby (150% dmg) | Storm Giants |
| Rune of Shadows | Vanish | Become invisible (3s), next attack +50% | Shadow Caves |
| Rune of Divine Light | Holy Nova | AOE heal (30 HP to all allies in range) | Temple of Dawn |
| Rune of Earthen Might | Stoneskin | +50% defense for 8 seconds | Mountain Golems |
| Rune of the Phoenix | Rebirth | Revive with 25% HP once per 10 min | Phoenix (rare) |

**Passive Runes:**
| Rune | Effect | Source |
|------|--------|--------|
| Rune of the Relentless | Chain decay -50% | Elite wolves |
| Rune of Fortitude | +50 max HP | Stone golems |
| Rune of Swiftness | +10% movement speed | Harpies |
| Rune of the Leech | 3% lifesteal on hit | Vampiric enemies |
| Rune of Precision | +5% crit chance | Archer enemies |
| Rune of Wisdom | +15% XP gain | Library zone |

**Trait Runes:**
| Rune | Condition | Bonus | Source |
|------|-----------|-------|--------|
| Rune of Last Stand | Below 30% HP | +25% damage | World bosses |
| Rune of the Opener | First hit on enemy | +50% damage | Assassin mobs |
| Rune of Momentum | Chain x5+ | +10% attack speed | Berserker mobs |
| Rune of Vengeance | After taking hit | Next attack +20% | Knight enemies |
| Rune of the Giant Slayer | vs Elites/Bosses | +15% damage | Giant mobs |
| Rune of the Underdog | vs Higher level | +20% damage | Rare world drop |

**Title Runes:**
| Rune | Requirement | Title | Bonus | Source |
|------|-------------|-------|-------|--------|
| Wolfbane | Kill 500 wolves | "Wolfbane" | +5% vs wolves | Alpha Wolf |
| Dragonkin | Kill 100 drakes | "Dragonkin" | +5% fire resist | Dragon zone |
| The Undying | Die 0 times for 10 hours played | "The Undying" | +10 HP | Achievement |
| Dungeon Delver | Clear 50 dungeons | "Dungeon Delver" | +5% dungeon loot | Dungeon chests |

### Rune Swapping Rules

- Runes can only be swapped in **safe zones** (towns, camps)
- Swapping has a **30-second channel** (prevents combat swapping)
- No cost to swap (encourages experimentation)
- Runes are stored in a **Rune Pouch** (separate from inventory, 20 slots)

### Rune UI Element

```
┌─────────────────────────────────────────────┐
│  RUNES                          [Swap]      │
│                                             │
│  [1] ◆ Rune of Sanguine Fury    (Ability)   │
│      Blood Price: -15% HP, +30% dmg (10s)   │
│      Cooldown: Ready                        │
│                                             │
│  [2] ◆ Rune of the Relentless   (Passive)   │
│      Chain decay -50%                       │
│                                             │
│  [3] ◆ Rune of Last Stand       (Trait)     │
│      +25% damage below 30% HP               │
│                                             │
│  [4] ░░░ Empty Slot                         │
│                                             │
│  [5] 🔒 Locked (Weapon Skill 200)           │
│                                             │
│  [6] 🔒 Locked (2x Grandmaster)             │
└─────────────────────────────────────────────┘
```

---

## System 3: Discipline Affinity

### Core Concept

Discipline Affinity tracks **HOW you play**, not just what weapon you hold. It's a secondary progression system that runs alongside weapon skills, automatically tracking your combat behavior and rewarding your playstyle with abilities and bonuses.

Two players can both use swords, but if one plays aggressively (high damage, lots of kills) and another plays tactically (lots of crits, dodges), they'll develop different disciplines and emerge as different classes.

### The Disciplines

| Discipline | Playstyle | What It Tracks |
|------------|-----------|----------------|
| **Warfare** | Aggressive frontliner | Damage dealt, killing blows, time in combat |
| **Finesse** | Precision striker | Crits landed, dodge rolls, one-shot kills |
| **Brutality** | Berserker/momentum | Overkill damage, chain peaks, multi-kills |
| **Piety** | Support/healer | Healing done, ally revives, buff uptime |
| **Guardianship** | Tank/protector | Damage taken for allies, aggro held |

### Earning Affinity Points

Points are awarded **automatically** based on your actions:

| Action | Discipline | Points |
|--------|------------|--------|
| Kill an enemy | Warfare | +1 |
| Deal 100+ damage in one hit | Warfare | +0.5 |
| Land a critical hit | Finesse | +0.5 |
| Kill enemy at full HP (one-shot) | Finesse | +1 |
| Dodge an attack (i-frame hit) | Finesse | +2 |
| Reach chain multiplier x5+ | Brutality | +2 |
| Overkill by 50%+ damage | Brutality | +0.5 |
| Get a multi-kill (2+ in 2 sec) | Brutality | +3 |
| Heal an ally for 50+ HP | Piety | +1 |
| Revive a fallen ally | Piety | +10 |
| Apply a buff to ally | Piety | +2 |
| Take damage while ally nearby | Guardianship | +0.5 |
| Hold aggro on 3+ enemies | Guardianship | +1 |
| Block damage (future) | Guardianship | +1 per 25 blocked |

**Key insight:** You don't choose to level a discipline - your behavior automatically shapes it.

### Affinity Thresholds & Unlocks

| Affinity Points | Tier | Unlock |
|-----------------|------|--------|
| 500 | Initiate | Discipline recognized, minor title change |
| 1,000 | Adept | Discipline passive unlocks |
| 2,500 | Specialist | First discipline ability unlocks |
| 5,000 | Expert | Enhanced passive |
| 10,000 | Master | Second discipline ability, mastery title |

### Discipline Passives (1,000 points)

| Discipline | Passive Name | Effect |
|------------|--------------|--------|
| Warfare | Battle Hardened | +5% damage dealt |
| Finesse | Keen Eye | +5% crit chance |
| Brutality | Blood Frenzy | +2% damage per chain level |
| Piety | Blessed Touch | +15% healing effectiveness |
| Guardianship | Stalwart | +10% damage reduction |

### Discipline Abilities

**First Ability (2,500 points):**

| Discipline | Ability | Effect | Cooldown |
|------------|---------|--------|----------|
| Warfare | Battle Cry | +20% damage for 10s, allies get +10% | 45s |
| Finesse | Riposte | After dodging, next attack guaranteed crit | 20s |
| Brutality | Execute | +50% damage to enemies below 25% HP | 15s |
| Piety | Sanctuary | Place heal zone (15 HP/sec, 6s) | 40s |
| Guardianship | Taunt | Force nearby enemies to target you (5s) | 30s |

**Second Ability (10,000 points - Mastery):**

| Discipline | Ability | Effect | Cooldown |
|------------|---------|--------|----------|
| Warfare | Unstoppable | Immune to CC, +30% damage (6s) | 90s |
| Finesse | Death Mark | Target takes +30% damage from all sources (8s) | 60s |
| Brutality | Rampage | Kills extend all active buffs by 3s | 45s |
| Piety | Divine Shield | Absorb shield on ally (blocks 100 damage) | 50s |
| Guardianship | Last Stand | Survive fatal hit at 1 HP (once per 5 min) | 300s |

### Affinity Display (UI Element)

```
┌─────────────────────────────────────────────┐
│  DISCIPLINES                                │
│                                             │
│  ⚔ Warfare     ████████████░░░░  2,847/5,000│
│    [Specialist] Battle Cry ✓                │
│    Passive: +5% damage                      │
│                                             │
│  🎯 Finesse    ██████░░░░░░░░░░  1,203/2,500│
│    [Adept] Riposte ✗ (1,297 to unlock)      │
│    Passive: +5% crit                        │
│                                             │
│  💀 Brutality  ███░░░░░░░░░░░░░    634/1,000│
│    [Initiate]                               │
│                                             │
│  ✚ Piety      █░░░░░░░░░░░░░░░     89/500  │
│    Not yet recognized                       │
│                                             │
│  🛡 Guardian   ░░░░░░░░░░░░░░░░     23/500  │
│    Not yet recognized                       │
└─────────────────────────────────────────────┘
```

### How Disciplines Affect Class

Your **Primary Discipline** (highest affinity) modifies your class identity:

```
SAME WEAPON, DIFFERENT DISCIPLINES:

Player A: Swords (300) + Warfare Primary
→ Class: BLADEMASTER (aggressive sword fighter)
→ Passive: +5% sword damage + 5% all damage

Player B: Swords (300) + Finesse Primary
→ Class: DUELIST (precision sword fighter)
→ Passive: +5% sword damage + 5% crit chance

Player C: Swords (300) + Piety Primary
→ Class: TEMPLAR (supportive sword fighter)
→ Passive: +5% sword damage + 15% healing
```

---

## System 4: Emergent Classes & Titles

### Core Concept

Your "class" is not chosen - it emerges from the combination of your highest weapon skill, discipline affinity, and rune loadout. The system reads your progression and assigns an appropriate class identity and title.

### Class Determination Formula

```gdscript
func determine_class() -> Dictionary:
    var primary_weapon = WeaponSkillManager.get_highest_weapon_type()  # e.g., "swords"
    var primary_discipline = DisciplineManager.get_highest_discipline() # e.g., "warfare"

    # Class emerges from weapon + discipline combination
    var class_id = CLASS_MATRIX[primary_weapon][primary_discipline]
    var title = get_title_for_progression(primary_weapon, primary_discipline)

    return {"class": class_id, "title": title}
```

### Class Matrix (Weapon × Discipline)

| Primary Weapon | Warfare | Finesse | Brutality | Piety | Guardianship |
|----------------|---------|---------|-----------|-------|--------------|
| Swords | Blademaster | Duelist | Berserker | Templar | Sword Knight |
| Daggers | Assassin | Rogue | Cutthroat | Nightblade | Shadow Guard |
| Maces | Crusher | Brawler | Ravager | Priest | Cleric |
| Hammers | Warlord | Executioner | Berserker | Justicar | Paladin |
| Spears | Dragoon | Lancer | Impaler | Valkyrie | Hoplite |
| Staves | Battle Mage | Sage | Warlock | High Priest | Arcane Ward |

**30 unique classes** emerge from the 6 weapons × 5 disciplines matrix.

### Title Progression

Titles evolve based on your highest weapon skill level:

```
Skill 1-49:     "Adventurer [Name]"
Skill 50-99:    "[Weapon] Initiate [Name]"     → "Sword Initiate Kevin"
Skill 100-149:  "[Weapon] Apprentice [Name]"   → "Sword Apprentice Kevin"
Skill 150-199:  "[Class Base] [Name]"          → "Swordsman Kevin"
Skill 200-249:  "[Class] [Name]"               → "Blademaster Kevin"
Skill 250-299:  "[Class] Master [Name]"        → "Blademaster Master Kevin"
Skill 300:      "Grandmaster [Class] [Name]"   → "Grandmaster Blademaster Kevin"
```

### Prestige Titles (Multi-Mastery)

When players achieve Grandmaster (300) in multiple weapon skills, they earn prestige titles:

| Achievement | Title Format |
|-------------|--------------|
| 1x Grandmaster | "Grandmaster [Class] [Name]" |
| 2x Grandmaster | "[Dual Class Title] [Name]" (see below) |
| 3x Grandmaster | "Legendary [Primary Class] [Name]" |
| 4x Grandmaster | "Mythic [Primary Class] [Name]" |
| 5x Grandmaster | "Paragon [Name]" |
| All Grandmaster | "[Name] the Transcendent" |

### Dual-Mastery Titles

| Combo | Prestige Title |
|-------|----------------|
| Swords + Daggers | Sword Saint |
| Swords + Maces | Battle Lord |
| Swords + Staves | Spellblade |
| Daggers + Hammers | Shadow Crusher |
| Maces + Staves | Holy Warrior |
| Hammers + Spears | Warlord Prime |
| Staves + Any Melee | Arcane Knight |

### Title Rune Stacking

Title runes (like "Wolfbane") prepend to your class title:

```
"Wolfbane Grandmaster Blademaster Kevin"
"Dragonkin Sword Saint Kevin"
"The Undying Paragon Kevin"
```

### Class Passive Bonuses

Each emergent class grants a minor passive bonus:

| Class | Passive Bonus |
|-------|---------------|
| Blademaster | +5% sword damage |
| Assassin | +10% crit damage |
| Crusher | +10% stagger chance |
| Berserker | +3% damage per 10% HP missing |
| Dragoon | +20% range |
| Battle Mage | Attacks have 5% chance to deal bonus magic damage |
| Paladin | Take 10% less damage when HP > 50% |
| High Priest | +30% healing done |

---

## Integration: How It All Works Together

### Example Player Progression

**Early Game (Level 5, Cap: 50):**
```
Name: Kevin
Title: Adventurer Kevin
Class: None (Adventurer)

Weapon Skills (Cap: 50):
  Swords: 50/50 ✓ (maxed for level - using main weapon)
  Maces: 12/50 (tried briefly)

Runes:
  [1] Rune of Precision (+5% crit) - just found one!
```

**Mid Game (Level 15, Cap: 150):**
```
Name: Kevin
Title: Sword Apprentice Kevin
Class: Swordsman (emerging)

Weapon Skills (Cap: 150):
  Swords: 150/150 ✓ (maxed - Blade Precision unlocked!)
  Daggers: 67/150 (backup, 45%)
  Maces: 12/150 (abandoned, 8%)

Runes:
  [1] Rune of Precision (+5% crit)
  [2] Rune of the Relentless (chain decay)
```

**Late Game (Level 25, Cap: 250):**
```
Name: Kevin
Title: Blademaster Kevin
Class: Blademaster

Weapon Skills (Cap: 250):
  Swords: 250/250 ✓ (maxed - Blade Flurry unlocked!)
  Daggers: 200/250 (80% - Eviscerate unlocked!)

Runes:
  [1] Rune of Sanguine Fury (Blood Price ability)
  [2] Rune of Last Stand (+25% dmg low HP)
  [3] Rune of Precision (+5% crit)
  [4] Rune of the Leech (lifesteal) - unlocked at skill 200!

Abilities:
  [Q] Blade Flurry (Swords 200)
  [W] Eviscerate (Daggers 200)
  [E] Blood Price (Rune)
```

**Endgame (Level 30, Cap: 300):**
```
Name: Kevin
Title: Sword Saint Kevin
Class: Sword Saint (Swords 300 + Daggers 300)

Weapon Skills (Cap: 300 - MAXIMUM):
  Swords: 300/300 ★ GRANDMASTER
  Daggers: 300/300 ★ GRANDMASTER
  Spears: 89/300 (working on third mastery)

Runes:
  [1] Rune of Sanguine Fury
  [2] Rune of Last Stand
  [3] Rune of the Leech (lifesteal)
  [4] Wolfbane Rune (title + wolf bonus)
  [5] Rune of Shadows (Vanish ability) - unlocked with 1st Grandmaster!
  [6] 🔒 (need 2x Grandmaster - working on Spears)

Abilities:
  [Q] Blade Flurry (Swords 200)
  [W] Eviscerate (Daggers 200)
  [E] Blood Price (Rune)
  [R] Vanish (Rune)
```

---

## Technical Implementation

### New Files Required

```
scripts/systems/WeaponSkillManager.gd   - Weapon skill tracking & leveling
scripts/systems/DisciplineManager.gd    - Discipline affinity tracking
scripts/systems/RuneManager.gd          - Rune inventory & slot management
scripts/systems/ClassManager.gd         - Class/title determination
scripts/resources/Rune.gd               - Rune resource definition
scripts/ui/WeaponSkillUI.gd             - Weapon skills display
scripts/ui/DisciplineUI.gd              - Discipline progress display
scripts/ui/RuneUI.gd                    - Rune slots & management UI
scripts/ui/ClassDisplayUI.gd            - Title/class display
data/runes.json                         - Rune definitions
data/disciplines.json                   - Discipline definitions & thresholds
data/class_matrix.json                  - Class determination rules
data/weapon_skill_config.json           - Skill curve & milestone config
```

### Data Structures

**WeaponSkillManager.gd:**
```gdscript
extends Node

signal skill_gained(weapon_type: String, amount: float, new_total: float)
signal skill_milestone_reached(weapon_type: String, milestone: int)
signal grandmaster_achieved(weapon_type: String)
signal skill_capped(weapon_type: String)

var weapon_skills: Dictionary = {
    "swords": 1.0,
    "daggers": 1.0,
    "maces": 1.0,
    "hammers": 1.0,
    "spears": 1.0,
    "staves": 1.0,
    "axes": 1.0,
    "bows": 1.0,
    "shields": 1.0
}

const ABSOLUTE_SKILL_CAP = 300.0
const MILESTONES = [50, 100, 150, 200, 250, 300]

# Skill cap is based on player level
func get_skill_cap() -> float:
    return min(CharacterStats.level * 10.0, ABSOLUTE_SKILL_CAP)

# Get skill as percentage of current cap (0.0 to 1.0)
func get_skill_percentage(weapon_type: String) -> float:
    var current = weapon_skills[weapon_type]
    var cap = get_skill_cap()
    return clamp(current / cap, 0.0, 1.0)

# Add skill with catch-up mechanic
func add_skill(weapon_type: String, base_amount: float) -> void:
    var current = weapon_skills[weapon_type]
    var cap = get_skill_cap()

    # Can't exceed current level cap
    if current >= cap:
        return

    # Catch-up bonus: 2x gains when empty, 0.5x when nearly full
    var fill_ratio = current / cap
    var catch_up_bonus = lerp(2.0, 0.5, fill_ratio)

    var gain = base_amount * catch_up_bonus
    var old_skill = current
    weapon_skills[weapon_type] = min(current + gain, cap)

    emit_signal("skill_gained", weapon_type, gain, weapon_skills[weapon_type])
    _check_milestones(weapon_type, old_skill, weapon_skills[weapon_type])

    # Check if we just capped
    if weapon_skills[weapon_type] >= cap and old_skill < cap:
        emit_signal("skill_capped", weapon_type)

# Miss chance based on fill percentage (NOT absolute skill)
func get_miss_chance(weapon_type: String) -> float:
    var pct = get_skill_percentage(weapon_type)
    # 100% filled = 0% miss, 0% filled = 25% miss
    return lerp(0.25, 0.0, pct)

# Damage modifier based on fill percentage (NOT absolute skill)
func get_damage_modifier(weapon_type: String) -> float:
    var pct = get_skill_percentage(weapon_type)
    # 100% filled = 100% damage, 0% filled = 50% damage
    return lerp(0.5, 1.0, pct)

# Check if player has unlocked a milestone (requires both level AND skill)
func has_milestone(weapon_type: String, milestone: int) -> bool:
    var required_level = milestone / 10  # 100 skill requires level 10
    if CharacterStats.level < required_level:
        return false
    return weapon_skills[weapon_type] >= milestone

# Get highest weapon skill (for class determination)
func get_highest_weapon_type() -> String:
    var highest_type = "swords"
    var highest_skill = 0.0
    for weapon_type in weapon_skills:
        if weapon_skills[weapon_type] > highest_skill:
            highest_skill = weapon_skills[weapon_type]
            highest_type = weapon_type
    return highest_type

func get_highest_skill() -> float:
    return weapon_skills[get_highest_weapon_type()]

# Count grandmaster weapons (skill 300 at level 30)
func get_grandmaster_count() -> int:
    if CharacterStats.level < 30:
        return 0
    var count = 0
    for weapon_type in weapon_skills:
        if weapon_skills[weapon_type] >= 300:
            count += 1
    return count

func _check_milestones(weapon_type: String, old_skill: float, new_skill: float) -> void:
    for milestone in MILESTONES:
        if old_skill < milestone and new_skill >= milestone:
            emit_signal("skill_milestone_reached", weapon_type, milestone)
            if milestone == 300:
                emit_signal("grandmaster_achieved", weapon_type)
```

**DisciplineManager.gd:**
```gdscript
extends Node

signal affinity_gained(discipline: String, amount: float, new_total: float)
signal discipline_threshold_reached(discipline: String, tier: String)
signal ability_unlocked(discipline: String, ability_name: String)

var discipline_affinities: Dictionary = {
    "warfare": 0.0,
    "finesse": 0.0,
    "brutality": 0.0,
    "piety": 0.0,
    "guardianship": 0.0
}

# Thresholds for each tier
const THRESHOLDS = {
    "initiate": 500,
    "adept": 1000,
    "specialist": 2500,
    "expert": 5000,
    "master": 10000
}

# Add affinity points to a discipline
func add_affinity(discipline: String, amount: float) -> void:
    if not discipline_affinities.has(discipline):
        return

    var old_value = discipline_affinities[discipline]
    discipline_affinities[discipline] += amount

    emit_signal("affinity_gained", discipline, amount, discipline_affinities[discipline])
    _check_thresholds(discipline, old_value, discipline_affinities[discipline])

# Get the player's primary (highest) discipline
func get_highest_discipline() -> String:
    var highest = "warfare"
    var highest_value = 0.0
    for discipline in discipline_affinities:
        if discipline_affinities[discipline] > highest_value:
            highest_value = discipline_affinities[discipline]
            highest = discipline
    return highest

func get_highest_affinity() -> float:
    return discipline_affinities[get_highest_discipline()]

# Get current tier for a discipline
func get_tier(discipline: String) -> String:
    var affinity = discipline_affinities[discipline]
    if affinity >= THRESHOLDS.master: return "master"
    if affinity >= THRESHOLDS.expert: return "expert"
    if affinity >= THRESHOLDS.specialist: return "specialist"
    if affinity >= THRESHOLDS.adept: return "adept"
    if affinity >= THRESHOLDS.initiate: return "initiate"
    return "unrecognized"

# Check if discipline ability is unlocked
func has_ability(discipline: String, tier: String) -> bool:
    var required = THRESHOLDS.get(tier, 999999)
    return discipline_affinities[discipline] >= required

# Called from combat system to track player actions
func on_enemy_killed() -> void:
    add_affinity("warfare", 1.0)

func on_critical_hit() -> void:
    add_affinity("finesse", 0.5)

func on_one_shot_kill() -> void:
    add_affinity("finesse", 1.0)

func on_dodge_iframe() -> void:
    add_affinity("finesse", 2.0)

func on_chain_milestone(chain_level: int) -> void:
    if chain_level >= 5:
        add_affinity("brutality", 2.0)

func on_overkill(overkill_percent: float) -> void:
    if overkill_percent >= 0.5:
        add_affinity("brutality", 0.5)

func on_multi_kill(kill_count: int) -> void:
    if kill_count >= 2:
        add_affinity("brutality", kill_count * 1.5)

func on_ally_healed(amount: float) -> void:
    if amount >= 50:
        add_affinity("piety", 1.0)

func on_ally_revived() -> void:
    add_affinity("piety", 10.0)

func on_damage_taken_for_ally() -> void:
    add_affinity("guardianship", 0.5)

func on_aggro_held(enemy_count: int) -> void:
    if enemy_count >= 3:
        add_affinity("guardianship", 1.0)

func _check_thresholds(discipline: String, old_value: float, new_value: float) -> void:
    for tier in THRESHOLDS:
        var threshold = THRESHOLDS[tier]
        if old_value < threshold and new_value >= threshold:
            emit_signal("discipline_threshold_reached", discipline, tier)
            if tier == "specialist" or tier == "master":
                var ability_name = _get_ability_name(discipline, tier)
                emit_signal("ability_unlocked", discipline, ability_name)

func _get_ability_name(discipline: String, tier: String) -> String:
    var abilities = {
        "warfare": {"specialist": "Battle Cry", "master": "Unstoppable"},
        "finesse": {"specialist": "Riposte", "master": "Death Mark"},
        "brutality": {"specialist": "Execute", "master": "Rampage"},
        "piety": {"specialist": "Sanctuary", "master": "Divine Shield"},
        "guardianship": {"specialist": "Taunt", "master": "Last Stand"}
    }
    return abilities.get(discipline, {}).get(tier, "Unknown")
```

**RuneManager.gd:**
```gdscript
extends Node

signal rune_equipped(slot: int, rune: Rune)
signal rune_unequipped(slot: int, rune: Rune)
signal rune_ability_activated(rune: Rune)
signal rune_slots_updated(available_slots: int)

var equipped_runes: Array[Rune] = [null, null, null, null, null, null]
var rune_pouch: Array[Rune] = []
var rune_cooldowns: Dictionary = {}

const MAX_SLOTS = 6
const MAX_POUCH_SIZE = 20

func get_available_slots() -> int:
    var slots = 0
    if CharacterStats.level >= 5: slots += 1
    if CharacterStats.level >= 15: slots += 1
    if CharacterStats.level >= 25: slots += 1
    if WeaponSkillManager.get_highest_skill() >= 200: slots += 1
    if WeaponSkillManager.get_grandmaster_count() >= 1: slots += 1
    if WeaponSkillManager.get_grandmaster_count() >= 2: slots += 1
    return slots

func equip_rune(rune: Rune, slot: int) -> bool:
    if slot >= get_available_slots():
        return false
    if rune.min_level > CharacterStats.level:
        return false

    if equipped_runes[slot] != null:
        rune_pouch.append(equipped_runes[slot])

    equipped_runes[slot] = rune
    rune_pouch.erase(rune)
    emit_signal("rune_equipped", slot, rune)
    return true

func get_passive_bonuses() -> Dictionary:
    var bonuses = {}
    for rune in equipped_runes:
        if rune != null and rune.type == Rune.Type.PASSIVE:
            bonuses.merge(rune.bonuses, true)
    return bonuses

func get_trait_bonuses(context: Dictionary) -> Dictionary:
    var bonuses = {}
    for rune in equipped_runes:
        if rune != null and rune.type == Rune.Type.TRAIT:
            if rune.check_condition(context):
                bonuses.merge(rune.bonuses, true)
    return bonuses
```

**Rune.gd Resource:**
```gdscript
extends Resource
class_name Rune

enum Type { ABILITY, PASSIVE, TRAIT, TITLE }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, ARTIFACT }

@export var id: String
@export var name: String
@export var description: String
@export var type: Type
@export var rarity: Rarity
@export var icon: Texture2D

# For ABILITY type
@export var ability_name: String
@export var ability_description: String
@export var cooldown: float
@export var ability_script: Script  # Custom ability logic

# For PASSIVE type
@export var bonuses: Dictionary  # {"crit_chance": 0.05, "max_hp": 50}

# For TRAIT type
@export var condition: String  # "hp_below_30", "chain_above_5", etc.
@export var trait_bonuses: Dictionary

# For TITLE type
@export var title_granted: String
@export var title_requirement: Dictionary  # {"kill_wolves": 500}
@export var title_progress: int = 0
@export var title_bonus: Dictionary

@export var min_level: int = 1
@export var min_weapon_skill: int = 0
@export var tradeable: bool = true
@export var drop_sources: Array[String] = []
@export var drop_rate: float = 0.01
```

**ClassManager.gd:**
```gdscript
extends Node

signal class_changed(old_class: String, new_class: String)
signal title_changed(old_title: String, new_title: String)

var current_class: String = "Adventurer"
var current_title: String = "Adventurer"

var class_matrix: Dictionary = {}  # Loaded from JSON
var title_tiers: Dictionary = {}   # Loaded from JSON

func _ready():
    WeaponSkillManager.skill_gained.connect(_on_skill_changed)
    DisciplineManager.affinity_gained.connect(_on_discipline_changed)
    RuneManager.rune_equipped.connect(_on_runes_changed)
    RuneManager.rune_unequipped.connect(_on_runes_changed)
    _load_class_data()

func determine_class() -> String:
    var primary_weapon = WeaponSkillManager.get_highest_weapon_type()
    var primary_skill = WeaponSkillManager.get_highest_skill()

    if primary_skill < 50:
        return "Adventurer"

    # Class is determined by weapon + discipline combination
    var primary_discipline = DisciplineManager.get_highest_discipline()

    if class_matrix.has(primary_weapon) and class_matrix[primary_weapon].has(primary_discipline):
        return class_matrix[primary_weapon][primary_discipline]

    return _get_base_class(primary_weapon)

func determine_title() -> String:
    var primary = WeaponSkillManager.get_highest_weapon_type()
    var primary_skill = WeaponSkillManager.get_highest_skill()
    var grandmaster_count = WeaponSkillManager.get_grandmaster_count()

    # Check for prestige titles first
    if grandmaster_count >= 6:
        return "%s the Transcendent" % CharacterStats.player_name
    if grandmaster_count >= 5:
        return "Paragon %s" % CharacterStats.player_name
    if grandmaster_count >= 4:
        return "Mythic %s %s" % [current_class, CharacterStats.player_name]
    if grandmaster_count >= 3:
        return "Legendary %s %s" % [current_class, CharacterStats.player_name]
    if grandmaster_count >= 2:
        return "%s %s" % [_get_dual_mastery_title(), CharacterStats.player_name]

    # Standard title progression
    var title_rune_prefix = RuneManager.get_title_rune_prefix()
    var base_title = _get_skill_title(primary, primary_skill)

    if title_rune_prefix != "":
        return "%s %s" % [title_rune_prefix, base_title]
    return base_title

func _get_skill_title(weapon_type: String, skill: float) -> String:
    var name = CharacterStats.player_name
    var weapon_name = weapon_type.capitalize().trim_suffix("s")  # "swords" -> "Sword"

    if skill >= 300:
        return "Grandmaster %s %s" % [current_class, name]
    if skill >= 250:
        return "%s Master %s" % [current_class, name]
    if skill >= 200:
        return "%s %s" % [current_class, name]
    if skill >= 150:
        return "%s %s" % [_get_base_class(weapon_type), name]
    if skill >= 100:
        return "%s Apprentice %s" % [weapon_name, name]
    if skill >= 50:
        return "%s Initiate %s" % [weapon_name, name]
    return "Adventurer %s" % name
```

### Modifications to Existing Files

**CharacterStats.gd additions:**
```gdscript
# Add to save_data
func get_save_data() -> Dictionary:
    var data = {
        # ... existing fields ...
        "weapon_skills": WeaponSkillManager.weapon_skills.duplicate(),
        "discipline_affinities": DisciplineManager.discipline_affinities.duplicate(),
        "equipped_runes": RuneManager.get_equipped_rune_ids(),
        "rune_pouch": RuneManager.get_pouch_rune_ids(),
        "title_rune_progress": RuneManager.get_title_progress(),
    }
    return data

func load_save_data(data: Dictionary) -> void:
    # ... existing loading ...
    if data.has("weapon_skills"):
        WeaponSkillManager.weapon_skills = data.weapon_skills
    if data.has("discipline_affinities"):
        DisciplineManager.discipline_affinities = data.discipline_affinities
    if data.has("equipped_runes"):
        RuneManager.load_equipped_runes(data.equipped_runes)
    if data.has("rune_pouch"):
        RuneManager.load_pouch(data.rune_pouch)
```

**PlayerCombat.gd modifications:**
```gdscript
func attempt_attack(target: Node2D) -> void:
    var weapon = CharacterStats.get_equipped_weapon()
    var weapon_type = weapon.get_weapon_skill_type()
    var target_hp_before = target.current_hp

    # Check for miss based on weapon skill
    var miss_chance = WeaponSkillManager.get_miss_chance(weapon_type)
    if randf() < miss_chance:
        _show_miss_text()
        WeaponSkillManager.add_skill(weapon_type, 0.1)  # Small gain on miss
        return

    # Apply damage modifier from weapon skill
    var skill_modifier = WeaponSkillManager.get_damage_modifier(weapon_type)
    var base_damage = calculate_base_damage()
    var final_damage = base_damage * skill_modifier

    # Apply discipline passive bonuses
    var discipline_bonuses = DisciplineManager.get_passive_bonuses()
    if discipline_bonuses.has("damage_bonus"):
        final_damage *= (1.0 + discipline_bonuses.damage_bonus)

    # Apply rune bonuses
    var context = {"hp_percent": CharacterStats.get_hp_percent(), "chain": chain_level}
    var rune_bonuses = RuneManager.get_trait_bonuses(context)
    if rune_bonuses.has("damage_bonus"):
        final_damage *= (1.0 + rune_bonuses.damage_bonus)

    # Check for crit
    var is_critical = _roll_critical()
    if is_critical:
        final_damage *= 2.0
        DisciplineManager.on_critical_hit()  # Track for Finesse

    # Deal damage
    target.take_damage(final_damage)

    # Track discipline affinity based on combat actions
    if target.current_hp <= 0:
        DisciplineManager.on_enemy_killed()  # Track for Warfare

        # Check for one-shot kill (Finesse)
        if target_hp_before == target.max_hp:
            DisciplineManager.on_one_shot_kill()

        # Check for overkill (Brutality)
        var overkill = abs(target.current_hp) / target.max_hp
        if overkill >= 0.5:
            DisciplineManager.on_overkill(overkill)

    # Award weapon skill points
    var skill_gain = 0.5  # Base hit gain
    if is_critical:
        skill_gain += 1.0
    if target.current_hp <= 0:
        skill_gain += 2.0

    WeaponSkillManager.add_skill(weapon_type, skill_gain)

# Called when chain multiplier increases
func _on_chain_increased(new_level: int) -> void:
    if new_level >= 5:
        DisciplineManager.on_chain_milestone(new_level)

# Called when player dodges with i-frames
func _on_dodge_iframe_hit() -> void:
    DisciplineManager.on_dodge_iframe()

# Called when player heals an ally
func _on_ally_healed(ally: Node2D, amount: float) -> void:
    DisciplineManager.on_ally_healed(amount)
```

### Data Files

**data/runes.json:**
```json
{
  "runes": [
    {
      "id": "rune_sanguine_fury",
      "name": "Rune of Sanguine Fury",
      "description": "A crimson rune pulsing with vital energy",
      "type": "ability",
      "rarity": "rare",
      "ability_name": "Blood Price",
      "ability_description": "Sacrifice 15% HP for +30% damage (10s)",
      "cooldown": 60,
      "drop_sources": ["crimson_hollow_elite", "blood_knight"],
      "drop_rate": 0.005
    },
    {
      "id": "rune_relentless",
      "name": "Rune of the Relentless",
      "description": "Carved from the fang of an alpha predator",
      "type": "passive",
      "rarity": "uncommon",
      "bonuses": {
        "chain_decay_reduction": 0.5
      },
      "drop_sources": ["elite_wolf", "dire_wolf"],
      "drop_rate": 0.01
    },
    {
      "id": "rune_last_stand",
      "name": "Rune of Last Stand",
      "description": "Glows brighter as death approaches",
      "type": "trait",
      "rarity": "rare",
      "condition": "hp_below_30",
      "trait_bonuses": {
        "damage_bonus": 0.25
      },
      "drop_sources": ["world_boss"],
      "drop_rate": 0.02
    },
    {
      "id": "rune_wolfbane",
      "name": "Wolfbane Rune",
      "description": "The mark of a hunter who has culled the pack",
      "type": "title",
      "rarity": "epic",
      "title_granted": "Wolfbane",
      "title_requirement": {
        "kill_enemy_type": "wolf",
        "count": 500
      },
      "title_bonus": {
        "damage_vs_wolves": 0.05
      },
      "drop_sources": ["alpha_wolf"],
      "drop_rate": 0.003
    }
  ]
}
```

**data/disciplines.json:**
```json
{
  "disciplines": {
    "warfare": {
      "name": "Warfare",
      "description": "Aggressive frontline combat",
      "thresholds": {
        "initiate": 500,
        "adept": 1000,
        "specialist": 2500,
        "expert": 5000,
        "master": 10000
      },
      "passive": {
        "name": "Battle Hardened",
        "effect": {"damage_bonus": 0.05}
      },
      "abilities": {
        "specialist": {
          "name": "Battle Cry",
          "description": "+20% damage for 10s, allies get +10%",
          "cooldown": 45
        },
        "master": {
          "name": "Unstoppable",
          "description": "Immune to CC, +30% damage for 6s",
          "cooldown": 90
        }
      }
    },
    "finesse": {
      "name": "Finesse",
      "description": "Precision and critical strikes",
      "passive": {
        "name": "Keen Eye",
        "effect": {"crit_chance": 0.05}
      },
      "abilities": {
        "specialist": {
          "name": "Riposte",
          "description": "After dodging, next attack guaranteed crit",
          "cooldown": 20
        },
        "master": {
          "name": "Death Mark",
          "description": "Target takes +30% damage from all sources (8s)",
          "cooldown": 60
        }
      }
    },
    "brutality": {
      "name": "Brutality",
      "description": "Momentum and overwhelming force",
      "passive": {
        "name": "Blood Frenzy",
        "effect": {"damage_per_chain": 0.02}
      },
      "abilities": {
        "specialist": {
          "name": "Execute",
          "description": "+50% damage to enemies below 25% HP",
          "cooldown": 15
        },
        "master": {
          "name": "Rampage",
          "description": "Kills extend all active buffs by 3s",
          "cooldown": 45
        }
      }
    },
    "piety": {
      "name": "Piety",
      "description": "Healing and support",
      "passive": {
        "name": "Blessed Touch",
        "effect": {"healing_power": 0.15}
      },
      "abilities": {
        "specialist": {
          "name": "Sanctuary",
          "description": "Place heal zone (15 HP/sec, 6s)",
          "cooldown": 40
        },
        "master": {
          "name": "Divine Shield",
          "description": "Absorb shield on ally (blocks 100 damage)",
          "cooldown": 50
        }
      }
    },
    "guardianship": {
      "name": "Guardianship",
      "description": "Protection and tanking",
      "passive": {
        "name": "Stalwart",
        "effect": {"damage_reduction": 0.10}
      },
      "abilities": {
        "specialist": {
          "name": "Taunt",
          "description": "Force nearby enemies to target you (5s)",
          "cooldown": 30
        },
        "master": {
          "name": "Last Stand",
          "description": "Survive fatal hit at 1 HP (once per 5 min)",
          "cooldown": 300
        }
      }
    }
  }
}
```

**data/class_matrix.json:**
```json
{
  "class_matrix": {
    "swords": {
      "warfare": "Blademaster",
      "finesse": "Duelist",
      "brutality": "Berserker",
      "piety": "Templar",
      "guardianship": "Sword Knight",
      "default": "Swordsman"
    },
    "daggers": {
      "warfare": "Assassin",
      "finesse": "Rogue",
      "brutality": "Cutthroat",
      "piety": "Nightblade",
      "guardianship": "Shadow Guard",
      "default": "Knifesman"
    },
    "maces": {
      "warfare": "Crusher",
      "finesse": "Brawler",
      "brutality": "Ravager",
      "piety": "Priest",
      "guardianship": "Cleric",
      "default": "Bludgeoner"
    },
    "hammers": {
      "warfare": "Warlord",
      "finesse": "Executioner",
      "brutality": "Berserker",
      "piety": "Justicar",
      "guardianship": "Paladin",
      "default": "Hammerer"
    },
    "spears": {
      "warfare": "Dragoon",
      "finesse": "Lancer",
      "brutality": "Impaler",
      "piety": "Valkyrie",
      "guardianship": "Hoplite",
      "default": "Spearman"
    },
    "staves": {
      "warfare": "Battle Mage",
      "finesse": "Sage",
      "brutality": "Warlock",
      "piety": "High Priest",
      "guardianship": "Arcane Ward",
      "default": "Acolyte"
    }
  },
  "dual_mastery_titles": {
    "swords+daggers": "Sword Saint",
    "swords+maces": "Battle Lord",
    "swords+staves": "Spellblade",
    "swords+hammers": "Champion",
    "daggers+hammers": "Shadow Crusher",
    "daggers+spears": "Shadowlancer",
    "maces+staves": "Holy Warrior",
    "hammers+spears": "Warlord Prime",
    "staves+swords": "Arcane Knight",
    "staves+daggers": "Shadow Mage"
  },
  "class_passives": {
    "Blademaster": {"sword_damage": 0.05},
    "Duelist": {"crit_damage": 0.08},
    "Assassin": {"crit_damage": 0.10},
    "Rogue": {"dodge_chance": 0.05},
    "Crusher": {"stagger_chance": 0.10},
    "Berserker": {"damage_per_missing_hp_10": 0.03},
    "Warlord": {"damage_bonus": 0.05},
    "Dragoon": {"attack_range": 0.20},
    "Battle Mage": {"magic_proc_chance": 0.05},
    "Paladin": {"damage_reduction_above_50hp": 0.10},
    "High Priest": {"healing_power": 0.30},
    "Templar": {"healing_power": 0.15, "damage_bonus": 0.03}
  }
}
```

---

## Balance Considerations

### Weapon Skill Progression (Level-Tied)

Since weapon skill is capped by player level, progression happens naturally as you level:

| Level | Skill Cap | Milestone Unlockable | Time to Reach Level |
|-------|-----------|---------------------|---------------------|
| 5 | 50 | Initiate | ~1 hour |
| 10 | 100 | Passive | ~3 hours |
| 15 | 150 | Rare Access | ~6 hours |
| 20 | 200 | Ability | ~10 hours |
| 25 | 250 | Legendary Access | ~15 hours |
| 30 | 300 | Grandmaster | ~20-25 hours |

**Key Design Points:**
- Reaching max level (30) takes ~20-25 hours
- If you've been using your main weapon consistently, it's maxed when you hit 30
- Catching up a new weapon at level 30 takes ~100 kills (~1-2 hours)
- Second Grandmaster (for prestige title) requires dedicated grinding post-30

### Catch-Up Kill Estimates

How many kills to fill a weapon skill bar at various levels:

| Starting Point | Kills to Cap | Time (1 kill/min) |
|----------------|--------------|-------------------|
| 0% filled | ~100 kills | ~1.5 hours |
| 25% filled | ~80 kills | ~1.2 hours |
| 50% filled | ~60 kills | ~1 hour |
| 75% filled | ~40 kills | ~40 min |
| After level-up (91% filled) | ~15 kills | ~15 min |

This ensures:
- Weapon swapping has a cost (1-2 hours to catch up)
- But it's not punishing (you can experiment)
- Leveling up creates small "maintenance" goals

### Rune Drop Rates

Runes should feel rewarding but not trivialize content:

| Rarity | Expected Drops Per Hour |
|--------|------------------------|
| Common | 2-3 |
| Uncommon | 0.5-1 |
| Rare | 1 per 3-4 hours |
| Epic | 1 per 10-15 hours |
| Legendary | 1 per 30-50 hours |
| Artifact | Boss-only, 5-10% per kill |

### Ability Power Budget

Weapon abilities (skill 200) should be impactful but not required:

- **DPS increase from abilities:** ~10-15% when used optimally
- **Rune ability impact:** Similar to weapon abilities
- **Stacking concern:** 2 ability runes + weapon ability shouldn't exceed 30% DPS increase

---

## Future Expansion Hooks

### Shield Skill & Blocking
When shields are added:
- New "Shields" weapon skill
- Block mechanic (reduce incoming damage)
- Guardianship-style runes that synergize

### Ranged Combat
When bows are added:
- "Bows" weapon skill
- Ranged attack mechanics
- Marksmanship runes

### Magic System
If spellcasting is added:
- Could tie to Staves skill
- Runes could grant spell abilities
- Opens "Mage" class branches

### Group Content
- Runes that buff allies
- Class synergies (Paladin aura + DPS classes)
- Raid-specific rune drops

---

## Summary

### The Four Systems

| System | What It Tracks | Player Control | Unlocks |
|--------|----------------|----------------|---------|
| **Weapon Skills** | Proficiency per weapon type | Deliberate (use a weapon) | Accuracy, damage, weapon abilities |
| **Discipline Affinity** | HOW you play (playstyle) | Automatic (emergent) | Discipline passives & abilities |
| **Runes** | World drop items | Deliberate (slot choices) | Custom abilities & bonuses |
| **Emergent Class** | Combination of above | Emergent | Class identity & title |

### What This System Creates

1. **Fair at every level** - Weapon skill is capped by player level; a maxed level 5 is just as effective as a maxed level 30 (relative to their tier)
2. **Playstyle matters** - Two sword users with different playstyles become different classes (Blademaster vs Duelist)
3. **Meaningful investment** - High-level weapon swapping requires catch-up grind (~100 kills)
4. **Natural progression** - Weapon mastery and discipline growth happen alongside leveling
5. **Build diversity** - Runes allow customization independent of weapon/discipline
6. **30 unique classes** - 6 weapons × 5 disciplines = emergent identity
7. **Prestige path** - Post-30 grinding for Grandmaster titles and multi-mastery
8. **Horizontal content** - Rune hunting and discipline mastery beyond level cap

### Key Design Principles

| Principle | Implementation |
|-----------|----------------|
| Low levels aren't punished | Effectiveness is relative to YOUR cap |
| Weapon swapping has cost | Must grind ~100 kills to catch up |
| Playstyle shapes identity | Discipline tracks behavior automatically |
| Leveling feels rewarding | New skill cap = new room to grow |
| Same weapon ≠ same class | Discipline determines class variant |
| Mastery is earned | Grandmaster requires level 30 + maxed skill |
| Prestige is optional | Multi-Grandmaster for dedicated players |

### Player Journey Example

```
Level 1-5:   Adventurer → trying weapons, discipline unformed
Level 5-15:  Sword Initiate → Warfare growing from kills
Level 15-25: Swordsman → Warfare specialist, Battle Cry unlocked
Level 25-30: Blademaster → Maxed sword skill + Warfare Specialist
Post-30:     Grandmaster Blademaster → Working on 2nd weapon for prestige
Prestige:    Sword Saint → Swords + Daggers both at 300
```

The system respects player time at every stage while creating meaningful choices and long-term goals for those who want them.
