# Native Item Progression System (Levels 1-30)

## Overview

This document defines the in-game dropped/purchased items that form the core progression path for all players. Native items are the foundation of Dreadland's gear system - they provide meaningful progression independent of forge items while creating interesting synergies at endgame.

### Design Philosophy

```
NATIVE ITEMS:
- Level-gated progression (earned through gameplay)
- Darker, weathered aesthetic (contrast with golden forge items)
- Set bonuses at endgame (reward dedication to a build)
- Forge synergies (unlock at Tier 3)

FORGE ITEMS:
- No level requirements (twinking system)
- Gold/light aesthetic (prestige look)
- Unique effects/abilities
- ~15-25% of optimal endgame loadout
```

---

## Class Identities (4 Disciplines)

Dreadland supports 4 class identities that define playstyle. Any player can spec into any class via gear and stat allocation.

### Tank
**Role**: Frontline defender, damage soak, team protection
**Primary Armor**: Plate
**Primary Stats**: VIT (HP/Defense), STR (Block Effectiveness)
**Key Mechanics**:
- High HP pool and defense mitigation
- Block chance with shields
- Taunt/aggro management (future)
**Forge Synergy**: Lifesteal sustain, survival passives

### DPS (Damage Dealer)
**Role**: Primary damage output, kill targets fast
**Subtypes**:
- **Plate DPS (Warrior)**: Plate + Heavy weapons (greatsword, axe, halberd)
- **Leather DPS (Assassin)**: Leather + Light weapons (daggers, rapiers, katanas)
- **Ranged DPS (Hunter)**: Leather + Bow
- **Caster DPS (Mage)**: Cloth + Damage Staff
**Primary Stats**:
- Plate DPS: STR (Heavy damage), AGI (Attack Speed)
- Leather DPS: DEX (Light damage), AGI (Crit)
- Caster DPS: INT (Staff damage), WIS (Staff Crit)
**Key Mechanics**:
- Plate DPS: Big hits, cleave, execute damage, bleed
- Leather DPS: Critical hits, burst damage, chain building
- Caster DPS: Ranged magic damage, spell effects
**Forge Synergy**: Bleed effects, execute damage, armor penetration

### Healer
**Role**: Team sustain, health restoration
**Primary Armor**: Cloth
**Primary Weapon**: Healing Staff
**Primary Stats**: INT (Staff Power), WIS (Staff Crit, CDR)
**Key Mechanics**:
- Staff healing scales with INT
- Cooldown reduction for ability uptime
- Moderate damage when not healing
**Forge Synergy**: +Staff Power, AoE healing procs

### Support
**Role**: Utility, buffs, debuffs, crowd control
**Primary Armor**: Mixed (Cloth or Leather depending on build)
**Primary Stats**: WIS (CDR, Stamina Regen), AGI (Move Speed)
**Key Mechanics**:
- Ability spam with high CDR
- Movement speed for positioning
- Future: buff/debuff abilities
**Forge Synergy**: Utility procs (slows, stuns, team buffs)

### Class-Armor Mapping

| Class | Primary Armor | Primary Stats | Recommended Weapons |
|-------|---------------|---------------|---------------------|
| Tank | Plate | VIT/STR | Sword + Shield, Mace, Hammer |
| Plate DPS | Plate | STR/AGI | Greatsword, Axe, Halberd |
| Leather DPS | Leather | DEX/AGI | Dagger, Rapier, Katana |
| Ranged DPS | Leather | DEX/AGI | Bow |
| Caster DPS | Cloth | INT/WIS | Damage Staff |
| Healer | Cloth | INT/WIS | Healing Staff |
| Support | Cloth/Leather | WIS/AGI | Support Staff, Rapier |

---

## Weapon Types & Scaling

Weapons are divided into three categories based on their primary damage stat.

### Heavy Weapons (STR Scaling)
Used by Plate wearers (Tank and Plate DPS). Slower attacks, higher damage per hit.

| Weapon | Speed | Base Crit | Identity | Best For |
|--------|-------|-----------|----------|----------|
| **Sword** | Medium | 8% | Balanced, shield-compatible | Tank |
| **Greatsword** | Slow | 10% | Highest damage, two-handed | Plate DPS |
| **Axe** | Slow | 9% | Bleed on hit | Plate DPS |
| **Mace** | Slow | 10% | Armor penetration, stun | Tank |
| **Hammer** | Slow | 11% | Knockback, highest single-hit | Tank |
| **Spear** | Medium | 8% | Reach, thrust attacks | Versatile |
| **Halberd** | Slow | 9% | Reach + high damage | Plate DPS |

**Heavy Weapon Effects (Forge):**
- Lifesteal (Tank sustain)
- Cleave (hit multiple enemies)
- Stagger (interrupt enemy attacks)
- Execute (bonus damage below 25% HP)

### Light Weapons (DEX Scaling)
Used by Leather wearers (Assassin DPS). Faster attacks, crit-focused.

| Weapon | Speed | Base Crit | Identity | Best For |
|--------|-------|-----------|----------|----------|
| **Dagger** | Very Fast | 18% | Highest crit, chain builder | Chain specialists |
| **Rapier** | Fast | 10% | Armor penetration, precision | Anti-tank |
| **Katana** | Fast | 12% | Weakpoint bonus, balanced | General DPS |
| **Scimitar** | Fast | 11% | Bleed on crit | Sustained damage |
| **Saber** | Fast | 10% | Parry bonus, riposte | Defensive DPS |
| **Bow** | Medium | 12% | Ranged, safe positioning | Ranged DPS |

**Light Weapon Effects (Forge):**
- Bleed (damage over time)
- Poison (slow + DoT)
- Armor Penetration (ignore % defense)
- Chain Damage Bonus (+X% at max chain)
- Backstab Bonus (+X% from behind)

### Staff Weapons (INT Scaling)
Used by Cloth wearers (Caster, Healer, Support). Ranged attacks, magic damage.

