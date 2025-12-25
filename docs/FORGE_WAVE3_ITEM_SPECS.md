# Wave 3: Rings & Amulets Item Specifications

**Created**: 2025-12-25
**Items**: 14 new items (10 Rings, 4 Amulets)
**Provider Balance**: Steam (4), PlayStation (4), Xbox (3), Battle.net (3)
**Rarity Target**: 2 Legendary, 6 Epic, 6 Rare

---

## Design Philosophy

### Two Ring Slots
The game has ring1 and ring2 slots - players need meaningful choices for BOTH slots.
With 7 current rings + 10 new = 17 total, players get real build diversity.

### Accessory Fantasy
- **Rings**: Power focus - damage, crit, specific buffs
- **Amulets**: Protection focus - defense, resistance, survival

### Achievement-to-Accessory Fantasy
- **Rings**: Mastery achievements, collection, completion
- **Amulets**: Story achievements, lore completion, exploration

---

## Steam Items (4)

### 1. Band of the Scholar (band_of_scholar)
```json
{
  "item_id": "band_of_scholar",
  "item_name": "Band of the Scholar",
  "item_type": "ring",
  "description": "A ring worn by those who seek knowledge.",
  "lore": "The more you know, the more you forget.",
  "base_rarity": "rare",
  "theme": "hollow_knight",
  "achievement_mapping": "367520:MR_MUSHROOM",
  "visuals": {
    "icon_url": "/static/items/icons/band_of_scholar.png",
    "sprite_folder": null,
    "effect": "void_particles",
    "glow_color": "#4A4A6A"
  },
  "effects": {
    "passive": ["int_bonus"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 5, "wis": 3, "vit": 0}
}
```
**Fantasy**: Found all Mr. Mushroom locations - seeker of hidden knowledge

---

