# Wave 2: Arms, Hands & Shields Item Specifications

**Created**: 2025-12-25
**Items**: 21 new items (8 Arms, 7 Hands, 6 Shields)
**Provider Balance**: Steam (6), PlayStation (5), Xbox (5), Battle.net (5)
**Rarity Target**: 4 Legendary, 10 Epic, 7 Rare

---

## Design Philosophy

### New Slot: armor_arms
Arms slot (bracers, vambraces, armguards) is SEPARATE from hands slot (gloves, gauntlets).
- **Arms**: Defensive, protective - bracers deflect blows
- **Hands**: Offensive, precision - gloves for grip/skill

### Achievement-to-Slot Fantasy
- **Arms**: Defensive achievements, blocking, tanking
- **Hands**: Precision achievements, crafting, skill-based
- **Shields**: Tank achievements, protection, survival

---

## Steam Items (6)

### 1. Abyss Watcher Vambraces (abyss_watcher_vambraces)
```json
{
  "item_id": "abyss_watcher_vambraces",
  "item_name": "Abyss Watcher Vambraces",
  "item_type": "armor_arms",
  "description": "Arm guards of the wolf blood legion.",
  "lore": "The wolf blood burns within.",
  "base_rarity": "epic",
  "theme": "dark_souls",
  "achievement_mapping": "374320:ABYSS_WATCHERS",
  "visuals": {
    "icon_url": "/static/items/icons/abyss_watcher_vambraces.png",
    "sprite_folder": "armor/arms/abyss_watcher",
    "effect": "wolf_blood_aura",
    "glow_color": "#4A6B8A"
  },
  "effects": {
    "passive": ["damage_reduction"],
    "active": null
  },
  "defense": 12,
  "stat_bonuses": {"str": 3, "agi": 0, "dex": 3, "int": 0, "wis": 0, "vit": 2}
}
```
**Fantasy**: Defeated the Abyss Watchers - earned their armor

---

### 2. Blacksmith's Gloves (blacksmith_gloves)
```json
{
  "item_id": "blacksmith_gloves",
  "item_name": "Blacksmith's Gloves",
  "item_type": "armor_hands",
  "description": "Sturdy gloves worn at the forge.",
  "lore": "Every item shipped, every tool crafted.",
  "base_rarity": "rare",
  "theme": "stardew",
  "achievement_mapping": "413150:CRAFT_MASTER",
  "visuals": {
    "icon_url": "/static/items/icons/blacksmith_gloves.png",
    "sprite_folder": "armor/hands/blacksmith",
    "effect": "forge_sparks",
    "glow_color": "#8B4513"
  },
  "effects": {
    "passive": ["regen"],
    "active": null
  },
  "defense": 8,
  "stat_bonuses": {"str": 2, "agi": 0, "dex": 3, "int": 0, "wis": 0, "vit": 2}
}
```
**Fantasy**: Master crafter - hands that built the farm

---

