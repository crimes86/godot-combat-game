# TTK Balance Issue - Enemies Dying Too Fast

I'm finding that enemies die too quickly, especially once I land a weakpoint hit. One weakpoint nearly kills a level 1 enemy.

## Current balance values in `scripts/constants.gd`:
- `ENEMY_BASE_HEALTH = 60.0` (level 1 enemy HP)
- `ENEMY_HEALTH_SCALING = 1.12` (12% per level)
- `CRIT_DAMAGE_MULTIPLIER = 1.5` (weakpoint damage multiplier)
- `TTK_WINDOWS_TRASH = 2` (design: trash mobs should take 2 perfect crit windows)

## Weakpoint mechanics in `scripts/enemies/weakpoint.gd`:
- Line 184: `max_hits = randi_range(3, 5)` (3-5 clicks to destroy one weakpoint)
- Level 1-10 players get 1 weakpoint per crit window

## Player damage in `scripts/systems/CharacterStats.gd` `get_base_damage()`:
- Level 1 with starter sword (~5 weapon damage): approximately 6 total damage

## The problem:
- One weakpoint = 4 hits avg × 6 dmg × 1.5 crit = 36 damage
- 36 / 60 HP = **60% of enemy HP from one weakpoint**
- Design says 2 windows to kill, but 1 weakpoint nearly kills them

## Options:
1. Increase `ENEMY_BASE_HEALTH` from 60 to 85-100
2. Reduce `CRIT_DAMAGE_MULTIPLIER` from 1.5 to 1.25
3. Reduce weakpoint `max_hits` from 3-5 to 2-3
4. Combination approach

Help me tune this so enemies reliably survive 2 crit windows as designed.
