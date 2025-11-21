# Campfire System - Crit Chance & Healing Buff Tuning

## Current Level 10 Stats

### Base Stats (Level 10)
- **LUCK**: 19 (10 starting + 9 from leveling)
- **Base Crit from LUCK**: 6.4% (formula: 1% + (LUCK - 10) * 0.6%)

### Common Level 10 Weapons
- Iron Short Sword (150g): +7.1% crit
- Bone Mace (180g): +7.1% crit
- Bronze Spear (250g): +7.1% crit

### **TOTAL CURRENT CRIT: 13.5%** (6.4% base + 7.1% weapon)
- This means **~1 crit every 7-8 attacks**
- Feels: Infrequent crit windows, low rhythm

---

## Proposed Campfire Buff System

### Design Goals
1. **Without campfire**: 13.5% crit feels "lackluster" ✓ (already there)
2. **With campfire (max bone chips)**: Noticeably better, frequent crit windows
3. **Scalable**: Works for level 10, 20, 30+ spots

### Target Crit Chances

| Buff Level | Crit Chance | Attacks Per Crit | Feel |
|-----------|-------------|------------------|------|
| **No Campfire** | 13.5% | ~7-8 attacks | Lackluster, slow rhythm |
| **Low Bone Chips (25%)** | 17% | ~6 attacks | Slightly better |
| **Medium Bone Chips (50%)** | 21% | ~5 attacks | Noticeable improvement |
| **High Bone Chips (75%)** | 25% | ~4 attacks | Strong rhythm |
| **Max Bone Chips (100%)** | 30% | ~3-4 attacks | Excellent farming spot |

### Proposed Buff Values
- **Max Crit Buff**: +16.5% (brings 13.5% → 30%)
- **Scaling**: Linear from 0 to +16.5% based on bone chips added
- **Max Bone Chips**: 100 chips = full buff (players will farm this)

---

## Healing Buff System

### Current Campfire Healing
- Base: 5 HP/second
- Range: 150px radius

### Proposed Scaling
| Buff Level | Healing Power | Feel |
|-----------|--------------|------|
| **No Wood** | 5 HP/s | Base (current) |
| **Low Wood (25%)** | 8 HP/s | Slightly better |
| **Medium Wood (50%)** | 12 HP/s | Noticeable |
| **High Wood (75%)** | 17 HP/s | Strong |
| **Max Wood (100%)** | 25 HP/s | Almost unkillable |

- **Max Heal Buff**: +20 HP/s (brings 5 → 25 HP/s)
- **Scaling**: Linear from 0 to +20 based on wood logs added
- **Max Wood Logs**: 50 logs = full buff

---

## Resource Sources

### Wood Logs (for Healing)
- **Source**: Chopping down trees
- **Drop**: 1-3 logs per tree (already implemented)
- **Respawn**: 120 seconds

### Bone Chips (for Crit Chance)
- **Source**: Looting skeleton corpses
- **Drop**: NEW - Add to loot table
- **Drop Rate**: 40-60% chance, 1-2 chips per skeleton

---

## Implementation Phases

### Phase 1: Resource Items (CURRENT)
- [x] Add "Bone Chips" item to skeleton loot tables
- [x] Verify "Dry Log" is in inventory system

### Phase 2: Campfire Interaction System
- [ ] Add F-key interaction to campfires
- [ ] Create fuel UI (show current wood/bone chips)
- [ ] Track fuel levels (wood_count, bone_chips_count)
- [ ] Add fuel from inventory

### Phase 3: Buff Auras
- [ ] Healing buff scales with wood_count
- [ ] Crit chance buff scales with bone_chips_count
- [ ] Apply buffs to player when in range
- [ ] Visual indicators (bigger flames, brighter coals)

### Phase 4: Scalability
- [ ] Define level 20 tuning targets
- [ ] Define level 30 tuning targets
- [ ] Make buff calculations scale with player level

---

## Bone Chip Lore/Design Question

**Question**: Do bones need refining to burn, or can raw bone chips work as fuel?

**Proposal**: **Raw bone chips work as-is**
- Lore: "The ancient magic of the wasteland causes bones to burn with supernatural heat"
- Bones produce "ember heat" and "ghostly coals" that radiate combat energy
- Visual: White/blue ghostly embers mixed with orange coals
- This keeps the system simple (no refining step)

**Alternative**: Add refining step
- Craft "Bone Charcoal" from 5 bone chips
- More realistic but adds complexity

**Recommendation**: Keep it simple - raw bone chips generate ghostly heat/coals for crit buff

---

## End Game Vision (Level 30)

At max level with best gear:
- **Base Crit**: ~20%
- **Max Campfire Buff**: +20% (scaled from level 10's +16.5%)
- **Total**: 40% crit chance
- **Result**: Nearly constant crit windows with 1-2 second pauses
- **Kill Rate Limited By**: Click rate on weakpoints + gear quality

---

## Tuning Notes

### Why Lower Base Crit?
Current 13.5% already feels lackluster without buffs, which is perfect. No base changes needed.

### Why +16.5% Max Buff?
- 30% total crit = 1 crit every ~3 attacks
- Feels like "excellent farming spot" rhythm
- Not too overpowered (still need skill for weakpoints)
- Leaves room for scaling at higher levels

### Why 100 Bone Chips for Max?
- Ruins guardians: 8 skeletons constantly respawning
- At 50% drop rate, 1-2 chips each = ~10 chips per clear
- 100 chips = ~10 full clears = reasonable grind
- Encourages staying and farming the spot