### 3. Marksman's Gloves (marksman_gloves)
```json
{
  "item_id": "marksman_gloves",
  "item_name": "Marksman's Gloves",
  "item_type": "armor_hands",
  "description": "Precision shooting gloves.",
  "lore": "A thousand headshots, one pair of gloves.",
  "base_rarity": "epic",
  "theme": "counter_strike",
  "achievement_mapping": "730:HEADSHOT_MASTER",
  "visuals": {
    "icon_url": "/static/items/icons/marksman_gloves.png",
    "sprite_folder": "armor/hands/marksman",
    "effect": "precision_glow",
    "glow_color": "#FF4500"
  },
  "effects": {
    "passive": ["crit_chance"],
    "active": null
  },
  "defense": 6,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 6, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Headshot master - precision aiming

---

### 4. Grass Crest Vambraces (grass_crest_vambraces)
```json
{
  "item_id": "grass_crest_vambraces",
  "item_name": "Grass Crest Vambraces",
  "item_type": "armor_arms",
  "description": "Arm guards blessed with stamina recovery.",
  "lore": "Praise the grass!",
  "base_rarity": "rare",
  "theme": "dark_souls",
  "achievement_mapping": "211420:DARK_SOUL",
  "visuals": {
    "icon_url": "/static/items/icons/grass_crest_vambraces.png",
    "sprite_folder": "armor/arms/grass_crest",
    "effect": "stamina_aura",
    "glow_color": "#228B22"
  },
  "effects": {
    "passive": ["stamina_regen"],
    "active": null
  },
  "defense": 10,
  "stat_bonuses": {"str": 0, "agi": 3, "dex": 0, "int": 0, "wis": 0, "vit": 4}
}
```
**Fantasy**: The Dark Soul achievement - stamina management mastery

---

### 5. Aegis of Champions (aegis_of_champions)
```json
{
  "item_id": "aegis_of_champions",
  "item_name": "Aegis of Champions",
  "item_type": "shield",
  "description": "The shield of esports legends.",
  "lore": "The International awaits.",
  "base_rarity": "legendary",
  "theme": "dota",
  "achievement_mapping": "570:AEGIS_STEAL",
  "visuals": {
    "icon_url": "/static/items/icons/aegis_of_champions.png",
    "sprite_folder": "shields/aegis/standard",
    "effect": "aegis_glow",
    "glow_color": "#FFD700"
  },
  "effects": {
    "passive": ["death_prevention"],
    "active": null
  },
  "defense": 25,
  "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 6}
}
```
**Fantasy**: Aegis steal/win - esports glory

---

### 6. Thief's Handwraps (thief_handwraps)
```json
{
  "item_id": "thief_handwraps",
  "item_name": "Thief's Handwraps",
  "item_type": "armor_hands",
  "description": "Wraps that silence your touch.",
  "lore": "Light fingers, heavy pockets.",
  "base_rarity": "rare",
  "theme": "skyrim",
  "achievement_mapping": "72850:THIEVES_GUILD_MASTER",
  "visuals": {
    "icon_url": "/static/items/icons/thief_handwraps.png",
    "sprite_folder": "armor/hands/thief",
    "effect": "shadow_touch",
    "glow_color": "#2F4F4F"
  },
  "effects": {
    "passive": ["crit_chance"],
    "active": null
  },
  "defense": 5,
  "stat_bonuses": {"str": 0, "agi": 4, "dex": 3, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Thieves Guild Master - light-fingered expert

---

## PlayStation Items (5)

### 7. Hunter's Forearm Guards (hunter_forearm_guards)
```json
{
  "item_id": "hunter_forearm_guards",
  "item_name": "Hunter's Forearm Guards",
  "item_type": "armor_arms",
  "description": "Leather guards stained with old blood.",
  "lore": "Fear the old blood.",
  "base_rarity": "epic",
  "theme": "bloodborne",
  "achievement_mapping": "psn:BLOODBORNE_ALL_WEAPONS",
  "visuals": {
    "icon_url": "/static/items/icons/hunter_forearm_guards.png",
    "sprite_folder": "armor/arms/hunter",
    "effect": "blood_splatter",
    "glow_color": "#8B0000"
  },
  "effects": {
    "passive": ["lifesteal"],
    "active": null
  },
  "defense": 11,
  "stat_bonuses": {"str": 2, "agi": 3, "dex": 2, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Collected all weapons - master hunter

---

### 8. Leviathan Vambraces (leviathan_vambraces)
```json
{
  "item_id": "leviathan_vambraces",
  "item_name": "Leviathan Vambraces",
  "item_type": "armor_arms",
  "description": "Frost-touched arm guards.",
  "lore": "The axe remembers.",
  "base_rarity": "epic",
  "theme": "god_of_war",
  "achievement_mapping": "psn:GOD_OF_WAR_VALKYRIES",
  "visuals": {
    "icon_url": "/static/items/icons/leviathan_vambraces.png",
    "sprite_folder": "armor/arms/leviathan",
    "effect": "frost_particles",
    "glow_color": "#87CEEB"
  },
  "effects": {
    "passive": ["damage_reduction", "boss_damage"],
    "active": null
  },
  "defense": 14,
  "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4}
}
```
**Fantasy**: Defeated all Valkyries - proven warrior

---

### 9. Guardian Shield (guardian_shield)
```json
{
  "item_id": "guardian_shield",
  "item_name": "Guardian Shield",
  "item_type": "shield",
  "description": "A shield forged from machine parts.",
  "lore": "Override protocol engaged.",
  "base_rarity": "epic",
  "theme": "horizon",
  "achievement_mapping": "psn:HORIZON_ALL_MACHINES",
  "visuals": {
    "icon_url": "/static/items/icons/guardian_shield.png",
    "sprite_folder": "shields/guardian/standard",
    "effect": "machine_glow",
    "glow_color": "#4169E1"
  },
  "effects": {
    "passive": ["damage_reduction"],
    "active": null
  },
  "defense": 22,
  "stat_bonuses": {"str": 3, "agi": 0, "dex": 0, "int": 0, "wis": 2, "vit": 4}
}
```
**Fantasy**: Overrode all machines - machine master

---

### 10. Samurai Kote (samurai_kote)
```json
{
  "item_id": "samurai_kote",
  "item_name": "Samurai Kote",
  "item_type": "armor_hands",
  "description": "Armored gloves of the Ghost.",
  "lore": "The way of the Ghost.",
  "base_rarity": "epic",
  "theme": "ghost_of_tsushima",
  "achievement_mapping": "psn:GHOST_ALL_TECHNIQUES",
  "visuals": {
    "icon_url": "/static/items/icons/samurai_kote.png",
    "sprite_folder": "armor/hands/samurai",
    "effect": "ghost_stance",
    "glow_color": "#1A1A2E"
  },
  "effects": {
    "passive": ["crit_chance", "armor_pierce"],
    "active": null
  },
  "defense": 9,
  "stat_bonuses": {"str": 0, "agi": 3, "dex": 4, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Mastered all techniques - Ghost warrior

---

### 11. Atropos Bracers (atropos_bracers)
```json
{
  "item_id": "atropos_bracers",
  "item_name": "Atropos Bracers",
  "item_type": "armor_arms",
  "description": "Alien-touched arm guards.",
  "lore": "The cycle continues.",
  "base_rarity": "rare",
  "theme": "returnal",
  "achievement_mapping": "psn:RETURNAL_ALL_BIOMES",
  "visuals": {
    "icon_url": "/static/items/icons/atropos_bracers.png",
    "sprite_folder": "armor/arms/atropos",
    "effect": "adrenaline_pulse",
    "glow_color": "#00CED1"
  },
  "effects": {
    "passive": ["regen"],
    "active": null
  },
  "defense": 10,
  "stat_bonuses": {"str": 0, "agi": 2, "dex": 2, "int": 0, "wis": 0, "vit": 3}
}
```
**Fantasy**: Explored all biomes - cycle survivor

---

## Xbox Items (5)

### 12. MJOLNIR Bracers (mjolnir_bracers)
```json
{
  "item_id": "mjolnir_bracers",
  "item_name": "MJOLNIR Bracers",
  "item_type": "armor_arms",
  "description": "Spartan forearm armor.",
  "lore": "Spartans never die.",
  "base_rarity": "legendary",
  "theme": "halo",
  "achievement_mapping": "xbox:HALO_LEGENDARY_ALL",
  "visuals": {
    "icon_url": "/static/items/icons/mjolnir_bracers.png",
    "sprite_folder": "armor/arms/mjolnir",
    "effect": "shield_recharge",
    "glow_color": "#00FF00"
  },
  "effects": {
    "passive": ["damage_reduction", "poise"],
    "active": null
  },
  "defense": 15,
  "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 5}
}
```
**Fantasy**: All campaigns on Legendary - Spartan legend

---

### 13. Captain's Buckler (captain_buckler)
```json
{
  "item_id": "captain_buckler",
  "item_name": "Captain's Buckler",
  "item_type": "shield",
  "description": "A small shield for swift pirates.",
  "lore": "Every captain needs a backup plan.",
  "base_rarity": "rare",
  "theme": "sea_of_thieves",
  "achievement_mapping": "xbox:SEA_SHIP_BATTLES",
  "visuals": {
    "icon_url": "/static/items/icons/captain_buckler.png",
    "sprite_folder": "shields/captain/standard",
    "effect": "ocean_particles",
    "glow_color": "#1E90FF"
  },
  "effects": {
    "passive": ["stamina_regen"],
    "active": null
  },
  "defense": 16,
  "stat_bonuses": {"str": 2, "agi": 2, "dex": 2, "int": 0, "wis": 0, "vit": 2}
}
```
**Fantasy**: Won 100 ship battles - sea captain

---

### 14. COG Gauntlets (cog_gauntlets)
```json
{
  "item_id": "cog_gauntlets",
  "item_name": "COG Gauntlets",
  "item_type": "armor_hands",
  "description": "Heavy armored gloves for chainsaw grip.",
  "lore": "Rev it up.",
  "base_rarity": "epic",
  "theme": "gears",
  "achievement_mapping": "xbox:GEARS_LANCER_KILLS",
  "visuals": {
    "icon_url": "/static/items/icons/cog_gauntlets.png",
    "sprite_folder": "armor/hands/cog",
    "effect": "chainsaw_rev",
    "glow_color": "#990000"
  },
  "effects": {
    "passive": ["lifesteal"],
    "active": null
  },
  "defense": 10,
  "stat_bonuses": {"str": 5, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 2}
}
```
**Fantasy**: Lancer chainsaw mastery - brutal COG

---

### 15. Pilot's Bracers (pilot_bracers)
```json
{
  "item_id": "pilot_bracers",
  "item_name": "Pilot's Bracers",
  "item_type": "armor_arms",
  "description": "Reinforced jump kit arm mounts.",
  "lore": "Protocol 3: Protect the Pilot.",
  "base_rarity": "rare",
  "theme": "titanfall",
  "achievement_mapping": "xbox:TITANFALL_REGENERATION",
  "visuals": {
    "icon_url": "/static/items/icons/pilot_bracers.png",
    "sprite_folder": "armor/arms/pilot",
    "effect": "pilot_boost",
    "glow_color": "#FF6600"
  },
  "effects": {
    "passive": ["move_speed"],
    "active": null
  },
  "defense": 9,
  "stat_bonuses": {"str": 0, "agi": 4, "dex": 2, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Reached regeneration - veteran pilot

---

### 16. Netherite Gauntlets (netherite_gauntlets)
```json
{
  "item_id": "netherite_gauntlets",
  "item_name": "Netherite Gauntlets",
  "item_type": "armor_hands",
  "description": "Gloves forged in the Nether.",
  "lore": "Ancient debris reforged.",
  "base_rarity": "rare",
  "theme": "minecraft",
  "achievement_mapping": "xbox:MINECRAFT_NETHERITE",
  "visuals": {
    "icon_url": "/static/items/icons/netherite_gauntlets.png",
    "sprite_folder": "armor/hands/netherite",
    "effect": "block_particles",
    "glow_color": "#4A4A4A"
  },
  "effects": {
    "passive": ["damage_reduction"],
    "active": null
  },
  "defense": 11,
  "stat_bonuses": {"str": 3, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4}
}
```
**Fantasy**: Obtained netherite - deep explorer

---

## Battle.net Items (5)

### 17. Paladin's Bulwark (paladin_bulwark)
```json
{
  "item_id": "paladin_bulwark",
  "item_name": "Paladin's Bulwark",
  "item_type": "shield",
  "description": "A holy shield blessed by the Light.",
  "lore": "The Light protects.",
  "base_rarity": "legendary",
  "theme": "wow",
  "achievement_mapping": "battlenet:wow:GLADIATOR_TANK",
  "visuals": {
    "icon_url": "/static/items/icons/paladin_bulwark.png",
    "sprite_folder": "shields/paladin/standard",
    "effect": "holy_light",
    "glow_color": "#FFD700"
  },
  "effects": {
    "passive": ["damage_reduction", "regen"],
    "active": null
  },
  "defense": 28,
  "stat_bonuses": {"str": 5, "agi": 0, "dex": 0, "int": 0, "wis": 3, "vit": 5}
}
```
**Fantasy**: Gladiator as tank spec - ultimate defender

---

### 18. Crusader Bracers (crusader_bracers)
```json
{
  "item_id": "crusader_bracers",
  "item_name": "Crusader Bracers",
  "item_type": "armor_arms",
  "description": "Holy warrior arm guards.",
  "lore": "Akarat's Champion.",
  "base_rarity": "epic",
  "theme": "diablo",
  "achievement_mapping": "battlenet:diablo3:CRUSADER_MASTERY",
  "visuals": {
    "icon_url": "/static/items/icons/crusader_bracers.png",
    "sprite_folder": "armor/arms/crusader",
    "effect": "holy_light",
    "glow_color": "#FFD700"
  },
  "effects": {
    "passive": ["damage_reduction"],
    "active": null
  },
  "defense": 13,
  "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4}
}
```
**Fantasy**: Crusader class mastery - holy warrior

---

### 19. Reinhardt's Barrier Fragment (reinhardt_barrier)
```json
{
  "item_id": "reinhardt_barrier",
  "item_name": "Reinhardt's Barrier Fragment",
  "item_type": "shield",
  "description": "A piece of the legendary barrier.",
  "lore": "BARRIER IS HOLDING!",
  "base_rarity": "epic",
  "theme": "overwatch",
  "achievement_mapping": "battlenet:overwatch2:BARRIER_BLOCKED",
  "visuals": {
    "icon_url": "/static/items/icons/reinhardt_barrier.png",
    "sprite_folder": "shields/reinhardt/standard",
    "effect": "barrier_shimmer",
    "glow_color": "#4169E1"
  },
  "effects": {
    "passive": ["damage_reduction", "poise"],
    "active": null
  },
  "defense": 24,
  "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 5}
}
```
**Fantasy**: Blocked massive damage - anchor tank

---

### 20. Medic's Gloves (medic_gloves)
```json
{
  "item_id": "medic_gloves",
  "item_name": "Medic's Gloves",
  "item_type": "armor_hands",
  "description": "Field medic surgical gloves.",
  "lore": "Heal your allies, harm your enemies.",
  "base_rarity": "rare",
  "theme": "starcraft",
  "achievement_mapping": "battlenet:starcraft2:MEDIC_HEALS",
  "visuals": {
    "icon_url": "/static/items/icons/medic_gloves.png",
    "sprite_folder": "armor/hands/medic",
    "effect": "heal_aura",
    "glow_color": "#00FF00"
  },
  "effects": {
    "passive": ["regen"],
    "active": null
  },
  "defense": 7,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 2, "int": 0, "wis": 4, "vit": 2}
}
```
**Fantasy**: Healed extensively in coop - support master

---

### 21. Immortal Bracers (immortal_bracers)
```json
{
  "item_id": "immortal_bracers",
  "item_name": "Immortal Bracers",
  "item_type": "armor_arms",
  "description": "Bracers from the Immortal raid.",
  "lore": "A tribute to perfection.",
  "base_rarity": "legendary",
  "theme": "wow",
  "achievement_mapping": "battlenet:wow:IMMORTAL",
  "visuals": {
    "icon_url": "/static/items/icons/immortal_bracers.png",
    "sprite_folder": "armor/arms/immortal",
    "effect": "golden_glow",
    "glow_color": "#FFD700"
  },
  "effects": {
    "passive": ["death_prevention"],
    "active": null
  },
  "defense": 14,
  "stat_bonuses": {"str": 3, "agi": 0, "dex": 0, "int": 0, "wis": 3, "vit": 5}
}
```
**Fantasy**: The Immortal achievement - zero deaths in raid

---

## Summary Statistics

### By Provider
| Provider | Count | Games |
|----------|-------|-------|
| Steam | 6 | Dark Souls (2), Stardew, CS:GO, Skyrim, Dota |
| PlayStation | 5 | Bloodborne, God of War, Horizon, Ghost, Returnal |
| Xbox | 5 | Halo, Sea of Thieves, Gears, Titanfall, Minecraft |
| Battle.net | 5 | WoW (3), Diablo, Overwatch, StarCraft |

### By Slot
| Slot | Count | Existing | New Total |
|------|-------|----------|-----------|
| Armor Arms | 8 | 0 | 8 |
| Armor Hands | 7 | 1 | 8 |
| Shield | 6 | 2 | 8 |

### By Rarity
| Rarity | Count | Items |
|--------|-------|-------|
| Legendary | 4 | Aegis, MJOLNIR Bracers, Paladin's Bulwark, Immortal Bracers |
| Epic | 10 | Abyss Watcher, Marksman, Hunter's, Leviathan, Guardian, Samurai, COG, Crusader, Reinhardt |
| Rare | 7 | Blacksmith, Grass Crest, Thief's, Atropos, Captain's, Pilot's, Netherite, Medic's |

---

## Achievement Mappings to Add

```json
// Steam - Arms
"374320:ABYSS_WATCHERS": "abyss_watcher_vambraces",
"211420:DARK_SOUL": "grass_crest_vambraces",

// Steam - Hands
"413150:CRAFT_MASTER": "blacksmith_gloves",
"730:HEADSHOT_MASTER": "marksman_gloves",
"72850:THIEVES_GUILD_MASTER": "thief_handwraps",

// Steam - Shields
"570:AEGIS_STEAL": "aegis_of_champions",

// PlayStation - Arms
"psn:BLOODBORNE_ALL_WEAPONS": "hunter_forearm_guards",
"psn:GOD_OF_WAR_VALKYRIES": "leviathan_vambraces",
"psn:RETURNAL_ALL_BIOMES": "atropos_bracers",

// PlayStation - Hands
"psn:GHOST_ALL_TECHNIQUES": "samurai_kote",

// PlayStation - Shields
"psn:HORIZON_ALL_MACHINES": "guardian_shield",

// Xbox - Arms
"xbox:HALO_LEGENDARY_ALL": "mjolnir_bracers",
"xbox:TITANFALL_REGENERATION": "pilot_bracers",

// Xbox - Hands
"xbox:GEARS_LANCER_KILLS": "cog_gauntlets",
"xbox:MINECRAFT_NETHERITE": "netherite_gauntlets",

// Xbox - Shields
"xbox:SEA_SHIP_BATTLES": "captain_buckler",

// Battle.net - Arms
"battlenet:diablo3:CRUSADER_MASTERY": "crusader_bracers",
"battlenet:wow:IMMORTAL": "immortal_bracers",

// Battle.net - Hands
"battlenet:starcraft2:MEDIC_HEALS": "medic_gloves",

// Battle.net - Shields
"battlenet:wow:GLADIATOR_TANK": "paladin_bulwark",
"battlenet:overwatch2:BARRIER_BLOCKED": "reinhardt_barrier"
```

---

## New Themes Required

Add if not present:
```json
"dota": {
  "display_name": "Dota 2",
  "app_ids": ["570"],
  "color": "#FF6600",
  "effects": ["aegis_glow", "ancient_power"]
},
"counter_strike": {
  "display_name": "Counter-Strike",
  "app_ids": ["730"],
  "color": "#FF4500",
  "effects": ["stattrak_glow", "precision_glow"]
}
```

---

## Next Steps

1. [ ] Generate icons using GPT prompts
2. [ ] Add items to items.json
3. [ ] Test loading in Godot
4. [ ] Create LPC sprites for armor slots

---

## Wave 3 Preview: Rings + Amulets

With 2 ring slots needing coverage:

| Slot | Current | Wave 3 Target | Final |
|------|---------|---------------|-------|
| Ring | 7 | +10 | 17 |
| Amulet | 6 | +4 | 10 |

This ensures players have meaningful choices for both ring slots.
