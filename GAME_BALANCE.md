# Game Balance Design Document

## Combat & Weapon System

### Attack Speed & Crit Chance Balance

**CRITICAL DESIGN RULE:** All weapon types achieve equal DPS and equal crit window frequency through inverse scaling.

**Attack Speed Multipliers (at max level AGI):**

| Speed | Attack Multiplier | Damage Scaling | Crit Chance | Weapon Types |
|-------|------------------|----------------|-------------|--------------|
| **Fast** | 1.43x attacks | 1.0x damage | 5.0% | Dagger, Rapier |
| **Medium** | 1.0x attacks | 1.43x damage | 7.1% | Sword, Mace, Spear |
| **Slow** | 0.77x attacks | 1.86x damage | 9.3% | Warhammer, 2H weapons |

**Balance Formula:**
- Attack speed bonus: -30% (fast), 0% (medium), +30% (slow)
- Cooldown multiplier: 0.7 (fast), 1.0 (medium), 1.3 (slow)
- Attack rate multiplier: 1.43x (fast), 1.0x (medium), 0.77x (slow)
- For equal DPS: Damage × Attack Rate = Constant
- For equal crit windows: Crit% × Attack Rate = Constant

**Proof of Balance (Zone 2 weapons at max level):**
```
Fast (Rapier):    18 dmg × 1.43 = 25.7 DPS | 5.0% × 1.43 = 0.0715 crit/sec
Medium (Longsword): 26 dmg × 1.0 = 26.0 DPS | 7.1% × 1.0 = 0.071 crit/sec
Slow (Warhammer):  34 dmg × 0.77 = 26.2 DPS | 9.3% × 0.77 = 0.072 crit/sec
```

**Design Philosophy:**
- Fast weapons hit attack speed cap at max level + gear
- Medium/slow weapons attack naturally slower
- ALL weapon types produce equal DPS and crit opportunities
- Player choice is based on gameplay feel, not min/max optimization

---

## Economy & Gold Progression

### Enemy Gold Drops

| Zone | Enemy Type | Gold Per Kill | Notes |
|------|-----------|---------------|-------|
| Zone 1: Ruins | Skeleton Lv1 | 1-3g (avg 2g) | Base enemy |
| Zone 1: Ruins | Skeleton Lv3 | 2-5g (avg 3.5g) | Slightly stronger |
| Zone 2: Cursed | Zombie Lv5 | 5-10g (avg 7.5g) | Tougher enemies |
| Zone 3: Shadow | Elite Enemy | 15-25g (avg 20g) | High-tier content |
| Zone 4: Abyss | Boss/Mini-boss | 50-100g | Endgame content |

### Gold Accumulation Rate

**Zone 1 Grinding (1-2 hours):**
- Combat encounters: 80-160 (@ 45s per encounter)
- Average gold earned: 160-320g
- **Design Goal:** Player can buy 2-3 weapons to experiment with different types

**Zone 2 Grinding (1-2 hours):**
- Combat encounters: 60-120 (@ 60s per encounter, harder enemies)
- Average gold earned: 450-900g
- **Design Goal:** Player can upgrade 1-2 armor pieces or buy mid-tier weapon

**Zone 3 Grinding (1-2 hours):**
- Combat encounters: 40-80 (@ 90s per encounter, difficult content)
- Average gold earned: 800-1600g
- **Design Goal:** Player can afford 1 high-tier weapon or armor piece

---

## Weapon Pricing Strategy

### Zone 1: The Wasteland (Blacksmith Vendor)

| Weapon | Price | Attack Speed | Base Damage | DPS | Crit % | Rarity |
|--------|-------|--------------|-------------|-----|--------|--------|
| Wooden Club | 0g (starter) | Medium | 4 | 4.0 | 7.1% | Common |
| Rusty Dagger | 50g | Fast | 8 | 11.4 | 5.0% | Common |
| Iron Short Sword | 150g | Medium | 12 | 12.0 | 7.1% | Common |
| Bone Mace | 180g | Medium | 12 | 12.0 | 7.1% | Common |
| Bronze Spear | 250g | Medium | 12 | 12.0 | 7.1% | Uncommon |

**Rationale:**
- Free starter (club) - intentionally weak (4 DPS) to encourage first upgrade
- Budget option (dagger, 50g) - 11.4 DPS
- Standard weapons (150-250g) - ALL balanced at 12.0 DPS
- After 1-2hr grinding (160-320g), player can buy 2-3 weapons to test
- All non-starter weapons are balanced - choice is about gameplay feel, not power

