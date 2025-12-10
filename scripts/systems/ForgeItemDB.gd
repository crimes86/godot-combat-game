extends Node
## ForgeItemDB - Maps achievements to in-game items
## Core database for the Forge system
##
## Priority order based on game popularity (Steam player counts):
## 1. Elden Ring (42 achievements, 8.7% 100% rate)
## 2. Dark Souls 3 (43 achievements)
## 3. Stardew Valley (49 achievements)
## 4. Terraria (104 achievements)
## 5. Hollow Knight (63 achievements)
## 6. Hades (49 achievements)
## 7. The Witcher 3 (78 achievements)
## 8. Skyrim (75 achievements)
## 9. Monster Hunter World (50 achievements)
## 10. Sekiro (34 achievements)

# Item rarity thresholds (based on achievement unlock %)
# Legendary: < 1% unlock rate
# Epic: 1-5% unlock rate
# Rare: 5-15% unlock rate
# Uncommon: 15-40% unlock rate
# Common: 40%+ unlock rate

enum ItemRarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum ItemType { WEAPON, ARMOR_HEAD, ARMOR_CHEST, ARMOR_LEGS, ARMOR_HANDS, ARMOR_FEET, CAPE, SHIELD, ACCESSORY, EMOTE, TITLE }
# WeaponClass: Core (SWORD-RAPIER have animation data), Extended (rest fall back to core)
enum WeaponClass { SWORD, DAGGER, MACE, SPEAR, STAFF, AXE, RAPIER, GREATSWORD, KATANA, SABER, SCIMITAR, HALBERD, PIKE, TRIDENT, FLAIL, SCYTHE, BOW, CROSSBOW, GUN }

# Base paths for forged items (separate from regular loot)
const FORGED_ITEMS_BASE = "res://assets/equipment/forged/"
const FORGED_ICONS_BASE = "res://assets/icons/forged/"

# ═══════════════════════════════════════════════════════════════════════════════
# MASTER ITEM DATABASE
# Key format: "{provider}_{appid}_{achievement_api_name}"
# ═══════════════════════════════════════════════════════════════════════════════

