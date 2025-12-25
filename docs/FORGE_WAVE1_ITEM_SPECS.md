# Wave 1: Armor Feet & Legs Item Specifications

**Created**: 2025-12-25
**Items**: 20 new items (10 Feet, 10 Legs)
**Provider Balance**: Steam (5), PlayStation (5), Xbox (5), Battle.net (5)
**Rarity Target**: 4 Legendary, 10 Epic, 6 Rare

---

## Design Philosophy

### Provider Balance First
Each provider gets equal representation to ensure diverse achievement sources.

### Game Diversity Second
Prioritize games with only 1 item currently (underrepresented).

### Achievement-to-Slot Fantasy
- **Feet**: Movement, exploration, traversal achievements
- **Legs**: Survival, endurance, completion achievements

---

## Steam Items (5)

### 1. Apex Predator Boots (apex_predator_boots)
```json
{
  "item_id": "apex_predator_boots",
  "item_name": "Apex Predator Boots",
  "item_type": "armor_feet",
  "description": "Boots of the apex of the apex.",
  "lore": "You've climbed to the very top of the food chain.",
  "base_rarity": "epic",
  "theme": "apex_legends",
  "achievement_mapping": "1172470:APEX_PREDATOR_RANK",
  "visuals": {
    "icon_url": "/static/items/icons/apex_predator_boots.png",
    "sprite_folder": "armor/feet/apex_predator",
    "effect": "predator_aura",
    "glow_color": "#FF0000"
  },
  "effects": {
    "passive": ["move_speed", "crit_chance"],
    "active": null
  },
  "defense": 14,
  "stat_bonuses": {"str": 0, "agi": 5, "dex": 4, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Reached the highest competitive rank - apex movement

---

### 2. Portal Longfall Boots (portal_longfall_boots)
```json
{
  "item_id": "portal_longfall_boots",
  "item_name": "Portal Longfall Boots",
  "item_type": "armor_feet",
  "description": "Aperture Science spring-loaded boots.",
  "lore": "Now you're thinking with portals.",
  "base_rarity": "epic",
  "theme": "portal",
  "achievement_mapping": "620:PORTAL_ADVANCED_CHAMBERS",
  "visuals": {
    "icon_url": "/static/items/icons/portal_longfall_boots.png",
    "sprite_folder": "armor/feet/portal_longfall",
    "effect": "portal_energy",
    "glow_color": "#FF8C00"
  },
  "effects": {
    "passive": ["damage_reduction"],
    "active": null
  },
  "defense": 12,
  "stat_bonuses": {"str": 0, "agi": 3, "dex": 0, "int": 4, "wis": 0, "vit": 2}
}
```
**Fantasy**: Mastered the advanced test chambers - fall damage immunity

---

### 3. Cuphead's Dancing Shoes (cuphead_dancing_shoes)
```json
{
  "item_id": "cuphead_dancing_shoes",
  "item_name": "Cuphead's Dancing Shoes",
  "item_type": "armor_feet",
  "description": "Cartoon shoes with that rubberhose bounce.",
  "lore": "A great slam and then some!",
  "base_rarity": "legendary",
  "theme": "cuphead",
  "achievement_mapping": "268910:BEAT_DEVIL_EXPERT_SRANK",
  "visuals": {
    "icon_url": "/static/items/icons/cuphead_dancing_shoes.png",
    "sprite_folder": "armor/feet/cuphead",
    "effect": "rubberhose_bounce",
    "glow_color": "#DC143C"
  },
  "effects": {
    "passive": ["move_speed", "crit_chance"],
    "active": null
  },
  "defense": 10,
  "stat_bonuses": {"str": 0, "agi": 6, "dex": 5, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: S-ranked the Devil on Expert - cartoon mastery

---

### 4. Mountaineer's Trousers (mountaineer_trousers)
```json
{
  "item_id": "mountaineer_trousers",
  "item_name": "Mountaineer's Trousers",
  "item_type": "armor_legs",
  "description": "Climbing pants that have seen the summit.",
  "lore": "You can do this.",
  "base_rarity": "epic",
  "theme": "celeste",
  "achievement_mapping": "504230:C_SIDES_COMPLETE",
  "visuals": {
    "icon_url": "/static/items/icons/mountaineer_trousers.png",
    "sprite_folder": "armor/legs/mountaineer",
    "effect": "dash_trail",
    "glow_color": "#E85D8C"
  },
  "effects": {
    "passive": ["stamina_regen"],
    "active": null
  },
  "defense": 11,
  "stat_bonuses": {"str": 0, "agi": 5, "dex": 3, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Completed all C-sides - climbing endurance

---

### 5. Survivor's Pants (survivor_pants)
```json
{
  "item_id": "survivor_pants",
  "item_name": "Survivor's Pants",
  "item_type": "armor_legs",
  "description": "Tattered pants infused with cell mutation.",
  "lore": "Death is not the end.",
  "base_rarity": "legendary",
  "theme": "dead_cells",
  "achievement_mapping": "588650:FIVE_BOSS_CELLS",
  "visuals": {
    "icon_url": "/static/items/icons/survivor_pants.png",
    "sprite_folder": "armor/legs/survivor",
    "effect": "cell_mutation",
    "glow_color": "#00FF00"
  },
  "effects": {
    "passive": ["death_prevention"],
    "active": null
  },
  "defense": 13,
  "stat_bonuses": {"str": 0, "agi": 4, "dex": 4, "int": 0, "wis": 0, "vit": 5}
}
```
**Fantasy**: Reached 5 Boss Cells - ultimate survival

---

## PlayStation Items (5)

### 6. Hunter's Boots (hunter_boots)
```json
{
  "item_id": "hunter_boots",
  "item_name": "Hunter's Boots",
  "item_type": "armor_feet",
  "description": "Victorian boots stained with beast blood.",
  "lore": "A hunter must hunt.",
  "base_rarity": "epic",
  "theme": "bloodborne",
  "achievement_mapping": "psn:BLOODBORNE_CHALICE_DUNGEONS",
  "visuals": {
    "icon_url": "/static/items/icons/hunter_boots.png",
    "sprite_folder": "armor/feet/hunter",
    "effect": "blood_splatter",
    "glow_color": "#8B0000"
  },
  "effects": {
    "passive": ["lifesteal"],
    "active": null
  },
  "defense": 13,
  "stat_bonuses": {"str": 3, "agi": 4, "dex": 2, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Conquered all Chalice Dungeons - hunter's journey

---

### 7. Aloy's Strider Boots (aloy_strider_boots)
```json
{
  "item_id": "aloy_strider_boots",
  "item_name": "Aloy's Strider Boots",
  "item_type": "armor_feet",
  "description": "Tribal boots with machine components.",
  "lore": "Machines can be tamed.",
  "base_rarity": "rare",
  "theme": "horizon",
  "achievement_mapping": "psn:HORIZON_ZERO_DAWN_PLATINUM",
  "visuals": {
    "icon_url": "/static/items/icons/aloy_strider_boots.png",
    "sprite_folder": "armor/feet/aloy",
    "effect": "focus_scan",
    "glow_color": "#4169E1"
  },
  "effects": {
    "passive": ["move_speed"],
    "active": null
  },
  "defense": 10,
  "stat_bonuses": {"str": 0, "agi": 3, "dex": 3, "int": 0, "wis": 2, "vit": 0}
}
```
**Fantasy**: Platinum trophy - explored every horizon

---

### 8. Berserker Tassets (berserker_tassets)
```json
{
  "item_id": "berserker_tassets",
  "item_name": "Berserker Tassets",
  "item_type": "armor_legs",
  "description": "Leg armor forged in Spartan rage.",
  "lore": "BOY.",
  "base_rarity": "legendary",
  "theme": "god_of_war",
  "achievement_mapping": "psn:GOD_OF_WAR_GMGOW",
  "visuals": {
    "icon_url": "/static/items/icons/berserker_tassets.png",
    "sprite_folder": "armor/legs/berserker",
    "effect": "spartan_rage",
    "glow_color": "#C41E3A"
  },
  "effects": {
    "passive": ["boss_damage", "lifesteal"],
    "active": null
  },
  "defense": 18,
  "stat_bonuses": {"str": 6, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 5}
}
```
**Fantasy**: Completed Give Me God of War difficulty - Spartan endurance

---

### 9. Ghost Hakama (ghost_hakama)
```json
{
  "item_id": "ghost_hakama",
  "item_name": "Ghost Hakama",
  "item_type": "armor_legs",
  "description": "Traditional samurai hakama of the Ghost.",
  "lore": "Honor died on the beach.",
  "base_rarity": "epic",
  "theme": "ghost_of_tsushima",
  "achievement_mapping": "psn:GHOST_OF_TSUSHIMA_PLATINUM",
  "visuals": {
    "icon_url": "/static/items/icons/ghost_hakama.png",
    "sprite_folder": "armor/legs/ghost",
    "effect": "ghost_stance",
    "glow_color": "#1A1A2E"
  },
  "effects": {
    "passive": ["move_speed", "crit_chance"],
    "active": null
  },
  "defense": 14,
  "stat_bonuses": {"str": 0, "agi": 4, "dex": 5, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Platinum trophy - walked the path of the Ghost

---

### 10. Returnal Scout Greaves (returnal_scout_greaves)
```json
{
  "item_id": "returnal_scout_greaves",
  "item_name": "Returnal Scout Greaves",
  "item_type": "armor_legs",
  "description": "ASTRA suit leg armor, loop-worn.",
  "lore": "Break the cycle.",
  "base_rarity": "rare",
  "theme": "returnal",
  "achievement_mapping": "psn:RETURNAL_ACT3",
  "visuals": {
    "icon_url": "/static/items/icons/returnal_scout_greaves.png",
    "sprite_folder": "armor/legs/returnal",
    "effect": "adrenaline_pulse",
    "glow_color": "#00CED1"
  },
  "effects": {
    "passive": ["regen"],
    "active": null
  },
  "defense": 11,
  "stat_bonuses": {"str": 0, "agi": 2, "dex": 2, "int": 0, "wis": 0, "vit": 4}
}
```
**Fantasy**: Completed Act 3 - broke the cycle

---

## Xbox Items (5)

### 11. Pirate Legend Boots (pirate_legend_boots)
```json
{
  "item_id": "pirate_legend_boots",
  "item_name": "Pirate Legend Boots",
  "item_type": "armor_feet",
  "description": "Sea boots of a true legend.",
  "lore": "A thousand voyages, a thousand tales.",
  "base_rarity": "epic",
  "theme": "sea_of_thieves",
  "achievement_mapping": "xbox:SEA_OF_THIEVES_PIRATE_LEGEND",
  "visuals": {
    "icon_url": "/static/items/icons/pirate_legend_boots.png",
    "sprite_folder": "armor/feet/pirate_legend",
    "effect": "ghost_glow",
    "glow_color": "#1E90FF"
  },
  "effects": {
    "passive": ["stamina_regen"],
    "active": null
  },
  "defense": 12,
  "stat_bonuses": {"str": 2, "agi": 3, "dex": 3, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Achieved Pirate Legend status - sailed every sea

---

### 12. Spartan Greaves (spartan_greaves)
```json
{
  "item_id": "spartan_greaves",
  "item_name": "Spartan Greaves",
  "item_type": "armor_feet",
  "description": "MJOLNIR Mark VI leg armor.",
  "lore": "Finish the fight.",
  "base_rarity": "legendary",
  "theme": "halo",
  "achievement_mapping": "xbox:HALO_LASO_LEGENDARY",
  "visuals": {
    "icon_url": "/static/items/icons/spartan_greaves.png",
    "sprite_folder": "armor/feet/spartan",
    "effect": "shield_recharge",
    "glow_color": "#00FF00"
  },
  "effects": {
    "passive": ["damage_reduction", "poise"],
    "active": null
  },
  "defense": 17,
  "stat_bonuses": {"str": 4, "agi": 2, "dex": 0, "int": 0, "wis": 0, "vit": 5}
}
```
**Fantasy**: LASO completion - Spartan legend

---

### 13. COG Stompers (cog_stompers)
```json
{
  "item_id": "cog_stompers",
  "item_name": "COG Stompers",
  "item_type": "armor_legs",
  "description": "Heavy COG soldier leg armor.",
  "lore": "Seriously.",
  "base_rarity": "epic",
  "theme": "gears",
  "achievement_mapping": "xbox:GEARS_SERIOUSLY",
  "visuals": {
    "icon_url": "/static/items/icons/cog_stompers.png",
    "sprite_folder": "armor/legs/cog",
    "effect": "crimson_omen",
    "glow_color": "#990000"
  },
  "effects": {
    "passive": ["poise", "damage_reduction"],
    "active": null
  },
  "defense": 16,
  "stat_bonuses": {"str": 5, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4}
}
```
**Fantasy**: Seriously achievement - veteran Gear

---

### 14. Pilot's Flight Pants (pilot_flight_pants)
```json
{
  "item_id": "pilot_flight_pants",
  "item_name": "Pilot's Flight Pants",
  "item_type": "armor_legs",
  "description": "Pilot jumpsuit with thruster mounts.",
  "lore": "Stand by for Titanfall.",
  "base_rarity": "rare",
  "theme": "titanfall",
  "achievement_mapping": "xbox:TITANFALL_GAUNTLET",
  "visuals": {
    "icon_url": "/static/items/icons/pilot_flight_pants.png",
    "sprite_folder": "armor/legs/pilot",
    "effect": "pilot_boost",
    "glow_color": "#FF6600"
  },
  "effects": {
    "passive": ["move_speed"],
    "active": null
  },
  "defense": 10,
  "stat_bonuses": {"str": 0, "agi": 4, "dex": 3, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Gauntlet record - pilot agility

---

### 15. Diamond Leggings (diamond_leggings)
```json
{
  "item_id": "diamond_leggings",
  "item_name": "Diamond Leggings",
  "item_type": "armor_legs",
  "description": "Classic diamond armor pants.",
  "lore": "DIAMONDS!",
  "base_rarity": "rare",
  "theme": "minecraft",
  "achievement_mapping": "xbox:MINECRAFT_DIAMONDS",
  "visuals": {
    "icon_url": "/static/items/icons/diamond_leggings.png",
    "sprite_folder": "armor/legs/diamond",
    "effect": "block_particles",
    "glow_color": "#00BFFF"
  },
  "effects": {
    "passive": ["damage_reduction"],
    "active": null
  },
  "defense": 13,
  "stat_bonuses": {"str": 2, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 5}
}
```
**Fantasy**: Obtained diamonds - classic milestone

---

## Battle.net Items (5)

*Note: Blizzard games have 36 items but ZERO feet/legs. This fills that critical gap.*

### 16. Tier Set Sabatons (tier_set_sabatons)
```json
{
  "item_id": "tier_set_sabatons",
  "item_name": "Tier Set Sabatons",
  "item_type": "armor_feet",
  "description": "Mythic raid tier boots.",
  "lore": "Cutting Edge.",
  "base_rarity": "epic",
  "theme": "wow",
  "achievement_mapping": "battlenet:wow:CUTTING_EDGE_CURRENT",
  "visuals": {
    "icon_url": "/static/items/icons/tier_set_sabatons.png",
    "sprite_folder": "armor/feet/tier_set",
    "effect": "mythic_glow",
    "glow_color": "#B34DCC"
  },
  "effects": {
    "passive": ["boss_damage"],
    "active": null
  },
  "defense": 15,
  "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4}
}
```
**Fantasy**: Cutting Edge raider - mythic feet

---

### 17. Marauder's Treads (marauder_treads)
```json
{
  "item_id": "marauder_treads",
  "item_name": "Marauder's Treads",
  "item_type": "armor_feet",
  "description": "Demon Hunter set boots.",
  "lore": "No demon escapes.",
  "base_rarity": "rare",
  "theme": "diablo",
  "achievement_mapping": "battlenet:diablo3:SEASON_JOURNEY",
  "visuals": {
    "icon_url": "/static/items/icons/marauder_treads.png",
    "sprite_folder": "armor/feet/marauder",
    "effect": "set_bonus",
    "glow_color": "#8B4513"
  },
  "effects": {
    "passive": ["move_speed"],
    "active": null
  },
  "defense": 11,
  "stat_bonuses": {"str": 0, "agi": 4, "dex": 3, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Season Journey completion - demon hunter's path

---

### 18. Lich King Legplates (lich_king_legplates)
```json
{
  "item_id": "lich_king_legplates",
  "item_name": "Lich King Legplates",
  "item_type": "armor_legs",
  "description": "Saronite leg armor of the Lich King.",
  "lore": "There must always be a Lich King.",
  "base_rarity": "legendary",
  "theme": "wow",
  "achievement_mapping": "battlenet:wow:ICECROWN_CITADEL_GLORY",
  "visuals": {
    "icon_url": "/static/items/icons/lich_king_legplates.png",
    "sprite_folder": "armor/legs/lich_king",
    "effect": "frost_aura",
    "glow_color": "#00BFFF"
  },
  "effects": {
    "passive": ["damage_reduction", "regen"],
    "active": null
  },
  "defense": 19,
  "stat_bonuses": {"str": 5, "agi": 0, "dex": 0, "int": 0, "wis": 3, "vit": 4}
}
```
**Fantasy**: Glory of the Icecrown Raider - death knight power

---

### 19. Tracer's Leggings (tracer_leggings)
```json
{
  "item_id": "tracer_leggings",
  "item_name": "Tracer's Leggings",
  "item_type": "armor_legs",
  "description": "Chronal-accelerator compatible pants.",
  "lore": "Cheers, love!",
  "base_rarity": "rare",
  "theme": "overwatch",
  "achievement_mapping": "battlenet:overwatch2:MASTERS_RANK",
  "visuals": {
    "icon_url": "/static/items/icons/tracer_leggings.png",
    "sprite_folder": "armor/legs/tracer",
    "effect": "chronal_blur",
    "glow_color": "#FF7F00"
  },
  "effects": {
    "passive": ["move_speed"],
    "active": null
  },
  "defense": 9,
  "stat_bonuses": {"str": 0, "agi": 5, "dex": 3, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Reached Masters rank - time-jumping skill

---

### 20. Zealot Greaves (zealot_greaves)
```json
{
  "item_id": "zealot_greaves",
  "item_name": "Zealot Greaves",
  "item_type": "armor_legs",
  "description": "Protoss warrior leg armor.",
  "lore": "My life for Aiur!",
  "base_rarity": "epic",
  "theme": "starcraft",
  "achievement_mapping": "battlenet:starcraft2:BRUTAL_CAMPAIGNS",
  "visuals": {
    "icon_url": "/static/items/icons/zealot_greaves.png",
    "sprite_folder": "armor/legs/zealot",
    "effect": "psionic_charge",
    "glow_color": "#00CED1"
  },
  "effects": {
    "passive": ["armor_pierce"],
    "active": null
  },
  "defense": 14,
  "stat_bonuses": {"str": 3, "agi": 3, "dex": 0, "int": 0, "wis": 2, "vit": 0}
}
```
**Fantasy**: All campaigns on Brutal - Protoss warrior

---

## Summary Statistics

### By Provider
| Provider | Count | Games |
|----------|-------|-------|
| Steam | 5 | Apex, Portal, Cuphead, Celeste, Dead Cells |
| PlayStation | 5 | Bloodborne, Horizon, God of War, Ghost, Returnal |
| Xbox | 5 | Sea of Thieves, Halo, Gears, Titanfall, Minecraft |
| Battle.net | 5 | WoW (2), Diablo, Overwatch, StarCraft |

### By Slot
| Slot | Count |
|------|-------|
| Armor Feet | 10 |
| Armor Legs | 10 |

### By Rarity
| Rarity | Count | Items |
|--------|-------|-------|
| Legendary | 4 | Cuphead Shoes, Survivor's Pants, Berserker Tassets, Spartan Greaves |
| Epic | 10 | Apex Boots, Portal Boots, Mountaineer, Hunter's, Ghost Hakama, Pirate Legend, COG Stompers, Tier Set, Zealot |
| Rare | 6 | Aloy's Boots, Returnal Greaves, Pilot's Pants, Diamond Leggings, Marauder's Treads, Tracer's Leggings |

---

## Achievement Mappings to Add

```json
// Steam
"1172470:APEX_PREDATOR_RANK": "apex_predator_boots",
"620:PORTAL_ADVANCED_CHAMBERS": "portal_longfall_boots",
"268910:BEAT_DEVIL_EXPERT_SRANK": "cuphead_dancing_shoes",
"504230:C_SIDES_COMPLETE": "mountaineer_trousers",
"588650:FIVE_BOSS_CELLS": "survivor_pants",

// PlayStation
"psn:BLOODBORNE_CHALICE_DUNGEONS": "hunter_boots",
"psn:HORIZON_ZERO_DAWN_PLATINUM": "aloy_strider_boots",
"psn:GOD_OF_WAR_GMGOW": "berserker_tassets",
"psn:GHOST_OF_TSUSHIMA_PLATINUM": "ghost_hakama",
"psn:RETURNAL_ACT3": "returnal_scout_greaves",

// Xbox
"xbox:SEA_OF_THIEVES_PIRATE_LEGEND": "pirate_legend_boots",
"xbox:HALO_LASO_LEGENDARY": "spartan_greaves",
"xbox:GEARS_SERIOUSLY": "cog_stompers",
"xbox:TITANFALL_GAUNTLET": "pilot_flight_pants",
"xbox:MINECRAFT_DIAMONDS": "diamond_leggings",

// Battle.net
"battlenet:wow:CUTTING_EDGE_CURRENT": "tier_set_sabatons",
"battlenet:diablo3:SEASON_JOURNEY": "marauder_treads",
"battlenet:wow:ICECROWN_CITADEL_GLORY": "lich_king_legplates",
"battlenet:overwatch2:MASTERS_RANK": "tracer_leggings",
"battlenet:starcraft2:BRUTAL_CAMPAIGNS": "zealot_greaves"
```

---

## New Themes Required

Add these themes to `items.json` if not already present:

```json
"apex_legends": {
  "display_name": "Apex Legends",
  "app_ids": ["1172470"],
  "color": "#FF0000",
  "effects": ["predator_aura", "champion_glow"]
},
"portal": {
  "display_name": "Portal",
  "app_ids": ["620"],
  "color": "#FF8C00",
  "effects": ["portal_blue", "portal_orange"]
},
"cuphead": {
  "display_name": "Cuphead",
  "app_ids": ["268910"],
  "color": "#DC143C",
  "effects": ["rubberhose_bounce", "parry_pink"]
},
"horizon": {
  "display_name": "Horizon",
  "app_ids": ["psn"],
  "color": "#4169E1",
  "effects": ["focus_scan", "machine_override"]
},
"returnal": {
  "display_name": "Returnal",
  "app_ids": ["psn"],
  "color": "#00CED1",
  "effects": ["adrenaline_pulse", "cycle_break"]
},
"minecraft": {
  "display_name": "Minecraft",
  "app_ids": ["xbox"],
  "color": "#00BFFF",
  "effects": ["block_particles", "diamond_shimmer"]
}
```

---

## Next Steps

1. [x] Finalize item list
2. [x] Create GPT icon prompts
3. [ ] Generate icons using GPT/DALL-E
4. [ ] Add items to items.json
5. [ ] Add new themes to items.json
6. [ ] Test loading in Godot
7. [ ] Create LPC sprites for armor slots

---

## Notes

- Achievement IDs are placeholders - verify actual API names before implementation
- Some games may need theme definitions added to items.json
- Battle.net items fill a critical gap (0 feet/legs previously)
- All items prioritize underrepresented games (1 item currently)
