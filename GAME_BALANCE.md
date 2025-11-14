# Game Balance Design Document

## Combat & Weapon System

### Attack Speed & Crit Chance Balance

**CRITICAL DESIGN RULE:** Crit chance MUST scale inversely with attack speed to prevent fast weapons from dominating through crit window frequency.

**Attack Speed Categories:**

| Speed | Attack Multiplier | Crit Chance | Weapon Types | Gameplay Feel |
|-------|------------------|-------------|--------------|---------------|
| **Fast** | 1.5x attacks/min | 5% | Dagger, Rapier | Constant rhythm, rare crits |
| **Medium** | 1.0x attacks/min | 10% | Sword, Mace, Spear | Balanced, standard feel |
| **Slow** | 0.7x attacks/min | 15-20% | Warhammer, 2H weapons | Deliberate strikes, frequent crits |

**Why This Matters:**
- Fast weapon at 5% crit × 1.5 attacks = 0.075 crit opportunities/min
- Medium weapon at 10% crit × 1.0 attacks = 0.10 crit opportunities/min
- Slow weapon at 15% crit × 0.7 attacks = 0.105 crit opportunities/min

This keeps all weapon types viable while providing different gameplay experiences.

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

| Weapon | Price | Attack Speed | Base Damage | Crit % | Rarity |
|--------|-------|--------------|-------------|--------|--------|
| Wooden Club | 0g (starter) | Medium | 4 | 10% | Common |
| Rusty Dagger | 50g | Fast | 6 | 5% | Common |
| Iron Short Sword | 150g | Medium | 8 | 10% | Common |
| Bone Mace | 180g | Medium | 10 | 10% | Common |
| Bronze Spear | 250g | Medium | 12 | 10% | Uncommon |

**Rationale:**
- Free starter (club)
- Budget option (dagger, 50g)
- 2-3 standard weapons (150-250g range)
- After 1-2hr grinding (160-320g), player can buy 2-3 weapons to test

### Zone 2: Cursed Lands Vendor

| Weapon | Price | Attack Speed | Base Damage | Crit % | Rarity |
|--------|-------|--------------|-------------|--------|--------|
| Steel Longsword | 400g | Medium | 18 | 10% | Uncommon |
| Iron Warhammer | 550g | Slow | 22 | 15% | Uncommon |
| Silver Rapier | 650g | Fast | 20 | 5% | Uncommon |

**Rationale:**
- Mid-tier pricing (400-650g)
- After Zone 2 grinding (450-900g), can buy 1-2 weapons

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