const FORGE_ITEMS = {
	# ═══════════════════════════════════════════════════════════════════════════
	# ELDEN RING (Steam App ID: 1245620)
	# 42 achievements - Very popular, high completion rates
	# ═══════════════════════════════════════════════════════════════════════════

	# Common Tier (40%+ unlock) - Early game bosses
	"steam_1245620_MARGIT_THE_FELL": {
		"item_id": "margits_shackle",
		"item_name": "Margit's Shackle",
		"item_type": ItemType.ACCESSORY,
		"rarity": ItemRarity.COMMON,
		"description": "A chain that once bound the fell omen.",
		"lore": "Even demons can be bound by those who know the old ways.",
		"achievement_name": "Margit, the Fell Omen",
		"unlock_percent": 78.5,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "accessories/margits_shackle.png"
		},
		"effects": [],
		"cosmetic_only": true
	},

	"steam_1245620_GODRICK_THE_GRAFTED": {
		"item_id": "grafted_blade",
		"item_name": "Grafted Blade Greatsword",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.GREATSWORD,
		"rarity": ItemRarity.COMMON,
		"description": "A weapon of the many, grafted into one.",
		"lore": "Bear witness! I am the lord of all that is golden!",
		"achievement_name": "Godrick the Grafted",
		"unlock_percent": 72.3,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/grafted_blade.png",
			"walk": FORGED_ITEMS_BASE + "weapons/grafted_blade/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/grafted_blade/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/grafted_blade/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/grafted_blade/hurt.png"
		},
		"effects": ["golden_glow"],
		"stats": {"damage_bonus": 2},
		"cosmetic_only": false
	},

	# Uncommon Tier (15-40% unlock) - Mid-game progression
	"steam_1245620_RENNALA_QUEEN": {
		"item_id": "carian_crown",
		"item_name": "Carian Royal Crown",
		"item_type": ItemType.ARMOR_HEAD,
		"rarity": ItemRarity.UNCOMMON,
		"description": "Crown worn by the Queen of the Full Moon.",
		"lore": "Her gaze pierces even the darkest nights.",
		"achievement_name": "Rennala, Queen of the Full Moon",
		"unlock_percent": 52.1,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "armor/carian_crown.png",
			"walk": FORGED_ITEMS_BASE + "armor/head/carian_crown/walk.png",
			"slash": FORGED_ITEMS_BASE + "armor/head/carian_crown/slash.png",
			"thrust": FORGED_ITEMS_BASE + "armor/head/carian_crown/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "armor/head/carian_crown/hurt.png"
		},
		"effects": ["moonlight_aura"],
		"cosmetic_only": true
	},

	"steam_1245620_STARSCOURGE_RADAHN": {
		"item_id": "radahns_greatswords",
		"item_name": "Starscourge Greatswords",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.GREATSWORD,
		"rarity": ItemRarity.UNCOMMON,
		"description": "Paired greatswords wielded by the Starscourge.",
		"lore": "He held back the stars. Now, you carry that burden.",
		"achievement_name": "Starscourge Radahn",
		"unlock_percent": 38.7,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/radahns_greatswords.png",
			"walk": FORGED_ITEMS_BASE + "weapons/radahns_greatswords/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/radahns_greatswords/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/radahns_greatswords/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/radahns_greatswords/hurt.png"
		},
		"effects": ["gravity_particles", "purple_glow"],
		"stats": {"damage_bonus": 3},
		"cosmetic_only": false
	},

	# Rare Tier (5-15% unlock) - Late game / Optional bosses
	"steam_1245620_MALENIA_BLADE": {
		"item_id": "hand_of_malenia",
		"item_name": "Hand of Malenia",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.KATANA,
		"rarity": ItemRarity.RARE,
		"description": "Blade of Malenia, Blade of Miquella.",
		"lore": "I am Malenia, and I have never known defeat.",
		"achievement_name": "Malenia, Blade of Miquella",
		"unlock_percent": 32.4,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/hand_of_malenia.png",
			"walk": FORGED_ITEMS_BASE + "weapons/hand_of_malenia/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/hand_of_malenia/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/hand_of_malenia/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/hand_of_malenia/hurt.png"
		},
		"effects": ["scarlet_rot_trail", "flower_petals"],
		"stats": {"damage_bonus": 4, "lifesteal": 1},
		"cosmetic_only": false
	},

	# Epic Tier (1-5% unlock) - Legendary weapons/completionist
	"steam_1245620_LEGENDARY_ARMAMENTS": {
		"item_id": "elden_armory_set",
		"item_name": "Elden Armory Pauldrons",
		"item_type": ItemType.ARMOR_CHEST,
		"rarity": ItemRarity.EPIC,
		"description": "Shoulder guards blessed by all legendary armaments.",
		"lore": "The bearer has touched every legendary weapon in the Lands Between.",
		"achievement_name": "Legendary Armaments",
		"unlock_percent": 11.2,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "armor/elden_armory_pauldrons.png",
			"walk": FORGED_ITEMS_BASE + "armor/chest/elden_armory/walk.png",
			"slash": FORGED_ITEMS_BASE + "armor/chest/elden_armory/slash.png",
			"thrust": FORGED_ITEMS_BASE + "armor/chest/elden_armory/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "armor/chest/elden_armory/hurt.png"
		},
		"effects": ["golden_sparkle"],
		"cosmetic_only": true
	},

	# Legendary Tier (<1% unlock) - Platinum / 100% completion
	"steam_1245620_ELDEN_LORD": {
		"item_id": "elden_lord_crown",
		"item_name": "Elden Lord's Crown",
		"item_type": ItemType.ARMOR_HEAD,
		"rarity": ItemRarity.LEGENDARY,
		"description": "Crown of one who claimed the Elden Ring.",
		"lore": "Rise, Tarnished. Claim your rightful throne.",
		"achievement_name": "Elden Ring",
		"unlock_percent": 8.7,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "armor/elden_lord_crown.png",
			"walk": FORGED_ITEMS_BASE + "armor/head/elden_lord/walk.png",
			"slash": FORGED_ITEMS_BASE + "armor/head/elden_lord/slash.png",
			"thrust": FORGED_ITEMS_BASE + "armor/head/elden_lord/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "armor/head/elden_lord/hurt.png"
		},
		"effects": ["erdtree_blessing", "golden_leaves", "light_rays"],
		"cosmetic_only": true
	},

	# ═══════════════════════════════════════════════════════════════════════════
	# DARK SOULS 3 (Steam App ID: 374320)
	# 43 achievements - Classic FromSoftware
	# ═══════════════════════════════════════════════════════════════════════════

	"steam_374320_IUDEX_GUNDYR": {
		"item_id": "coiled_sword_fragment",
		"item_name": "Coiled Sword Fragment",
		"item_type": ItemType.ACCESSORY,
		"rarity": ItemRarity.COMMON,
		"description": "A fragment of the sword that links the First Flame.",
		"lore": "The first step on a long, dark journey.",
		"achievement_name": "Iudex Gundyr",
		"unlock_percent": 85.2,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "accessories/coiled_sword_fragment.png"
		},
		"effects": ["ember_glow"],
		"cosmetic_only": true
	},

	"steam_374320_ABYSS_WATCHERS": {
		"item_id": "farron_greatsword",
		"item_name": "Farron Greatsword",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.GREATSWORD,
		"rarity": ItemRarity.UNCOMMON,
		"description": "Greatsword of the Abyss Watchers.",
		"lore": "They partook of wolf blood, and hunted the abyss.",
		"achievement_name": "Abyss Watchers",
		"unlock_percent": 48.3,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/farron_greatsword.png",
			"walk": FORGED_ITEMS_BASE + "weapons/farron_greatsword/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/farron_greatsword/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/farron_greatsword/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/farron_greatsword/hurt.png"
		},
		"effects": ["wolf_blood_aura"],
		"stats": {"damage_bonus": 2},
		"cosmetic_only": false
	},

	"steam_374320_NAMELESS_KING": {
		"item_id": "dragonslayer_swordspear",
		"item_name": "Dragonslayer Swordspear",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.SPEAR,
		"rarity": ItemRarity.RARE,
		"description": "Cross-spear of the Nameless King.",
		"lore": "The firstborn son, erased from history.",
		"achievement_name": "Nameless King",
		"unlock_percent": 21.7,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/dragonslayer_swordspear.png",
			"walk": FORGED_ITEMS_BASE + "weapons/dragonslayer_swordspear/walk.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/dragonslayer_swordspear/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/dragonslayer_swordspear/hurt.png"
		},
		"effects": ["lightning_crackle", "storm_particles"],
		"stats": {"damage_bonus": 3, "lightning_damage": 2},
		"cosmetic_only": false
	},

	"steam_374320_THE_DARK_SOUL": {
		"item_id": "coiled_sword",
		"item_name": "Coiled Sword",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.SWORD,
		"rarity": ItemRarity.LEGENDARY,
		"description": "A sword twisted by the First Flame.",
		"lore": "Wielded by those who linked the fire. All achievements obtained.",
		"achievement_name": "The Dark Soul",
		"unlock_percent": 3.8,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/coiled_sword.png",
			"walk": FORGED_ITEMS_BASE + "weapons/coiled_sword/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/coiled_sword/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/coiled_sword/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/coiled_sword/hurt.png"
		},
		"effects": ["ember_trail", "flame_idle_glow", "heat_distortion"],
		"stats": {"damage_bonus": 5, "fire_damage": 3},
		"cosmetic_only": false
	},

	# ═══════════════════════════════════════════════════════════════════════════
	# STARDEW VALLEY (Steam App ID: 413150)
	# 49 achievements - Cozy farming, wide appeal
	# ═══════════════════════════════════════════════════════════════════════════

	"steam_413150_GREENHORN": {
		"item_id": "farmers_straw_hat",
		"item_name": "Farmer's Straw Hat",
		"item_type": ItemType.ARMOR_HEAD,
		"rarity": ItemRarity.COMMON,
		"description": "A humble hat for an honest farmer.",
		"lore": "Every legend starts somewhere. Yours started in the valley.",
		"achievement_name": "Greenhorn",
		"unlock_percent": 89.4,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "armor/farmers_straw_hat.png",
			"walk": FORGED_ITEMS_BASE + "armor/head/straw_hat/walk.png",
			"slash": FORGED_ITEMS_BASE + "armor/head/straw_hat/slash.png",
			"thrust": FORGED_ITEMS_BASE + "armor/head/straw_hat/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "armor/head/straw_hat/hurt.png"
		},
		"effects": [],
		"cosmetic_only": true
	},

	"steam_413150_SINGULAR_TALENT": {
		"item_id": "master_farmers_hoe",
		"item_name": "Master Farmer's Hoe",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.AXE,  # Closest to hoe mechanically
		"rarity": ItemRarity.UNCOMMON,
		"description": "A golden hoe for the dedicated farmer.",
		"lore": "Level 10 in a skill. The valley remembers your dedication.",
		"achievement_name": "Singular Talent",
		"unlock_percent": 34.2,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "tools/master_hoe.png",
			"walk": FORGED_ITEMS_BASE + "tools/master_hoe/walk.png",
			"slash": FORGED_ITEMS_BASE + "tools/master_hoe/slash.png",
			"thrust": FORGED_ITEMS_BASE + "tools/master_hoe/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "tools/master_hoe/hurt.png"
		},
		"effects": ["golden_sparkle"],
		"stats": {"damage_bonus": 1},
		"cosmetic_only": false
	},

	"steam_413150_MYSTERY_OF_STARDROPS": {
		"item_id": "stardrop_pendant",
		"item_name": "Stardrop Pendant",
		"item_type": ItemType.ACCESSORY,
		"rarity": ItemRarity.EPIC,
		"description": "A pendant containing essence of all Stardrops.",
		"lore": "You found every Stardrop. The cosmos smile upon you.",
		"achievement_name": "Mystery of the Stardrops",
		"unlock_percent": 6.8,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "accessories/stardrop_pendant.png"
		},
		"effects": ["stardust_trail", "healing_aura"],
		"cosmetic_only": true
	},

	"steam_413150_FECTOR_CHALLENGE": {
		"item_id": "prairie_king_crown",
		"item_name": "Prairie King's Crown",
		"item_type": ItemType.ARMOR_HEAD,
		"rarity": ItemRarity.LEGENDARY,
		"description": "Crown of the legendary Prairie King.",
		"lore": "You beat Journey of the Prairie King without dying. Legendary.",
		"achievement_name": "Fector's Challenge",
		"unlock_percent": 0.8,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "armor/prairie_king_crown.png",
			"walk": FORGED_ITEMS_BASE + "armor/head/prairie_king/walk.png",
			"slash": FORGED_ITEMS_BASE + "armor/head/prairie_king/slash.png",
			"thrust": FORGED_ITEMS_BASE + "armor/head/prairie_king/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "armor/head/prairie_king/hurt.png"
		},
		"effects": ["pixel_sparkle", "retro_trail"],
		"cosmetic_only": true
	},

	# ═══════════════════════════════════════════════════════════════════════════
	# HOLLOW KNIGHT (Steam App ID: 367520)
	# 63 achievements - Metroidvania classic
	# ═══════════════════════════════════════════════════════════════════════════

	"steam_367520_COMPLETION": {
		"item_id": "pure_nail",
		"item_name": "Pure Nail",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.SWORD,
		"rarity": ItemRarity.UNCOMMON,
		"description": "The ultimate form of the Knight's nail.",
		"lore": "Forged in the pale ore of Hallownest.",
		"achievement_name": "Completion",
		"unlock_percent": 35.1,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/pure_nail.png",
			"walk": FORGED_ITEMS_BASE + "weapons/pure_nail/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/pure_nail/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/pure_nail/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/pure_nail/hurt.png"
		},
		"effects": ["void_particles"],
		"stats": {"damage_bonus": 2},
		"cosmetic_only": false
	},

	"steam_367520_VOID": {
		"item_id": "void_cloak",
		"item_name": "Shade Cloak",
		"item_type": ItemType.CAPE,
		"rarity": ItemRarity.RARE,
		"description": "A cloak woven from pure void.",
		"lore": "Embrace the void. Become one with the darkness.",
		"achievement_name": "Void",
		"unlock_percent": 12.4,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "capes/shade_cloak.png",
			"walk": FORGED_ITEMS_BASE + "capes/shade_cloak/walk.png",
			"slash": FORGED_ITEMS_BASE + "capes/shade_cloak/slash.png",
			"thrust": FORGED_ITEMS_BASE + "capes/shade_cloak/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "capes/shade_cloak/hurt.png"
		},
		"effects": ["void_trail", "shadow_dash"],
		"cosmetic_only": true
	},

	"steam_367520_EMBRACE_THE_VOID": {
		"item_id": "void_heart",
		"item_name": "Void Heart Charm",
		"item_type": ItemType.ACCESSORY,
		"rarity": ItemRarity.LEGENDARY,
		"description": "A charm pulsing with void energy.",
		"lore": "You completed the Pantheon of Hallownest. True master.",
		"achievement_name": "Embrace the Void",
		"unlock_percent": 1.2,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "accessories/void_heart.png"
		},
		"effects": ["void_aura", "shadow_tendrils", "dark_burst"],
		"cosmetic_only": true
	},

	# ═══════════════════════════════════════════════════════════════════════════
	# HADES (Steam App ID: 1145360)
	# 49 achievements - Roguelike masterpiece
	# ═══════════════════════════════════════════════════════════════════════════

	"steam_1145360_ESCAPED_TARTARUS": {
		"item_id": "stygian_blade_basic",
		"item_name": "Stygian Blade",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.SWORD,
		"rarity": ItemRarity.COMMON,
		"description": "Standard blade of the underworld.",
		"lore": "Your first escape from Tartarus. Many more to come.",
		"achievement_name": "Escaped Tartarus",
		"unlock_percent": 76.8,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/stygian_blade.png",
			"walk": FORGED_ITEMS_BASE + "weapons/stygian_blade/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/stygian_blade/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/stygian_blade/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/stygian_blade/hurt.png"
		},
		"effects": ["blood_red_glow"],
		"stats": {"damage_bonus": 1},
		"cosmetic_only": false
	},

	"steam_1145360_SLAYER": {
		"item_id": "exagryph_adamant_rail",
		"item_name": "Adamant Rail",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.GUN,  # Ranged weapon - uses Skorpio body for gun animations
		"rarity": ItemRarity.UNCOMMON,
		"description": "The legendary rail gun of the underworld.",
		"lore": "1000 enemies slain. Death incarnate.",
		"achievement_name": "Slayer",
		"unlock_percent": 28.5,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/adamant_rail.png",
			"walk": FORGED_ITEMS_BASE + "weapons/adamant_rail/walk.png"
			# Note: Guns don't have slash/thrust/hurt - they use walk animation for all poses
		},
		"effects": ["infernal_glow"],
		"stats": {"damage_bonus": 2},
		"cosmetic_only": false
	},

	"steam_1145360_END_OF_STORY": {
		"item_id": "zagreus_helm",
		"item_name": "Prince's Laurel Crown",
		"item_type": ItemType.ARMOR_HEAD,
		"rarity": ItemRarity.EPIC,
		"description": "Crown of the Prince of the Underworld.",
		"lore": "You completed the epilogue. The whole story, told.",
		"achievement_name": "End of Story",
		"unlock_percent": 4.7,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "armor/zagreus_helm.png",
			"walk": FORGED_ITEMS_BASE + "armor/head/zagreus_helm/walk.png",
			"slash": FORGED_ITEMS_BASE + "armor/head/zagreus_helm/slash.png",
			"thrust": FORGED_ITEMS_BASE + "armor/head/zagreus_helm/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "armor/head/zagreus_helm/hurt.png"
		},
		"effects": ["divine_glow", "laurel_particles"],
		"cosmetic_only": true
	},

	# ═══════════════════════════════════════════════════════════════════════════
	# TERRARIA (Steam App ID: 105600)
	# 104 achievements - Sandbox adventure
	# ═══════════════════════════════════════════════════════════════════════════

	"steam_105600_EYE_OF_CTHULHU": {
		"item_id": "eye_of_cthulhu_shield",
		"item_name": "Eye of Cthulhu Shield",
		"item_type": ItemType.SHIELD,
		"rarity": ItemRarity.COMMON,
		"description": "A shield fashioned from the Eye's remains.",
		"lore": "Your first major boss. The world trembles.",
		"achievement_name": "Slayer of Worlds",
		"unlock_percent": 54.2,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "shields/eye_shield.png",
			"walk": FORGED_ITEMS_BASE + "shields/eye_shield/walk.png"
		},
		"effects": ["eerie_glow"],
		"cosmetic_only": true
	},

	"steam_105600_CHAMPION_OF_TERRARIA": {
		"item_id": "terra_blade",
		"item_name": "Terra Blade",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.SWORD,
		"rarity": ItemRarity.LEGENDARY,
		"description": "The ultimate sword, forged from night and light.",
		"lore": "You defeated Moon Lord. Champion of Terraria.",
		"achievement_name": "Champion of Terraria",
		"unlock_percent": 5.8,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/terra_blade.png",
			"walk": FORGED_ITEMS_BASE + "weapons/terra_blade/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/terra_blade/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/terra_blade/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/terra_blade/hurt.png"
		},
		"effects": ["terra_beam", "green_glow", "sword_projectile"],
		"stats": {"damage_bonus": 5},
		"cosmetic_only": false
	},

	# ═══════════════════════════════════════════════════════════════════════════
	# SEKIRO (Steam App ID: 814380)
	# 34 achievements - Shinobi action
	# ═══════════════════════════════════════════════════════════════════════════

	"steam_814380_GYOUBU_MASATAKA": {
		"item_id": "gyoubu_spear",
		"item_name": "Gyoubu's Broken Horn Spear",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.SPEAR,
		"rarity": ItemRarity.COMMON,
		"description": "Spear of the demon general.",
		"lore": "MY NAME IS GYOUBU MASATAKA ONIWA!",
		"achievement_name": "Gyoubu Masataka Oniwa",
		"unlock_percent": 68.4,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/gyoubu_spear.png",
			"walk": FORGED_ITEMS_BASE + "weapons/gyoubu_spear/walk.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/gyoubu_spear/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/gyoubu_spear/hurt.png"
		},
		"effects": [],
		"stats": {"damage_bonus": 1},
		"cosmetic_only": false
	},

	"steam_814380_ALL_SKILLS": {
		"item_id": "mortal_blade",
		"item_name": "Mortal Blade",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.KATANA,
		"rarity": ItemRarity.LEGENDARY,
		"description": "A blade that can kill the undying.",
		"lore": "All skills mastered. True Shinobi.",
		"achievement_name": "All Skills",
		"unlock_percent": 7.2,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/mortal_blade.png",
			"walk": FORGED_ITEMS_BASE + "weapons/mortal_blade/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/mortal_blade/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/mortal_blade/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/mortal_blade/hurt.png"
		},
		"effects": ["crimson_slash", "death_kanji", "blood_mist"],
		"stats": {"damage_bonus": 4},
		"cosmetic_only": false
	},

	# ═══════════════════════════════════════════════════════════════════════════
	# THE WITCHER 3 (Steam App ID: 292030)
	# 78 achievements - Open world RPG
	# ═══════════════════════════════════════════════════════════════════════════

	"steam_292030_LILAC_GOOSEBERRIES": {
		"item_id": "witcher_silver_sword",
		"item_name": "Witcher's Silver Sword",
		"item_type": ItemType.WEAPON,
		"weapon_class": WeaponClass.SWORD,
		"rarity": ItemRarity.COMMON,
		"description": "A silver blade for hunting monsters.",
		"lore": "Wind's howling. Time to prepare.",
		"achievement_name": "Lilac and Gooseberries",
		"unlock_percent": 81.3,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "weapons/witcher_silver_sword.png",
			"walk": FORGED_ITEMS_BASE + "weapons/witcher_silver_sword/walk.png",
			"slash": FORGED_ITEMS_BASE + "weapons/witcher_silver_sword/slash.png",
			"thrust": FORGED_ITEMS_BASE + "weapons/witcher_silver_sword/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "weapons/witcher_silver_sword/hurt.png"
		},
		"effects": ["silver_gleam"],
		"stats": {"damage_bonus": 1},
		"cosmetic_only": false
	},

	"steam_292030_WALKED_PATH": {
		"item_id": "grandmaster_wolf_armor",
		"item_name": "Grandmaster Wolf Chest",
		"item_type": ItemType.ARMOR_CHEST,
		"rarity": ItemRarity.LEGENDARY,
		"description": "Armor of a legendary Witcher.",
		"lore": "Completed the game on Death March difficulty.",
		"achievement_name": "Walked the Path",
		"unlock_percent": 4.1,
		"sprites": {
			"icon": FORGED_ICONS_BASE + "armor/grandmaster_wolf_chest.png",
			"walk": FORGED_ITEMS_BASE + "armor/chest/grandmaster_wolf/walk.png",
			"slash": FORGED_ITEMS_BASE + "armor/chest/grandmaster_wolf/slash.png",
			"thrust": FORGED_ITEMS_BASE + "armor/chest/grandmaster_wolf/thrust.png",
			"hurt": FORGED_ITEMS_BASE + "armor/chest/grandmaster_wolf/hurt.png"
		},
		"effects": ["wolf_school_glow", "danger_sense"],
		"cosmetic_only": true
	}
}