### Zone 2: Cursed Lands Vendor

| Weapon | Price | Attack Speed | Base Damage | DPS | Crit % | Rarity |
|--------|-------|--------------|-------------|-----|--------|--------|
| Steel Longsword | 400g | Medium | 26 | 26.0 | 7.1% | Uncommon |
| Iron Warhammer | 550g | Slow | 34 | 26.2 | 9.3% | Uncommon |
| Silver Rapier | 650g | Fast | 18 | 25.7 | 5.0% | Uncommon |

**Rationale:**
- Mid-tier pricing (400-650g)
- ALL weapons balanced at ~26 DPS
- After Zone 2 grinding (450-900g), can buy 1-2 weapons
- Perfect balance: choice is gameplay feel (fast attacks vs heavy hits), not power

### Zone 3: Shadow Realm Vendor

| Weapon | Price | Attack Speed | Base Damage | Crit % | Rarity |
|--------|-------|--------------|-------------|--------|--------|
| Darksteel Greatsword | 1000g | Slow | 32 | 18% | Rare |
| Shadow Dagger | 900g | Fast | 28 | 5% | Rare |
| Obsidian Spear | 1200g | Medium | 35 | 10% | Rare |

**Rationale:**
- High-tier pricing (900-1200g)
- After Zone 3 grinding (800-1600g), can buy 1 weapon

### Zone 4: The Abyss (Legendary Drops Only)

| Weapon | Acquisition | Attack Speed | Base Damage | Crit % | Rarity |
|--------|------------|--------------|-------------|--------|--------|
| Glowsword (Blue) | Boss drop | Fast | 45 | 8% | Legendary |
| Glowsword (Red) | Boss drop | Fast | 48 | 8% | Legendary |
| Abyssal Greathammer | Elite drop | Slow | 55 | 20% | Legendary |

**Rationale:**
- NOT sold in shops
- Exclusive boss/elite drops for prestige
- Slightly higher crit than base fast weapons (8% vs 5%) for legendary feel

---

## Armor Pricing (Reference)

| Zone | Slot | Defense | Price | Gold Ratio |
|------|------|---------|-------|------------|
| Zone 1 | Head | 8 | 100g | ~50 kills |
| Zone 1 | Chest | 12 | 150g | ~75 kills |
| Zone 1 | Full Set | 41 total | 550g | ~275 kills |
| Zone 2 | Full Set | 70 total | 1400g | ~180 kills |
| Zone 3 | Full Set | 100 total | 1320g | ~66 kills |
| Zone 4 | Full Set | 142 total | 4400g | ~50-88 kills |

---

## Damage Type System

**CURRENT:** Unified damage (no slash/pierce/blunt distinctions)
**FUTURE:** Extensible to add damage types if needed

**Reasoning:**
- Simplicity for initial launch
- Weapon choice based on attack speed preference, not type effectiveness
- Easy to expand later with enemy resistances/weaknesses

---

## Weapon Switching System

**Design Goal:** Players carry multiple weapon types and switch mid-combat

**Implementation Ideas:**
- Hotkey system (1, 2, 3, 4 for weapon slots)
- Quick-swap animation (0.5s delay to prevent spam)
- Visual indicator of equipped weapon on character
- Each weapon type feels different through attack speed and crit frequency

**Balancing Consideration:**
- No penalty for switching weapons
- Encourages experimentation
- Players find their preferred playstyle naturally

---

## Future Expansion Notes

### Potential Attack Speed Refinements
- Could add weapon-specific crit window sizes
- Faster weapons = smaller windows (harder to hit)
- Slower weapons = larger windows (easier to hit, but less frequent)

### Potential Damage Type System
- Fire/Ice/Lightning elemental damage
- Enemy resistances/weaknesses
- Weapon enchantments

### Potential Weapon Special Abilities
- Warhammer: Stun chance
- Spear: Armor penetration
- Dagger: Backstab bonus
- Would need careful balancing to not overshadow attack speed differences

---

## Key Takeaways

1. **Crit chance MUST inversely scale with attack speed** - This is critical for balance
2. **Weapon pricing matches 1-2hr grind sessions** - Player progression feels rewarding
3. **Multiple weapons per zone** - Encourages experimentation
4. **Unified damage for simplicity** - Can expand later
5. **Zone 4 legendaries are drops only** - Prestige and excitement