### 2. Gravity Ring (gravity_ring)
```json
{
  "item_id": "gravity_ring",
  "item_name": "Gravity Ring",
  "item_type": "ring",
  "description": "A ring that bends space around the wearer.",
  "lore": "Up is a suggestion.",
  "base_rarity": "epic",
  "theme": "celeste",
  "achievement_mapping": "504230:GOLDEN_STRAWBERRIES",
  "visuals": {
    "icon_url": "/static/items/icons/gravity_ring.png",
    "sprite_folder": null,
    "effect": "gravity_distortion",
    "glow_color": "#E85D8C"
  },
  "effects": {
    "passive": ["move_speed", "stamina_regen"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 5, "dex": 3, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Collected golden strawberries - defied gravity and death

---

### 3. Covenant Ring (covenant_ring)
```json
{
  "item_id": "covenant_ring",
  "item_name": "Covenant Ring",
  "item_type": "ring",
  "description": "A ring marking membership in a sacred covenant.",
  "lore": "Praise the Sun!",
  "base_rarity": "legendary",
  "theme": "dark_souls",
  "achievement_mapping": "374320:MASTER_OF_MIRACLES",
  "visuals": {
    "icon_url": "/static/items/icons/covenant_ring.png",
    "sprite_folder": null,
    "effect": "sunlight_glow",
    "glow_color": "#FFD700"
  },
  "effects": {
    "passive": ["regen", "wis_bonus"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 0, "wis": 6, "vit": 4}
}
```
**Fantasy**: Acquired all miracles - devoted to the Sun

---

### 4. Merchant's Signet (merchant_signet)
```json
{
  "item_id": "merchant_signet",
  "item_name": "Merchant's Signet",
  "item_type": "ring",
  "description": "A signet ring of a successful merchant.",
  "lore": "Buy low, sell high.",
  "base_rarity": "rare",
  "theme": "stardew",
  "achievement_mapping": "413150:MILLIONAIRE",
  "visuals": {
    "icon_url": "/static/items/icons/merchant_signet.png",
    "sprite_folder": null,
    "effect": "coin_sparkle",
    "glow_color": "#FFD700"
  },
  "effects": {
    "passive": ["gold_bonus"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 2, "wis": 3, "vit": 2}
}
```
**Fantasy**: Earned 1,000,000g - master of commerce

---

## PlayStation Items (4)

### 5. Blood Gem Ring (blood_gem_ring)
```json
{
  "item_id": "blood_gem_ring",
  "item_name": "Blood Gem Ring",
  "item_type": "ring",
  "description": "A ring set with a blood-red gem.",
  "lore": "The old blood courses through.",
  "base_rarity": "epic",
  "theme": "bloodborne",
  "achievement_mapping": "psn:BLOODBORNE_ALL_BOSSES",
  "visuals": {
    "icon_url": "/static/items/icons/blood_gem_ring.png",
    "sprite_folder": null,
    "effect": "blood_drip",
    "glow_color": "#8B0000"
  },
  "effects": {
    "passive": ["lifesteal", "crit_chance"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 3, "agi": 0, "dex": 4, "int": 0, "wis": 0, "vit": 0}
}
```
**Fantasy**: Defeated all bosses - blood-drunk hunter

---

### 6. Valkyrie's Band (valkyrie_band)
```json
{
  "item_id": "valkyrie_band",
  "item_name": "Valkyrie's Band",
  "item_type": "ring",
  "description": "A ring forged from Valkyrie metal.",
  "lore": "Worthy of Valhalla.",
  "base_rarity": "epic",
  "theme": "god_of_war",
  "achievement_mapping": "psn:GOD_OF_WAR_VALKYRIES",
  "visuals": {
    "icon_url": "/static/items/icons/valkyrie_band.png",
    "sprite_folder": null,
    "effect": "wings_shimmer",
    "glow_color": "#C0C0C0"
  },
  "effects": {
    "passive": ["boss_damage", "damage_reduction"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4}
}
```
**Fantasy**: Defeated all Valkyries - slayer of the chosen

---

### 7. Focus Lens Amulet (focus_lens_amulet)
```json
{
  "item_id": "focus_lens_amulet",
  "item_name": "Focus Lens Amulet",
  "item_type": "amulet",
  "description": "An amulet containing a Focus device lens.",
  "lore": "See what others cannot.",
  "base_rarity": "epic",
  "theme": "horizon",
  "achievement_mapping": "psn:HORIZON_FORBIDDEN_WEST_PLATINUM",
  "visuals": {
    "icon_url": "/static/items/icons/focus_lens_amulet.png",
    "sprite_folder": null,
    "effect": "scan_pulse",
    "glow_color": "#4169E1"
  },
  "effects": {
    "passive": ["crit_chance", "armor_pierce"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 4, "int": 3, "wis": 0, "vit": 0}
}
```
**Fantasy**: Platinum trophy Forbidden West - machine master

---

### 8. Astronaut Figurine Charm (astronaut_charm)
```json
{
  "item_id": "astronaut_charm",
  "item_name": "Astronaut Figurine Charm",
  "item_type": "amulet",
  "description": "A small astronaut figurine on a chain.",
  "lore": "Helios. Returner.",
  "base_rarity": "rare",
  "theme": "returnal",
  "achievement_mapping": "psn:RETURNAL_PLATINUM",
  "visuals": {
    "icon_url": "/static/items/icons/astronaut_charm.png",
    "sprite_folder": null,
    "effect": "loop_shimmer",
    "glow_color": "#00CED1"
  },
  "effects": {
    "passive": ["death_prevention"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 0, "wis": 2, "vit": 5}
}
```
**Fantasy**: Platinum trophy - survived all cycles

---

## Xbox Items (3)

### 9. Legendary Ring (legendary_ring_halo)
```json
{
  "item_id": "legendary_ring_halo",
  "item_name": "Legendary Ring",
  "item_type": "ring",
  "description": "A ring forged in the fires of Legendary difficulty.",
  "lore": "Were it so easy.",
  "base_rarity": "legendary",
  "theme": "halo",
  "achievement_mapping": "xbox:HALO_LEGENDARY_COOP",
  "visuals": {
    "icon_url": "/static/items/icons/legendary_ring_halo.png",
    "sprite_folder": null,
    "effect": "energy_sword_glow",
    "glow_color": "#00FF00"
  },
  "effects": {
    "passive": ["damage_reduction", "boss_damage"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 5}
}
```
**Fantasy**: Completed Legendary co-op - brothers in arms

---

### 10. Athena's Favor (athena_favor)
```json
{
  "item_id": "athena_favor",
  "item_name": "Athena's Favor",
  "item_type": "ring",
  "description": "A ring blessed by the goddess of wisdom.",
  "lore": "My aid is given freely.",
  "base_rarity": "epic",
  "theme": "hades",
  "achievement_mapping": "1145360:OLYMPIAN_POWER",
  "visuals": {
    "icon_url": "/static/items/icons/athena_favor.png",
    "sprite_folder": null,
    "effect": "aegis_shimmer",
    "glow_color": "#FFD700"
  },
  "effects": {
    "passive": ["damage_reduction", "poise"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 4, "wis": 4, "vit": 0}
}
```
**Fantasy**: Maxed Athena's favor - protected by wisdom

---

### 11. Ancient Core Amulet (ancient_core_amulet)
```json
{
  "item_id": "ancient_core_amulet",
  "item_name": "Ancient Core Amulet",
  "item_type": "amulet",
  "description": "An amulet powered by ancient Sheikah technology.",
  "lore": "The Calamity has been sealed.",
  "base_rarity": "rare",
  "theme": "zelda",
  "achievement_mapping": "xbox:TOTK_ALL_SHRINES",
  "visuals": {
    "icon_url": "/static/items/icons/ancient_core_amulet.png",
    "sprite_folder": null,
    "effect": "sheikah_glow",
    "glow_color": "#00BFFF"
  },
  "effects": {
    "passive": ["stamina_regen", "int_bonus"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 4, "wis": 2, "vit": 2}
}
```
**Fantasy**: Completed all shrines - blessing of the monks

---

## Battle.net Items (3)

### 12. Sigil of the Mage (sigil_of_mage)
```json
{
  "item_id": "sigil_of_mage",
  "item_name": "Sigil of the Mage",
  "item_type": "ring",
  "description": "A ring crackling with arcane power.",
  "lore": "Knowledge is power.",
  "base_rarity": "epic",
  "theme": "wow",
  "achievement_mapping": "battlenet:wow:MOUNT_PARADE",
  "visuals": {
    "icon_url": "/static/items/icons/sigil_of_mage.png",
    "sprite_folder": null,
    "effect": "arcane_sparks",
    "glow_color": "#8A2BE2"
  },
  "effects": {
    "passive": ["int_bonus", "crit_chance"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 6, "wis": 2, "vit": 0}
}
```
**Fantasy**: Mount parade achievement - collector of power

---

### 13. Horadric Charm (horadric_charm)
```json
{
  "item_id": "horadric_charm",
  "item_name": "Horadric Charm",
  "item_type": "amulet",
  "description": "An ancient charm from the Horadric order.",
  "lore": "Stay awhile and listen.",
  "base_rarity": "rare",
  "theme": "diablo",
  "achievement_mapping": "battlenet:diablo4:CAMPAIGN_COMPLETE",
  "visuals": {
    "icon_url": "/static/items/icons/horadric_charm.png",
    "sprite_folder": null,
    "effect": "cube_glow",
    "glow_color": "#FFD700"
  },
  "effects": {
    "passive": ["regen", "gold_bonus"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 2, "wis": 3, "vit": 3}
}
```
**Fantasy**: Completed D4 campaign - heir of the Horadrim

---

### 14. Xel'Naga Artifact Ring (xelnaga_ring)
```json
{
  "item_id": "xelnaga_ring",
  "item_name": "Xel'Naga Artifact Ring",
  "item_type": "ring",
  "description": "A ring containing Xel'Naga energy.",
  "lore": "The cycle must be broken.",
  "base_rarity": "rare",
  "theme": "starcraft",
  "achievement_mapping": "battlenet:starcraft2:MASTER_ARCHIVE",
  "visuals": {
    "icon_url": "/static/items/icons/xelnaga_ring.png",
    "sprite_folder": null,
    "effect": "void_energy",
    "glow_color": "#9400D3"
  },
  "effects": {
    "passive": ["armor_pierce"],
    "active": null
  },
  "defense": 0,
  "stat_bonuses": {"str": 0, "agi": 0, "dex": 3, "int": 4, "wis": 0, "vit": 0}
}
```
**Fantasy**: Completed Master Archives - keeper of forbidden knowledge

---

## Summary Statistics

### By Provider
| Provider | Count | Games |
|----------|-------|-------|
| Steam | 4 | Hollow Knight, Celeste, Dark Souls, Stardew |
| PlayStation | 4 | Bloodborne, God of War, Horizon, Returnal |
| Xbox | 3 | Halo, Hades (cross-platform), Zelda |
| Battle.net | 3 | WoW, Diablo, StarCraft |

### By Slot
| Slot | Current | Wave 3 | Final |
|------|---------|--------|-------|
| Ring | 7 | +10 | 17 |
| Amulet | 6 | +4 | 10 |

### By Rarity
| Rarity | Count | Items |
|--------|-------|-------|
| Legendary | 2 | Covenant Ring, Legendary Ring |
| Epic | 6 | Gravity Ring, Blood Gem, Valkyrie's Band, Focus Lens, Athena's Favor, Sigil of Mage |
| Rare | 6 | Band of Scholar, Merchant's Signet, Astronaut Charm, Ancient Core, Horadric Charm, Xel'Naga Ring |

---

## Achievement Mappings to Add

```json
// Steam - Rings
"367520:MR_MUSHROOM": "band_of_scholar",
"504230:GOLDEN_STRAWBERRIES": "gravity_ring",
"374320:MASTER_OF_MIRACLES": "covenant_ring",
"413150:MILLIONAIRE": "merchant_signet",

// PlayStation - Rings
"psn:BLOODBORNE_ALL_BOSSES": "blood_gem_ring",
"psn:GOD_OF_WAR_VALKYRIES": "valkyrie_band",

// PlayStation - Amulets
"psn:HORIZON_FORBIDDEN_WEST_PLATINUM": "focus_lens_amulet",
"psn:RETURNAL_PLATINUM": "astronaut_charm",

// Xbox - Rings
"xbox:HALO_LEGENDARY_COOP": "legendary_ring_halo",
"1145360:OLYMPIAN_POWER": "athena_favor",

// Xbox - Amulets
"xbox:TOTK_ALL_SHRINES": "ancient_core_amulet",

// Battle.net - Rings
"battlenet:wow:MOUNT_PARADE": "sigil_of_mage",
"battlenet:starcraft2:MASTER_ARCHIVE": "xelnaga_ring",

// Battle.net - Amulets
"battlenet:diablo4:CAMPAIGN_COMPLETE": "horadric_charm"
```

---

## New Themes Required

Add if not present:
```json
"zelda": {
  "display_name": "The Legend of Zelda",
  "app_ids": ["xbox"],
  "color": "#00BFFF",
  "effects": ["sheikah_glow", "triforce_shimmer"]
}
```

---

## All Waves Summary

| Wave | Slot Focus | Items | Cumulative |
|------|------------|-------|------------|
| Base | All | 116 | 116 |
| Wave 1 | Feet, Legs | 20 | 136 |
| Wave 2 | Arms, Hands, Shields | 21 | 157 |
| Wave 3 | Rings, Amulets | 14 | 171 |

### Final Slot Distribution After Wave 3:

| Slot | Count | Status |
|------|-------|--------|
| Weapons | 40+ | Good |
| Head | 12 | Good |
| Chest | 9 | Good |
| Arms | 8 | Good (Wave 2) |
| Hands | 8 | Good (Wave 2) |
| Legs | 10 | Good (Wave 1) |
| Feet | 10 | Good (Wave 1) |
| Back (Cape) | 8 | Good |
| Shield | 8 | Good (Wave 2) |
| Ring (x2) | 17 | Good (Wave 3) |
| Amulet | 10 | Good (Wave 3) |

**Full set equipping now possible across all slots with meaningful variety!**

---

## Next Steps

1. [ ] Generate icons using GPT prompts
2. [ ] Add Wave 1-3 items to items.json
3. [ ] Add new themes to items.json
4. [ ] Test loading in Godot
5. [ ] Create LPC sprites for armor slots