# ═══════════════════════════════════════════════════════════════════════════════
# LOOKUP FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

## Get item data for a specific achievement
func get_item_for_achievement(provider: String, app_id: String, api_name: String) -> Dictionary:
	var key = "%s_%s_%s" % [provider, app_id, api_name]
	return FORGE_ITEMS.get(key, {})

## Get all forgeable achievement keys
func get_all_forgeable_keys() -> Array:
	return FORGE_ITEMS.keys()

## Get items by rarity
func get_items_by_rarity(rarity: ItemRarity) -> Array:
	var results = []
	for key in FORGE_ITEMS:
		if FORGE_ITEMS[key].get("rarity", ItemRarity.COMMON) == rarity:
			results.append(FORGE_ITEMS[key])
	return results

## Get items by type
func get_items_by_type(item_type: ItemType) -> Array:
	var results = []
	for key in FORGE_ITEMS:
		if FORGE_ITEMS[key].get("item_type", ItemType.ACCESSORY) == item_type:
			results.append(FORGE_ITEMS[key])
	return results

## Get items for a specific game
func get_items_for_game(provider: String, app_id: String) -> Array:
	var results = []
	var prefix = "%s_%s_" % [provider, app_id]
	for key in FORGE_ITEMS:
		if key.begins_with(prefix):
			results.append(FORGE_ITEMS[key])
	return results