| Weapon | Speed | Base Crit | Identity | Best For |
|--------|-------|-----------|----------|----------|
| **Damage Staff** | Medium | 8% | Ranged magic damage | Caster DPS |
| **Healing Staff** | Medium | 8% | Heals allies, moderate damage | Healer |
| **Support Staff** | Medium | 6% | Buffs/debuffs, utility | Support |

**Staff Damage Formula:**
```
Staff Damage = Base Staff Damage + (INT * 0.5)
Staff Crit Chance = Base Crit + (WIS * 0.25%)
```

**Staff Effects (Forge):**
- Spell Power (+% staff damage)
- Healing Power (+% healing done)
- Cooldown Reduction
- Mana/Stamina efficiency
- AoE radius increase

---

## Player Archetypes (Endgame)

At endgame, three distinct player types emerge based on how they acquire gear:

### Whales (All Forge Gear)
**Profile**: Players with significant Mantle achievements, early adopters, collectors
**Gear Source**: 100% Forge items from bridging achievements
**Power Curve**:
```
Level 1:  ~800 effective power (MASSIVE early advantage)
Level 15: ~850 effective power (plateau)
Level 30: ~1000 effective power (base forge power)
```
**Strengths**:
- Dominate early/mid game
- Unique legendary effects
- Prestige golden aesthetic
- No grinding required for gear
**Weaknesses**:
- No set bonuses (forge items don't form sets)
- No forge synergies (need native T3 for those)
- Power plateaus earlier

### Grinders (All Native Gear)
**Profile**: Pure F2P players, completionists, anti-P2W philosophy
**Gear Source**: 100% dropped/purchased native items
**Power Curve**:
```
Level 1:  ~100 effective power (naked start)
Level 15: ~400 effective power (grinding up)
Level 30: ~950-1000 effective power + SET BONUSES
```
**Strengths**:
- Full set bonuses (2pc/4pc/5pc effects)
- No dependency on external achievements
- Satisfaction of earned progression
- Darker "veteran" aesthetic
**Weaknesses**:
- Slow early/mid game progression
- Must grind gold and levels
- Miss unique forge abilities

### Normies (Mixed Gear)
**Profile**: Casual players, hybrid approach, optimal min-maxers
**Gear Source**: Mix of forge items + native T3 pieces
**Power Curve**:
```
Level 1:  ~400-600 effective power (some forge items)
Level 15: ~600-700 effective power (hybrid)
Level 30: ~1050 effective power (FORGE SYNERGIES ACTIVE)
```
**Strengths**:
- HIGHEST endgame power (forge synergies)
- Best of both worlds
- Flexibility in build options
- Can fill gaps with native items
**Weaknesses**:
- Requires both grinding AND achievements
- More complex gearing decisions
- Neither pure aesthetic

### Endgame Balance Philosophy

```
DESIGN GOAL: All three archetypes viable at endgame

Whales:     Pure forge power + unique effects = ~1000 power
Grinders:   Native power + full set bonuses   = ~1000 power
Normies:    Mixed power + forge synergies     = ~1050 power

The ~5% "normie bonus" rewards versatility but doesn't
invalidate pure builds. A skilled grinder beats a
mediocre whale through set bonus procs and game knowledge.
```

### PvP Counterplay Between Archetypes

| Matchup | Dynamic |
|---------|---------|
| Whale vs Grinder | Whale has unique procs, Grinder has set bonus sustain |
| Whale vs Normie | Normie has synergy edge, Whale has more legendary effects |
| Grinder vs Normie | Grinder has full sets, Normie has hybrid flexibility |

**The key insight**: No archetype is strictly "best". Each has strengths that create meaningful counterplay. A full-forge burst assassin can delete a grinder before set bonuses proc. A full-native tank with Ironclad can survive whale burst and outlast them.

---

### Power Curve Target

```
Level 1 (naked):     100 effective power
Level 10 (Tier 1):   250 effective power
Level 20 (Tier 2):   500 effective power
Level 30 (Tier 3):   1000 effective power

Full Forge loadout:  ~1000 effective power (no level req)
Full Native T3:      ~950-1000 effective power + set bonuses
Mixed optimal:       ~1050 effective power (synergies)
```

### Weakpoint System Integration

Combat rhythm is defined by the **weakpoint window system**. Enemies trigger weakpoint windows at HP thresholds (75%, 50%, 25%), spawning clickable weakpoints. The number of weakpoints per window scales with level:

```
Level 1-10:  1 weakpoint per window  (3 total per fight)
Level 11-20: 2 weakpoints per window (6 total per fight)
Level 21-30: 3 weakpoints per window (9 total per fight)
```

**Critical Design Rule**: Weakpoint burst damage does NOT trigger new HP thresholds. Only normal attack damage counts toward crossing 75%/50%/25% thresholds. This prevents chain-killing where one weakpoint burst cascades into immediate subsequent windows.

```
Fight Rhythm (Level 30):
100% ──normal hits──▶ 75% ──WEAKPOINT (3 clicks)──▶ ~65% HP
 65% ──normal hits──▶ 50% ──WEAKPOINT (3 clicks)──▶ ~40% HP
 40% ──normal hits──▶ 25% ──WEAKPOINT (3 clicks)──▶ ~15% HP
 15% ──normal hits──▶ 0% DEAD
```

This creates a skill ceiling: faster/more accurate weakpoint clicking = faster kills, but you can't skip phases.

### TTK Calculations by Tier

**Assumptions:**
- Medium attack speed = ~1 hit/second
- Weakpoint damage = base_damage × 2.0 (crit multiplier)
- Enemy HP scales with zone difficulty
- All numbers assume same-tier enemy (not trivial or elite)

#### Tier 1 (Level 10, 1 weakpoint/window)

```
Player Stats (Copper Plate + Base):
├── STR: 25 (16 base + 9 armor)
├── VIT: 25 (10 base + 15 armor)
├── Damage bonus: +12.5
├── Weapon (Rusty Blade): 8-12 avg 10
├── Total damage/hit: ~22.5

Enemy (Zone 1 Skeleton):
├── HP: ~120
├── Defense: ~15 → 13% mitigation

Combat Flow:
├── Effective damage/hit: 22.5 × 0.87 = ~19.6
├── Hits to cross 75%: 30 HP / 19.6 = ~2 hits
├── WEAKPOINT (1 click): ~45 bonus damage → enemy at ~55 HP
├── Hits to cross 50%: 10 HP / 19.6 = ~1 hit
├── WEAKPOINT (1 click): ~45 bonus damage → enemy at ~20 HP
├── Hits to cross 25%: 10 HP / 19.6 = ~1 hit
├── WEAKPOINT (1 click): ~45 bonus damage → enemy DEAD

Total: ~4 normal hits + 3 weakpoint clicks = ~5-6 seconds
Skill gap: Perfect weakpoints save ~1-2 seconds
```

#### Tier 2 (Level 20, 2 weakpoints/window)

```
Player Stats (Iron Plate + Base):
├── STR: 45 (30 base + 15 armor)
├── VIT: 45 (20 base + 25 armor)
├── Damage bonus: +22.5
├── Weapon (Iron Longsword): 18-26 avg 22
├── Total damage/hit: ~44.5

Enemy (Zone 2 Zombie):
├── HP: ~300
├── Defense: ~35 → 26% mitigation

Combat Flow:
├── Effective damage/hit: 44.5 × 0.74 = ~33
├── Hits to cross 75%: 75 HP / 33 = ~2-3 hits
├── WEAKPOINT (2 clicks): ~90 bonus damage → enemy at ~135 HP
├── Hits to cross 50%: 15 HP / 33 = ~1 hit
├── WEAKPOINT (2 clicks): ~90 bonus damage → enemy at ~60 HP
├── Hits to cross 25%: 15 HP / 33 = ~1 hit
├── WEAKPOINT (2 clicks): ~90 bonus damage → enemy DEAD

Total: ~5 normal hits + 6 weakpoint clicks = ~7-8 seconds
Skill gap: Perfect weakpoints save ~2-3 seconds
```

#### Tier 3 (Level 30, 3 weakpoints/window)

```
Player Stats (Dark Steel + Base):
├── STR: 64 (40 base + 24 armor)
├── VIT: 70 (30 base + 40 armor)
├── Damage bonus: +32
├── Weapon (Dark Steel Blade): 35-50 avg 42.5
├── Total damage/hit: ~74.5

Enemy (Zone 3 Elite):
├── HP: ~600
├── Defense: ~60 → 38% mitigation

Combat Flow:
├── Effective damage/hit: 74.5 × 0.62 = ~46
├── Hits to cross 75%: 150 HP / 46 = ~3-4 hits
├── WEAKPOINT (3 clicks): ~150 bonus damage → enemy at ~300 HP
├── Hits to cross 50%: 0 HP needed (already below 50%)
├── WEAKPOINT (3 clicks): ~150 bonus damage → enemy at ~150 HP
├── Hits to cross 25%: 0 HP needed (already below 25%)
├── WEAKPOINT (3 clicks): ~150 bonus damage → enemy DEAD

Total: ~4 normal hits + 9 weakpoint clicks = ~8-10 seconds
Skill gap: Perfect weakpoints save ~3-4 seconds
```

### PvP Duel TTK (Level 30)

```
Plate vs Plate:
├── Attacker: 74.5 damage, Defender: 450 HP, 66 Defense (40% mitigation)
├── Effective damage: 74.5 × 0.6 = ~45 per hit
├── Normal hits to kill: 450 / 45 = ~10 hits
├── With 3 perfect weakpoint windows: ~7-8 hits
├── TTK: 10-12 seconds (skill-dependent)

Leather vs Leather:
├── Attacker: ~70 damage (42.5 + 34.5 DEX), Defender: 310 HP, 44 Defense (31% mitigation)
├── Effective damage: 70 × 0.69 = ~48 per hit
├── But 18.75% crit chance → avg ~52 damage
├── Normal hits to kill: 310 / 52 = ~6 hits
├── With weakpoints: ~4-5 hits
├── TTK: 6-8 seconds (more bursty due to crits)

Mixed matchups create interesting asymmetry:
├── Plate has more sustain, needs more hits to land
├── Leather has burst, but less room for error
└── Cloth with staff provides support/healing utility
```

---

## Armor Types (3 Archetypes)

### 1. Plate Armor - "The Iron Wall"
**Philosophy**: Maximum defense, health bonuses, slower movement
**Visual Theme**: Heavy metals - copper → iron → dark steel
**Color Palette**: Copper/brown → gray/silver → gunmetal/dark steel

| Stat Focus | Primary | Secondary |
|------------|---------|-----------|
| Defense | +++++ | |
| Max HP | +++ | |
| Block Chance | ++ | (with shield) |
| Movement Speed | - | (penalty) |

### 2. Leather Armor - "The Swift Hunter"
**Philosophy**: Balanced defense, crit/dodge bonuses, mobility
**Visual Theme**: Treated hides - rawhide → hardened → shadowskin
**Color Palette**: Tan/brown → dark brown → black/charcoal

| Stat Focus | Primary | Secondary |
|------------|---------|-----------|
| Defense | +++ | |
| Crit Chance | +++ | |
| Dodge Chance | ++ | |
| Movement Speed | + | |

### 3. Cloth Armor - "The Arcane Scholar"
**Philosophy**: Minimal defense, cooldown/regen bonuses, utility
**Visual Theme**: Woven fabrics - linen → wool → mystic weave
**Color Palette**: Cream/white → gray/blue → deep purple/midnight

| Stat Focus | Primary | Secondary |
|------------|---------|-----------|
| Defense | + | |
| Cooldown Reduction | +++ | |
| HP Regen | ++ | |
| Stamina Regen | ++ | |
| Movement Speed | ++ | |

---

## Tier Breakdown

### Tier 1: Levels 1-10 (Starter Zone - "The Wasteland")

**Dropped by**: Skeletons, Wolves, Zone 1 chests
**Purchased from**: Campfire Vendor (Tattered Merchant)

#### Plate: Copper Set (EXISTS)
Already implemented - serves as template.

| Slot | Item Name | STR | VIT | DEX | AGI | INT | WIS | Price |
|------|-----------|-----|-----|-----|-----|-----|-----|-------|
| Head | Copper Plate Helm | 2 | 3 | - | - | - | - | 150g |
| Chest | Copper Plate Cuirass | 3 | 5 | - | - | - | - | 250g |
| Arms | Copper Plate Bracers | 1 | 2 | - | - | - | - | 100g |
| Legs | Copper Plate Greaves | 2 | 3 | - | - | - | - | 150g |
| Feet | Copper Plate Boots | 1 | 2 | - | - | - | - | 100g |

**Full Set (5pc)**: +9 STR, +15 VIT
**Set Bonus (5pc)**: None at Tier 1

#### Leather: Rawhide Set (NEW)

| Slot | Item Name | STR | VIT | DEX | AGI | INT | WIS | Price |
|------|-----------|-----|-----|-----|-----|-----|-----|-------|
| Head | Rawhide Hood | - | 2 | 3 | 2 | - | - | 120g |
| Chest | Rawhide Vest | - | 3 | 4 | 3 | - | - | 200g |
| Arms | Rawhide Wraps | - | 1 | 2 | 1 | - | - | 80g |
| Legs | Rawhide Leggings | - | 2 | 3 | 2 | - | - | 120g |
| Feet | Rawhide Boots | - | 1 | 2 | 2 | - | - | 80g |

**Full Set (5pc)**: +9 VIT, +14 DEX, +10 AGI
**Set Bonus (5pc)**: None at Tier 1

#### Cloth: Linen Set (NEW)

| Slot | Item Name | STR | VIT | DEX | AGI | INT | WIS | Price |
|------|-----------|-----|-----|-----|-----|-----|-----|-------|
| Head | Linen Hood | - | 1 | - | - | 3 | 2 | 100g |
| Chest | Linen Robe | - | 2 | - | - | 4 | 3 | 180g |
| Arms | Linen Wrappings | - | 1 | - | - | 2 | 1 | 60g |
| Legs | Linen Trousers | - | 1 | - | - | 3 | 2 | 100g |
| Feet | Linen Sandals | - | 1 | - | - | 2 | 2 | 60g |

**Full Set (5pc)**: +6 VIT, +14 INT, +10 WIS
**Set Bonus (5pc)**: None at Tier 1

---

### Tier 2: Levels 11-20 (Mid Game - "The Cursed Lands")

**Dropped by**: Zombies, Skeletal Guardians, Elite Wolves, Zone 2 bosses
**Purchased from**: Ruins Outpost Vendor

#### Plate: Iron Set

| Slot | Item Name | STR | VIT | DEX | AGI | INT | WIS | Price |
|------|-----------|-----|-----|-----|-----|-----|-----|-------|
| Head | Iron Barbute | 3 | 5 | - | - | - | - | 450g |
| Chest | Iron Breastplate | 5 | 8 | - | - | - | - | 750g |
| Arms | Iron Vambraces | 2 | 3 | - | - | - | - | 300g |
| Legs | Iron Cuisses | 3 | 5 | - | - | - | - | 450g |
| Feet | Iron Sabatons | 2 | 4 | - | - | - | - | 300g |

**Full Set (5pc)**: +15 STR, +25 VIT
**Set Bonus (5pc)**: None at Tier 2

#### Leather: Hardened Leather Set

| Slot | Item Name | STR | VIT | DEX | AGI | INT | WIS | Price |
|------|-----------|-----|-----|-----|-----|-----|-----|-------|
| Head | Hardened Leather Cap | - | 3 | 5 | 4 | - | - | 400g |
| Chest | Hardened Leather Jerkin | - | 5 | 7 | 6 | - | - | 650g |
| Arms | Hardened Leather Bracers | - | 2 | 3 | 2 | - | - | 250g |
| Legs | Hardened Leather Pants | - | 3 | 5 | 4 | - | - | 400g |
| Feet | Hardened Leather Boots | - | 2 | 4 | 4 | - | - | 250g |

**Full Set (5pc)**: +15 VIT, +24 DEX, +20 AGI
**Set Bonus (5pc)**: None at Tier 2

#### Cloth: Wool Set

| Slot | Item Name | STR | VIT | DEX | AGI | INT | WIS | Price |
|------|-----------|-----|-----|-----|-----|-----|-----|-------|
| Head | Wool Cowl | - | 2 | - | - | 5 | 4 | 350g |
| Chest | Wool Robe | - | 3 | - | - | 7 | 6 | 600g |
| Arms | Wool Sleeves | - | 1 | - | - | 3 | 2 | 200g |
| Legs | Wool Trousers | - | 2 | - | - | 5 | 4 | 350g |
| Feet | Wool Shoes | - | 1 | - | - | 4 | 3 | 200g |

**Full Set (5pc)**: +9 VIT, +24 INT, +19 WIS
**Set Bonus (5pc)**: None at Tier 2

---

### Tier 3: Levels 21-30 (Endgame - "The Abyss")

**Dropped by**: Elite enemies, World bosses, Dungeon bosses, Zone 3-4 content
**Purchased from**: Fortress Quartermaster (high prices, requires reputation)

At Tier 3, native items gain **Set Bonuses** and **Forge Synergies** that make them competitive with and complementary to forge items.

#### Plate: Dark Steel Set

| Slot | Item Name | STR | VIT | DEX | AGI | INT | WIS | Price |
|------|-----------|-----|-----|-----|-----|-----|-----|-------|
| Head | Dark Steel Great Helm | 5 | 8 | - | - | - | - | 2000g |
| Chest | Dark Steel Plate | 8 | 13 | - | - | - | - | 3500g |
| Arms | Dark Steel Gauntlets | 3 | 5 | - | - | - | - | 1200g |
| Legs | Dark Steel Greaves | 5 | 8 | - | - | - | - | 2000g |
| Feet | Dark Steel Boots | 3 | 6 | - | - | - | - | 1200g |

**Full Set (5pc)**: +24 STR, +40 VIT
**Set Bonuses**:
- 2pc: +20 Max HP
- 4pc: +10% damage reduction when below 50% HP
- 5pc: "Ironclad" - Once per 60s, survive fatal damage at 1 HP and gain 50% damage reduction for 3s

**Forge Synergy**: When wielding a Forge weapon, +5% lifesteal

---

#### Leather: Shadowskin Set

| Slot | Item Name | STR | VIT | DEX | AGI | INT | WIS | Price |
|------|-----------|-----|-----|-----|-----|-----|-----|-------|
| Head | Shadowskin Mask | - | 4 | 7 | 5 | - | - | 1800g |
| Chest | Shadowskin Vest | - | 7 | 10 | 8 | - | - | 3200g |
| Arms | Shadowskin Bracers | - | 3 | 5 | 4 | - | - | 1100g |
| Legs | Shadowskin Leggings | - | 5 | 7 | 6 | - | - | 1800g |
| Feet | Shadowskin Boots | - | 3 | 5 | 5 | - | - | 1100g |

**Full Set (5pc)**: +22 VIT, +34 DEX, +28 AGI
**Set Bonuses**:
- 2pc: +10% Crit Damage
- 4pc: Dodging an attack grants +15% damage for 3s
- 5pc: "Shadow Strike" - Crits have 20% chance to strike twice

**Forge Synergy**: When wielding a Forge weapon, crits apply a bleed (3% max HP over 3s)

---

#### Cloth: Mystic Weave Set

| Slot | Item Name | STR | VIT | DEX | AGI | INT | WIS | Price |
|------|-----------|-----|-----|-----|-----|-----|-----|-------|
| Head | Mystic Weave Hood | - | 3 | - | - | 7 | 5 | 1600g |
| Chest | Mystic Weave Robe | - | 5 | - | - | 10 | 8 | 3000g |
| Arms | Mystic Weave Wraps | - | 2 | - | - | 5 | 4 | 1000g |
| Legs | Mystic Weave Pants | - | 3 | - | - | 7 | 5 | 1600g |
| Feet | Mystic Weave Slippers | - | 2 | - | - | 5 | 4 | 1000g |

**Full Set (5pc)**: +15 VIT, +34 INT, +26 WIS
**Set Bonuses**:
- 2pc: Abilities cost 10% less stamina
- 4pc: After using an ability, +20% move speed for 2s
- 5pc: "Arcane Surge" - Every 5th ability use has no cooldown

**Forge Synergy**: When wielding a Forge staff, +15% Staff Power (affects both damage and healing)

---

## Weapon Tiers

### Tier 1 Weapons (Level 1-10)

| Type | Name | Damage | Speed | Crit | Price | Notes |
|------|------|--------|-------|------|-------|-------|
| Sword | Rusty Blade | 8-12 | Medium | 5% | 100g | Starter |
| Mace | Morning Star | 10-14 | Slow | 7% | 0g | Free starter |
| Dagger | Chipped Dirk | 6-8 | Fast | 8% | 80g | |
| Spear | Bronze Spear | 10-14 | Medium | 5% | 150g | Reach |
| Staff | Gnarled Branch | 6-10 | Medium | 3% | 120g | Heal mode |
| Bow | Hunting Bow | 8-12 | Medium | 6% | 150g | Ranged |

### Tier 2 Weapons (Level 11-20)

| Type | Name | Damage | Speed | Crit | Price | Notes |
|------|------|--------|-------|------|-------|-------|
| Sword | Iron Longsword | 18-26 | Medium | 6% | 400g | |
| Mace | Iron Warhammer | 24-34 | Slow | 8% | 550g | Stagger |
| Dagger | Steel Stiletto | 14-18 | Fast | 10% | 350g | |
| Rapier | Silver Rapier | 16-22 | Fast | 7% | 450g | Precision |
| Spear | Iron Pike | 20-30 | Medium | 6% | 500g | Reach |
| Staff | Oak Staff | 12-18 | Medium | 4% | 400g | Better heal |
| Bow | Composite Bow | 16-24 | Medium | 8% | 500g | |

### Tier 3 Weapons (Level 21-30)

| Type | Name | Damage | Speed | Crit | Special | Price |
|------|------|--------|-------|------|---------|-------|
| Sword | Dark Steel Blade | 35-50 | Medium | 8% | +5% damage vs wounded | 1800g |
| Greatsword | Executioner's Blade | 50-70 | Slow | 10% | +15% damage below 25% HP | 2500g |
| Mace | Dreadnought Hammer | 45-65 | Slow | 12% | Stagger + armor break | 2200g |
| Dagger | Assassin's Fang | 25-35 | Fast | 15% | +20% damage from behind | 1600g |
| Rapier | Duelist's Edge | 30-42 | Fast | 12% | +10% crit after dodge | 2000g |
| Spear | Impaler Pike | 38-55 | Medium | 8% | First hit +25% damage | 2000g |
| Halberd | Warden's Halberd | 42-60 | Slow | 9% | AoE cleave | 2300g |
| Staff | Elder Oak Staff | 25-38 | Medium | 5% | +30% heal power | 1800g |
| Bow | Deadeye Longbow | 32-48 | Medium | 12% | +range, +projectile speed | 2200g |

---

## Accessory System (NEW)

Accessories provide additional customization. Players can equip 2 accessories.

### Tier 1 Accessories

| Name | Effect | Price | Drop Source |
|------|--------|-------|-------------|
| Bone Charm | +10 Max HP | 75g | Skeleton |
| Wolf Fang Necklace | +3% Crit | 100g | Wolf |
| Leather Pouch | +1 inventory slot | 150g | Vendor |
| Copper Ring | +3 Defense | 50g | Zone 1 chest |

### Tier 2 Accessories

| Name | Effect | Price | Drop Source |
|------|--------|-------|-------------|
| Zombie Eye Amulet | +5% Lifesteal | 400g | Elite Zombie |
| Guardian's Signet | +8% Block | 350g | Skeletal Guardian |
| Traveler's Boots Charm | +8% Move | 300g | Zone 2 chest |
| Hunting Horn | +10% damage to beasts | 450g | Alpha Wolf |

### Tier 3 Accessories

| Name | Effect | Price | Drop Source |
|------|--------|-------|-------------|
| Abyssal Pendant | +15% damage, -10% defense | 1500g | Abyss Boss |
| Phoenix Amulet | Death prevention (60s CD) | 2500g | World Boss |
| Titan's Belt | +10% Max HP | 1200g | Elite drop |
| Precision Gem | +10% Crit Chance | 1800g | Dungeon Boss |
| Vampiric Medallion | +8% Lifesteal | 2000g | Elite drop |
| Sprinter's Anklet | +15% Move Speed | 1000g | Zone 3 chest |

---

## Shield System

Shields work with any armor type but have synergy with Plate.

### Tier 1 Shields

| Name | Block% | Defense | Price | Notes |
|------|--------|---------|-------|-------|
| Wooden Buckler | 15% | +3 | 80g | Basic |
| Bronze Shield | 20% | +5 | 150g | |

### Tier 2 Shields

| Name | Block% | Defense | Price | Notes |
|------|--------|---------|-------|-------|
| Iron Kite Shield | 25% | +10 | 500g | |
| Tower Shield | 35% | +15 | 700g | -10% move |

### Tier 3 Shields

| Name | Block% | Defense | Special | Price |
|------|--------|---------|---------|-------|
| Dark Steel Shield | 35% | +20 | Blocks projectiles | 1500g |
| Bulwark | 45% | +25 | -15% move, reflect 10% damage | 2200g |
| Aegis | 40% | +18 | Perfect blocks heal 5% HP | 2500g |

---

## Stat System

### Base Stats from Leveling

Characters gain stats from leveling, creating meaningful progression even without gear.

```
Level 1:  10 base in all 6 stats
Per Level: +3 stat points to distribute (or auto-assign based on weapon used)
Level 30: 10 + (29 × 3) = 97 total points distributed
```

**Example Naked Level 30 Characters:**

| Build | STR | VIT | DEX | AGI | INT | WIS | Total |
|-------|-----|-----|-----|-----|-----|-----|-------|
| Heavy Weapon | 40 | 30 | 5 | 12 | 5 | 5 | 97 |
| Light Weapon | 5 | 20 | 35 | 27 | 5 | 5 | 97 |
| Staff | 5 | 15 | 5 | 5 | 40 | 27 | 97 |

This means a naked level 5 player (10 base + 12 points) feels different from a naked level 1.

### Primary Stats (On Items)

Items grant these 6 raw stats. Combined with base stats, all derived stats are calculated from totals.

| Stat | Full Name | Primary Effects | Armor Affinity |
|------|-----------|-----------------|----------------|
| **STR** | Strength | Heavy weapon damage, Block Effectiveness | Plate |
| **VIT** | Vitality | Max HP, Defense, HP Regen | Plate |
| **DEX** | Dexterity | Light weapon damage, Dodge Chance | Leather |
| **AGI** | Agility | Physical Crit %, Attack Speed, Move Speed | Leather |
| **INT** | Intellect | Staff Power (damage & healing) | Cloth |
| **WIS** | Wisdom | Staff Crit %, CDR, Stamina Regen | Cloth |

**Weapon Scaling:**

| Category | Weapons | Damage Stat | Crit Stat |
|----------|---------|-------------|-----------|
| Heavy | Sword, Axe, Mace, Hammer, Greatsword, Halberd, Spear | STR | AGI |
| Light | Dagger, Rapier, Bow, Katana, Scimitar, Saber | DEX | AGI |
| Staff | Healing Staff, Damage Staff | INT | WIS |

### Derived Stats (Calculated)

These are computed from primary stat totals:

| Derived Stat | Formula | Soft Cap |
|--------------|---------|----------|
| **Heavy Weapon Damage** | Base + (STR * 0.5) | None |
| **Light Weapon Damage** | Base + (DEX * 0.5) | None |
| **Block Chance** | 10% + (STR * 0.15%) | 60% |
| **Max HP** | 100 + (VIT * 5) | None |
| **Defense** | 10 + (VIT * 0.8) | None |
| **HP Regen** | 1 + (VIT * 0.1) per 5s | None |
| **Dodge Chance** | (DEX * 0.2%) | 40% |
| **Physical Crit %** | 5% + (AGI * 0.25%) | 50% |
| **Attack Speed** | cooldown = 1.0 / (1.0 + (AGI-10) * 0.06) | 0.05s min |
| **Move Speed** | 100% + (AGI * 0.15%) | +50% |
| **Staff Power** | 100% + (INT * 0.5%) | None |
| **Staff Crit %** | 5% + (WIS * 0.25%) | 50% |
| **Cooldown Reduction** | (WIS * 0.2%) | 50% |
| **Stamina Regen** | 100% + (WIS * 0.3%) | +100% |

### Example Characters (Level 30 with T3 Armor)

**Plate User (Heavy Weapon) - Dark Steel Set**
```
Base Stats (Level 30):  40 STR, 30 VIT, 5 DEX, 12 AGI, 5 INT, 5 WIS
T3 Armor Bonus:        +24 STR, +40 VIT
─────────────────────────────────────────────────────────────────
Total Raw Stats:        64 STR, 70 VIT, 5 DEX, 12 AGI, 5 INT, 5 WIS

Derived:
├── Heavy Weapon Damage: +32 (64 × 0.5)
├── Block Chance: 19.6% (10% + 64 × 0.15%)
├── Max HP: 450 (100 + 70 × 5)
├── Defense: 66 (10 + 70 × 0.8)
├── Physical Crit: 8% (5% + 12 × 0.25%)
├── Attack Speed: +2.4% (12 × 0.2%)
└── Move Speed: +1.8% (12 × 0.15%)
```

**Leather User (Light Weapon) - Shadowskin Set**
```
Base Stats (Level 30):  5 STR, 20 VIT, 35 DEX, 27 AGI, 5 INT, 5 WIS
T3 Armor Bonus:        +22 VIT, +34 DEX, +28 AGI
─────────────────────────────────────────────────────────────────
Total Raw Stats:        5 STR, 42 VIT, 69 DEX, 55 AGI, 5 INT, 5 WIS

Derived:
├── Light Weapon Damage: +34.5 (69 × 0.5)
├── Dodge Chance: 13.8% (69 × 0.2%)
├── Max HP: 310 (100 + 42 × 5)
├── Defense: 43.6 (10 + 42 × 0.8)
├── Physical Crit: 18.75% (5% + 55 × 0.25%)
├── Attack Speed: +11% (55 × 0.2%)
└── Move Speed: +8.25% (55 × 0.15%)
```

**Cloth User (Staff) - Mystic Weave Set**
```
Base Stats (Level 30):  5 STR, 15 VIT, 5 DEX, 5 AGI, 40 INT, 27 WIS
T3 Armor Bonus:        +15 VIT, +34 INT, +26 WIS
─────────────────────────────────────────────────────────────────
Total Raw Stats:        5 STR, 30 VIT, 5 DEX, 5 AGI, 74 INT, 53 WIS

Derived:
├── Staff Power: +37% (74 × 0.5%)
├── Staff Crit: 18.25% (5% + 53 × 0.25%)
├── Max HP: 250 (100 + 30 × 5)
├── Defense: 34 (10 + 30 × 0.8)
├── CDR: 10.6% (53 × 0.2%)
└── Stamina Regen: +15.9% (53 × 0.3%)
```

### Damage/Healing Formulas

```python
# Heavy weapon damage (sword, axe, mace, hammer, etc.)
base_damage = weapon_damage + (STR * 0.5)
is_crit = random() < physical_crit_chance  # from AGI
crit_mult = 1.5 + (AGI * 0.005)  # Base 150%, +0.5% per AGI
damage = base_damage * (crit_mult if is_crit else 1.0)

# Light weapon damage (dagger, rapier, bow, katana, etc.)
base_damage = weapon_damage + (DEX * 0.5)
is_crit = random() < physical_crit_chance  # from AGI
crit_mult = 1.5 + (AGI * 0.005)  # Base 150%, +0.5% per AGI
damage = base_damage * (crit_mult if is_crit else 1.0)

# Staff damage or healing
staff_base = staff_power  # Base heal/damage from weapon
staff_mult = 1.0 + (INT * 0.005)  # +0.5% per INT
is_crit = random() < staff_crit_chance  # from WIS
crit_mult = 1.5 + (WIS * 0.005)  # Base 150%, +0.5% per WIS
final_staff_output = staff_base * staff_mult * (crit_mult if is_crit else 1.0)

# Defense mitigation (applies to damage, not healing)
mitigation = target_defense / (100 + target_defense)
final_damage = damage * (1 - mitigation)
```

---

## Visual Design Guidelines

### Color Philosophy

```
FORGE ITEMS (Achievement-based):
- Gold, white, silver, light blue
- Glowing effects, ethereal particles
- "Blessed" / "Divine" aesthetic

NATIVE ITEMS (In-game drops):
- Earth tones: brown, gray, rust, black
- Weathered, battle-worn appearance
- "Practical" / "Veteran" aesthetic
```

### Tier Color Schemes

#### Plate Armor

| Tier | Primary | Accent | Metal Type |
|------|---------|--------|------------|
| 1 | Copper (#B87333) | Bronze (#CD7F32) | Warm, new |
| 2 | Iron Gray (#48494B) | Silver (#C0C0C0) | Cool, worn |
| 3 | Dark Steel (#2F4F4F) | Gunmetal (#536878) | Dark, veteran |

#### Leather Armor

| Tier | Primary | Accent | Leather Type |
|------|---------|--------|--------------|
| 1 | Tan (#D2B48C) | Light Brown (#A0522D) | Fresh rawhide |
| 2 | Dark Brown (#5C4033) | Rust (#8B4513) | Treated leather |
| 3 | Black (#1C1C1C) | Charcoal (#36454F) | Shadow-treated |

#### Cloth Armor

| Tier | Primary | Accent | Fabric Type |
|------|---------|--------|-------------|
| 1 | Cream (#FFFDD0) | White (#F5F5F5) | Simple linen |
| 2 | Gray (#808080) | Blue-gray (#6699CC) | Dyed wool |
| 3 | Deep Purple (#301934) | Midnight (#191970) | Enchanted weave |

---

## Economy Balance

### Gold Acquisition Rates

| Activity | Gold/Hour (Level 10) | Gold/Hour (Level 20) | Gold/Hour (Level 30) |
|----------|---------------------|---------------------|---------------------|
| Farming mobs | 100-150g | 300-400g | 600-800g |
| Dungeon runs | 200-300g | 500-700g | 1000-1500g |
| Boss kills | 50-100g | 150-300g | 400-800g |
| Quests | 100-200g | 300-500g | 500-1000g |

### Time to Full Tier Set

| Tier | Total Cost (Armor) | Time to Acquire |
|------|-------------------|-----------------|
| Tier 1 | ~750g | 3-5 hours |
| Tier 2 | ~2,250g | 5-8 hours |
| Tier 3 | ~10,000g | 15-25 hours |

---

## Forge Interaction System

### Synergy Mechanics

At Tier 3, native armor sets gain bonuses when combined with forge items:

```
FORGEBOUND MECHANIC:
When wearing 3+ pieces of Tier 3 native armor AND wielding a Forge weapon:
├── Plate: +5% lifesteal (survivability synergy)
├── Leather: Crits apply bleed (damage synergy)
└── Cloth: +15% Staff Power (amplifies staff damage AND healing)
```

### Why This Works

1. **Forge items remain valuable** - they unlock the synergy
2. **Native items remain valuable** - they provide the bonus
3. **Neither obsoletes the other** - optimal builds use both
4. **Creates meaningful choice** - 3 distinct build paths

### Example Endgame Builds

**"Iron Vampire" (Plate + Forge)**
- 5pc Dark Steel Armor (Ironclad set bonus)
- Hand of Malenia (3% lifesteal + Waterfowl Dance)
- Dark Steel Shield (35% block)
- Combined: 8% lifesteal, Ironclad survival, massive defense

**"Shadow Assassin" (Leather + Forge)**
- 5pc Shadowskin Armor (Shadow Strike double-crit)
- Mortal Blade (Execute damage + Mortal Draw)
- No shield (mobility focus)
- Combined: 38% crit + bleed + execute for burst damage

**"Arcane Caster" (Cloth + Forge Staff)**
- 5pc Mystic Weave (Arcane Surge no-cooldown)
- Forge Damage Staff or Healing Staff
- Sprinter's Anklet accessory
- Combined: Ultra-mobile staff spam with +15% Staff Power boost

---

## Implementation Priority

### Phase 1: Tier 1 Completion
- [x] Copper Plate Set (exists)
- [ ] Rawhide Leather Set (new sprites needed)
- [ ] Linen Cloth Set (new sprites needed)
- [ ] Tier 1 weapons variety
- [ ] Tier 1 accessories

### Phase 2: Tier 2 Introduction
- [ ] Iron Plate Set
- [ ] Hardened Leather Set
- [ ] Wool Cloth Set
- [ ] Tier 2 weapons
- [ ] Tier 2 accessories
- [ ] Shield system

### Phase 3: Tier 3 & Endgame
- [ ] Dark Steel Plate Set + set bonuses
- [ ] Shadowskin Leather Set + set bonuses
- [ ] Mystic Weave Cloth Set + set bonuses
- [ ] Tier 3 weapons with specials
- [ ] Tier 3 accessories
- [ ] Forge synergy system
- [ ] Tier 3 shields

---

## Technical Implementation

### Item Data Structure

```json
{
  "item_id": "dark_steel_plate",
  "name": "Dark Steel Plate",
  "type": "armor",
  "slot": "chest",
  "tier": 3,
  "required_level": 21,
  "rarity": "epic",
  "stats": {
    "str": 8,
    "vit": 13,
    "dex": 0,
    "agi": 0,
    "int": 0,
    "wis": 0
  },
  "set_id": "dark_steel",
  "sprite_name": "dark_steel_plate",
  "price": 3500,
  "description": "Forged in the depths of the Abyss, this armor has witnessed countless battles.",
  "flavor_text": "\"The darkness is not your enemy. It is your shield.\" - Unknown Knight"
}
```

### Set Bonus System

```gdscript
# SetBonusManager.gd
func calculate_set_bonuses(equipped_items: Dictionary) -> Dictionary:
    var bonuses = {}
    var set_counts = {}

    # Count pieces per set
    for slot in equipped_items:
        var item = equipped_items[slot]
        if item and item.has("set_id"):
            var set_id = item.set_id
            set_counts[set_id] = set_counts.get(set_id, 0) + 1

    # Apply bonuses based on piece count
    for set_id in set_counts:
        var count = set_counts[set_id]
        var set_data = SET_DEFINITIONS[set_id]

        if count >= 2 and set_data.has("2pc"):
            bonuses.merge(set_data["2pc"])
        if count >= 4 and set_data.has("4pc"):
            bonuses.merge(set_data["4pc"])
        if count >= 5 and set_data.has("5pc"):
            bonuses.merge(set_data["5pc"])

    return bonuses
```

---

## Sprite Asset Requirements

### New Sprites Needed

| Set | Slots | Animations | Gender | Priority |
|-----|-------|------------|--------|----------|
| Rawhide | 5 | walk, slash, hurt, shoot | M/F | High |
| Linen | 5 | walk, slash, hurt, shoot | M/F | High |
| Iron Plate | 5 | walk, slash, hurt, shoot | M/F | Medium |
| Hardened Leather | 5 | walk, slash, hurt, shoot | M/F | Medium |
| Wool | 5 | walk, slash, hurt, shoot | M/F | Medium |
| Dark Steel | 5 | walk, slash, hurt, shoot | M/F | Low |
| Shadowskin | 5 | walk, slash, hurt, shoot | M/F | Low |
| Mystic Weave | 5 | walk, slash, hurt, shoot | M/F | Low |

### LPC Generator Settings

**Rawhide Leather:**
- Torso: Leather vest (brown/tan)
- Legs: Leather pants (brown)
- Feet: Leather boots (brown)
- Arms: Leather bracers (optional)
- Head: Leather hood/cap

**Linen Cloth:**
- Torso: Robe (cream/white)
- Legs: Cloth pants (white)
- Feet: Sandals/simple shoes
- Arms: Wrapped cloth
- Head: Simple hood (white)

---

## Related Documents

- `FORGE_ITEM_PHILOSOPHY.md` - Forge item design principles
- `FORGE_ITEM_EFFECTS.md` - Effect system specifications
- `LPC_GUIDE.md` - Sprite creation guide
- `COMBAT_SYSTEMS.md` - Combat mechanics

---

## Version History

- v1.0 (2024-12) - Initial native itemization design
- v1.1 (2024-12) - Added 4 class identities (Tank, DPS, Healer, Support) and 3 player archetypes (Whales, Grinders, Normies)