## Check if achievement has a forge item
func has_forge_item(provider: String, app_id: String, api_name: String) -> bool:
	var key = "%s_%s_%s" % [provider, app_id, api_name]
	return FORGE_ITEMS.has(key)

## Get rarity color for display
func get_rarity_color(rarity: ItemRarity) -> Color:
	match rarity:
		ItemRarity.COMMON:
			return Color(0.6, 0.6, 0.6)  # Gray
		ItemRarity.UNCOMMON:
			return Color(0.2, 0.8, 0.2)  # Green
		ItemRarity.RARE:
			return Color(0.2, 0.6, 1.0)  # Blue
		ItemRarity.EPIC:
			return Color(0.7, 0.3, 0.9)  # Purple
		ItemRarity.LEGENDARY:
			return Color(1.0, 0.5, 0.0)  # Orange
	return Color.WHITE

## Get rarity name for display
func get_rarity_name(rarity: ItemRarity) -> String:
	match rarity:
		ItemRarity.COMMON:
			return "Common"
		ItemRarity.UNCOMMON:
			return "Uncommon"
		ItemRarity.RARE:
			return "Rare"
		ItemRarity.EPIC:
			return "Epic"
		ItemRarity.LEGENDARY:
			return "Legendary"
	return "Unknown"

# ═══════════════════════════════════════════════════════════════════════════════
# STATISTICS
# ═══════════════════════════════════════════════════════════════════════════════

## Get count of items by game
func get_item_count_by_game() -> Dictionary:
	var counts = {}
	for key in FORGE_ITEMS:
		var parts = key.split("_")
		if parts.size() >= 2:
			var game_key = "%s_%s" % [parts[0], parts[1]]
			counts[game_key] = counts.get(game_key, 0) + 1
	return counts

## Get total forge item count
func get_total_item_count() -> int:
	return FORGE_ITEMS.size()

## Print database summary
func print_summary() -> void:
	print("═══════════════════════════════════════════════════════════")
	print("FORGE ITEM DATABASE SUMMARY")
	print("═══════════════════════════════════════════════════════════")
	print("Total Items: %d" % get_total_item_count())
	print("")
	print("By Game:")
	var by_game = get_item_count_by_game()
	for game_key in by_game:
		print("  %s: %d items" % [game_key, by_game[game_key]])
	print("")
	print("By Rarity:")
	for rarity in ItemRarity.values():
		var items = get_items_by_rarity(rarity)
		print("  %s: %d items" % [get_rarity_name(rarity), items.size()])
	print("═══════════════════════════════════════════════════════════")
