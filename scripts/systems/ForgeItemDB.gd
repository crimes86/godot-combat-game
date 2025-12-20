extends Node
## ForgeItemDB - Maps achievements to in-game items
## Loads item data from backend/data/items.json at runtime
##
## This file now contains:
## - Enum definitions (ItemRarity, ItemType, WeaponClass)
## - Path constants for Godot assets
## - JSON loading logic
## - Utility/lookup functions
##
## The actual item data is stored in backend/data/items.json

# Item rarity thresholds (based on achievement unlock %)
# Legendary: < 1% unlock rate
# Epic: 1-5% unlock rate
# Rare: 5-15% unlock rate
# Uncommon: 15-40% unlock rate
# Common: 40%+ unlock rate

enum ItemRarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum ItemType { WEAPON, ARMOR_HEAD, ARMOR_CHEST, ARMOR_ARMS, ARMOR_LEGS, ARMOR_HANDS, ARMOR_FEET, CAPE, SHIELD, ACCESSORY, RING, AMULET, EMOTE, TITLE, TOOL }
# WeaponClass: Core (SWORD-RAPIER have animation data), Extended (rest fall back to core)
enum WeaponClass { SWORD, DAGGER, MACE, SPEAR, STAFF, AXE, RAPIER, GREATSWORD, KATANA, SABER, SCIMITAR, HALBERD, PIKE, TRIDENT, FLAIL, SCYTHE, BOW, CROSSBOW, GUN, BATTLE_RIFLE }

# Base paths for forged items (separate from regular loot)
const FORGED_ITEMS_BASE = "res://assets/equipment/forged/"
const FORGED_ICONS_BASE = "res://assets/icons/forged/"
# Prefer enhanced (upscaled) icons when present
const ENHANCED_ICONS_BASE = "res://assets/icons/enhanced/forged/"

# Path to JSON data file
const ITEMS_JSON_PATH = "res://backend/data/items.json"

# ═══════════════════════════════════════════════════════════════════════════════
# RUNTIME DATA (loaded from JSON)
# ═══════════════════════════════════════════════════════════════════════════════

## Master dictionary mapping achievement keys to item data
## Key format: "{provider}_{appid}_{achievement_api_name}"
## Built dynamically from items.json + achievement_mappings
var FORGE_ITEMS: Dictionary = {}

## Items indexed by item_id for fast lookup
var _items_by_id: Dictionary = {}

## Raw JSON data cache
var _json_data: Dictionary = {}

## Whether data has been loaded
var _loaded: bool = false

# ═══════════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_load_from_json()

## Load all item data from JSON file
func _load_from_json() -> void:
	if _loaded:
		return

	var file = FileAccess.open(ITEMS_JSON_PATH, FileAccess.READ)
	if not file:
		push_error("ForgeItemDB: Failed to open %s" % ITEMS_JSON_PATH)
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("ForgeItemDB: JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return

	_json_data = json.data

	# Build items_by_id lookup from items array
	var items_array = _json_data.get("items", [])
	for item in items_array:
		var item_id = item.get("item_id", "")
		if item_id != "":
			# Convert JSON format to FORGE_ITEMS format
			var converted = _convert_json_item(item)
			_items_by_id[item_id] = converted

	# Build FORGE_ITEMS from achievement_mappings
	var mappings = _json_data.get("achievement_mappings", {})
	for key in mappings:
		# Skip comment keys
		if key.begins_with("_"):
			continue

		var item_id = mappings[key]
		if _items_by_id.has(item_id):
			# Convert achievement mapping key format (app_id:api_name) to our format (provider_appid_apiname)
			var achievement_key = _convert_mapping_key_to_achievement_key(key)
			FORGE_ITEMS[achievement_key] = _items_by_id[item_id]

	_loaded = true
	print("ForgeItemDB: Loaded %d items, %d achievement mappings" % [_items_by_id.size(), FORGE_ITEMS.size()])

## Convert JSON item format to internal FORGE_ITEMS format
func _convert_json_item(json_item: Dictionary) -> Dictionary:
	var item = {}

	# Direct copies (with null safety)
	item["item_id"] = _safe_string(json_item.get("item_id"), "")
	item["item_name"] = _safe_string(json_item.get("item_name"), "Unknown")
	item["description"] = _safe_string(json_item.get("description"), "")
	item["lore"] = _safe_string(json_item.get("lore"), "")
	item["cosmetic_only"] = json_item.get("cosmetic_only", true) if json_item.get("cosmetic_only") != null else true

	# Convert item_type string to enum
	var item_type_str = _safe_string(json_item.get("item_type"), "accessory")
	item["item_type"] = _item_type_string_to_enum(item_type_str)

	# Convert rarity string to enum
	var rarity_str = _safe_string(json_item.get("base_rarity"), "common")
	item["rarity"] = _rarity_string_to_enum(rarity_str)

	# Convert weapon_type string to enum (if applicable)
	var weapon_type = json_item.get("weapon_type")
	if weapon_type != null and weapon_type is String and weapon_type != "":
		item["weapon_class"] = _weapon_class_string_to_enum(weapon_type)
		item["weapon_type"] = weapon_type  # Also preserve original string for inventory system

	# Build sprites dictionary from visuals
	var visuals = json_item.get("visuals")
	if visuals == null or not visuals is Dictionary:
		visuals = {}
	var sprites = {}

	# Icon path - convert from web path to Godot path
	var icon_url = _safe_string(visuals.get("icon_url"), "")
	if icon_url != "":
		# Convert /static/items/icons/xxx.png to local icon paths (prefer enhanced)
		var icon_filename = icon_url.get_file()
		# Determine subfolder based on item type
		var subfolder = _get_icon_subfolder(item["item_type"])
		var enhanced_subfolder_path = ENHANCED_ICONS_BASE + subfolder + "/" + icon_filename
		var enhanced_root_path = ENHANCED_ICONS_BASE + icon_filename
		var forged_subfolder_path = FORGED_ICONS_BASE + subfolder + "/" + icon_filename
		var forged_root_path = FORGED_ICONS_BASE + icon_filename

		# Try enhanced first, then fall back to forged
		if FileAccess.file_exists(enhanced_subfolder_path):
			sprites["icon"] = enhanced_subfolder_path
		elif FileAccess.file_exists(enhanced_root_path):
			sprites["icon"] = enhanced_root_path
		elif FileAccess.file_exists(forged_subfolder_path):
			sprites["icon"] = forged_subfolder_path
		elif FileAccess.file_exists(forged_root_path):
			sprites["icon"] = forged_root_path

	# Fallback icon lookup by item_id/name (covers cases where icon_url points to a different filename)
	if not sprites.has("icon"):
		var fallback_filename = item["item_id"].to_lower().replace(" ", "_").replace("-", "_").replace("'", "")
		var name_filename = _name_to_snake_case(item["item_name"])
		var subfolder = _get_icon_subfolder(item["item_type"])
		var candidates = [
			ENHANCED_ICONS_BASE + subfolder + "/" + fallback_filename + ".png",
			ENHANCED_ICONS_BASE + subfolder + "/" + name_filename + ".png",
			FORGED_ICONS_BASE + subfolder + "/" + fallback_filename + ".png",
			FORGED_ICONS_BASE + subfolder + "/" + name_filename + ".png",
		]
		for c in candidates:
			if FileAccess.file_exists(c):
				sprites["icon"] = c
				break

	# Sprite folder - build full paths
	var sprite_folder = _safe_string(visuals.get("sprite_folder"), "")
	if sprite_folder != "":
		sprites["walk"] = FORGED_ITEMS_BASE + sprite_folder + "/walk.png"
		sprites["slash"] = FORGED_ITEMS_BASE + sprite_folder + "/slash.png"
		sprites["thrust"] = FORGED_ITEMS_BASE + sprite_folder + "/thrust.png"
		sprites["hurt"] = FORGED_ITEMS_BASE + sprite_folder + "/hurt.png"
		# Bows/crossbows use shoot.png instead of slash/thrust
		var weapon_type_str = _safe_string(json_item.get("weapon_type"), "")
		if weapon_type_str in ["bow", "crossbow"]:
			sprites["shoot"] = FORGED_ITEMS_BASE + sprite_folder + "/shoot.png"

	item["sprites"] = sprites

	# Effects array
	var effects_obj = json_item.get("effects")
	if effects_obj == null or not effects_obj is Dictionary:
		effects_obj = {}
	var effects_array = []
	var passive_effects = effects_obj.get("passive")
	if passive_effects != null and passive_effects is Array:
		effects_array.append_array(passive_effects)
	item["effects"] = effects_array

	# Glow color
	var glow_color = _safe_string(visuals.get("glow_color"), "")
	if glow_color != "":
		item["glow_color"] = glow_color

	# Stats (legacy format)
	var stats = json_item.get("stats")
	if stats != null and stats is Dictionary and not stats.is_empty():
		item["stats"] = stats

	# Combat stats (new format from items.json)
	# base_damage can be {"min": X, "max": Y} dict or single number
	var base_damage = json_item.get("base_damage")
	if base_damage != null:
		if base_damage is Dictionary:
			# Use average of min/max for single value
			var dmg_min = base_damage.get("min", 0)
			var dmg_max = base_damage.get("max", 0)
			item["base_damage"] = (dmg_min + dmg_max) / 2.0
			item["base_damage_min"] = dmg_min
			item["base_damage_max"] = dmg_max
		else:
			item["base_damage"] = float(base_damage)

	var attack_speed = json_item.get("attack_speed")
	if attack_speed != null:
		item["attack_speed"] = attack_speed

	# NOTE: Crit chance removed from weapons - now purely stat-based (DEX for melee, WIS for caster)

	var defense = json_item.get("defense")
	if defense != null:
		item["defense"] = defense

	var stat_bonuses = json_item.get("stat_bonuses")
	if stat_bonuses != null and stat_bonuses is Dictionary:
		item["stat_bonuses"] = stat_bonuses

	var hp_bonus = json_item.get("hp_bonus")
	if hp_bonus != null:
		item["hp_bonus"] = hp_bonus

	var lifesteal = json_item.get("lifesteal")
	if lifesteal != null:
		item["lifesteal"] = lifesteal

	var cooldown_reduction = json_item.get("cooldown_reduction")
	if cooldown_reduction != null:
		item["cooldown_reduction"] = cooldown_reduction

	var movement_speed = json_item.get("movement_speed")
	if movement_speed != null:
		item["movement_speed"] = movement_speed

	# Gun config - also extract root-level gun properties for inventory system
	var gun_config = json_item.get("gun_config")
	if gun_config != null and gun_config is Dictionary and not gun_config.is_empty():
		item["gun_config"] = gun_config

	# Extract gun properties from either gun_config or root level
	var gun_subtype = json_item.get("gun_subtype")
	if gun_subtype == null and gun_config != null:
		gun_subtype = gun_config.get("gun_subtype")
	if gun_subtype != null:
		item["gun_subtype"] = gun_subtype

	var burst_count = json_item.get("burst_count")
	if burst_count == null and gun_config != null:
		burst_count = gun_config.get("burst_count")
	if burst_count != null:
		item["burst_count"] = burst_count

	var burst_delay = json_item.get("burst_delay")
	if burst_delay == null and gun_config != null:
		burst_delay = gun_config.get("burst_delay")
	if burst_delay != null:
		item["burst_delay"] = burst_delay

	# Two-handed flag
	if json_item.get("is_two_handed", false):
		item["is_two_handed"] = true

	# Multi-slash flag
	if json_item.get("multi_slash", false):
		item["multi_slash"] = true

	# Visual override slots (for outfits like loremaster_hood)
	var visual_overrides = json_item.get("visual_override_slots")
	if visual_overrides != null and visual_overrides is Dictionary and not visual_overrides.is_empty():
		item["visual_override_slots"] = visual_overrides

	return item

## Safe string getter - returns default if value is null or not a string
func _safe_string(value, default: String) -> String:
	if value == null:
		return default
	if value is String:
		return value
	return default

## Convert a display name to snake_case (matches ItemIconGenerator convention)
func _name_to_snake_case(name: String) -> String:
	return name.to_lower().replace(" ", "_").replace("'", "").replace("-", "_")

## Convert achievement mapping key format to FORGE_ITEMS key format
## Input: "app_id:api_name" or "provider:api_name"
## Output: "steam_appid_apiname" or "provider_apiname"
func _convert_mapping_key_to_achievement_key(mapping_key: String) -> String:
	var parts = mapping_key.split(":")
	if parts.size() < 2:
		return mapping_key

	var provider_or_appid = parts[0]

	# Check if it's a numeric Steam app ID
	if provider_or_appid.is_valid_int():
		var api_name = parts[1]
		return "steam_%s_%s" % [provider_or_appid, api_name]
	elif provider_or_appid == "battlenet" and parts.size() >= 3:
		# Battlenet uses 3-part format: battlenet:game:achievement
		# e.g., "battlenet:diablo4:SEASON_JOURNEY_GUARDIAN"
		var game = parts[1]
		var achievement = parts[2]
		return "battlenet_%s_%s" % [game, achievement]
	else:
		# Provider like "xbox", "psn", "discord", "github", "roblox" (2-part format)
		var api_name = parts[1]
		return "%s_%s" % [provider_or_appid, api_name]

## Get icon subfolder based on item type
func _get_icon_subfolder(item_type: ItemType) -> String:
	match item_type:
		ItemType.WEAPON:
			return "weapons"
		ItemType.ARMOR_HEAD, ItemType.ARMOR_CHEST, ItemType.ARMOR_ARMS, ItemType.ARMOR_LEGS, ItemType.ARMOR_HANDS, ItemType.ARMOR_FEET:
			return "armor"
		ItemType.SHIELD:
			return "shields"
		ItemType.CAPE:
			return "capes"
		ItemType.ACCESSORY, ItemType.RING, ItemType.AMULET:
			return "accessories"
		ItemType.TOOL:
			return "tools"
		_:
			return "misc"

# ═══════════════════════════════════════════════════════════════════════════════
# ENUM CONVERSIONS
# ═══════════════════════════════════════════════════════════════════════════════

func _rarity_string_to_enum(rarity_str: String) -> ItemRarity:
	match rarity_str.to_lower():
		"common": return ItemRarity.COMMON
		"uncommon": return ItemRarity.UNCOMMON
		"rare": return ItemRarity.RARE
		"epic": return ItemRarity.EPIC
		"legendary": return ItemRarity.LEGENDARY
		_: return ItemRarity.COMMON

func _item_type_string_to_enum(type_str: String) -> ItemType:
	match type_str.to_lower():
		"weapon": return ItemType.WEAPON
		"armor_head": return ItemType.ARMOR_HEAD
		"armor_chest": return ItemType.ARMOR_CHEST
		"armor_arms": return ItemType.ARMOR_ARMS
		"armor_legs": return ItemType.ARMOR_LEGS
		"armor_hands": return ItemType.ARMOR_HANDS
		"armor_feet": return ItemType.ARMOR_FEET
		"cape": return ItemType.CAPE
		"shield": return ItemType.SHIELD
		"accessory": return ItemType.ACCESSORY
		"ring": return ItemType.RING
		"amulet": return ItemType.AMULET
		"emote": return ItemType.EMOTE
		"title": return ItemType.TITLE
		"tool": return ItemType.TOOL
		_: return ItemType.ACCESSORY

func _weapon_class_string_to_enum(weapon_str: String) -> WeaponClass:
	match weapon_str.to_lower():
		"sword": return WeaponClass.SWORD
		"dagger": return WeaponClass.DAGGER
		"mace": return WeaponClass.MACE
		"spear": return WeaponClass.SPEAR
		"staff": return WeaponClass.STAFF
		"axe": return WeaponClass.AXE
		"rapier": return WeaponClass.RAPIER
		"greatsword": return WeaponClass.GREATSWORD
		"katana": return WeaponClass.KATANA
		"saber": return WeaponClass.SABER
		"scimitar": return WeaponClass.SCIMITAR
		"halberd": return WeaponClass.HALBERD
		"pike": return WeaponClass.PIKE
		"trident": return WeaponClass.TRIDENT
		"flail": return WeaponClass.FLAIL
		"scythe": return WeaponClass.SCYTHE
		"bow": return WeaponClass.BOW
		"crossbow": return WeaponClass.CROSSBOW
		"gun": return WeaponClass.GUN
		"battle_rifle": return WeaponClass.BATTLE_RIFLE
		_: return WeaponClass.SWORD

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

## Get item data by item_id (e.g., "loremaster_hood", "straw_hat")
func get_item_by_id(item_id: String) -> Dictionary:
	return _items_by_id.get(item_id, {})

## Get items by rarity
func get_items_by_rarity(rarity: ItemRarity) -> Array:
	var results = []
	for item_id in _items_by_id:
		var item = _items_by_id[item_id]
		if item.get("rarity", ItemRarity.COMMON) == rarity:
			results.append(item)
	return results

## Get items by type
func get_items_by_type(item_type: ItemType) -> Array:
	var results = []
	for item_id in _items_by_id:
		var item = _items_by_id[item_id]
		if item.get("item_type", ItemType.ACCESSORY) == item_type:
			results.append(item)
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
	return _items_by_id.size()

## Game name lookup from achievement key (for Armory display)
const GAME_NAMES = {
	"1245620": "Elden Ring",
	"374320": "Dark Souls III",
	"413150": "Stardew Valley",
	"105600": "Terraria",
	"367520": "Hollow Knight",
	"1145360": "Hades",
	"292030": "The Witcher 3",
	"72850": "Skyrim",
	"582010": "Monster Hunter World",
	"814380": "Sekiro",
	"620": "Portal 2",
	"220": "Half-Life 2",
	"550": "Left 4 Dead 2",
	"268500": "XCOM 2",
	"504230": "Celeste",
	"646570": "Slay the Spire",
	"588650": "Dead Cells",
	"268910": "Cuphead",
	"BLOODBORNE": "Bloodborne",
	"DEMONS_SOULS": "Demon's Souls",
	"MCC": "Halo MCC",
	"battlenet": "World of Warcraft",
	"discord": "Discord",
	"github": "GitHub",
}

## Convert ItemType enum to category string for Armory
func _type_to_category(item_type: ItemType) -> String:
	match item_type:
		ItemType.WEAPON:
			return "weapons"
		ItemType.ARMOR_HEAD, ItemType.ARMOR_CHEST, ItemType.ARMOR_ARMS, ItemType.ARMOR_LEGS, ItemType.ARMOR_HANDS, ItemType.ARMOR_FEET:
			return "armor"
		ItemType.SHIELD:
			return "shields"
		ItemType.CAPE:
			return "capes"
		ItemType.RING, ItemType.AMULET:
			return "jewelry"
		ItemType.ACCESSORY:
			return "accessories"
		_:
			return "misc"

## Get game name from achievement key
func _get_game_from_key(key: String) -> String:
	var parts = key.split("_")
	if parts.size() < 2:
		return "Unknown"

	var provider = parts[0]
	var game_id = parts[1]

	# Providers where the provider name IS the game (battlenet=WoW, discord, github, roblox)
	if provider in ["battlenet", "discord", "github", "roblox"]:
		return GAME_NAMES.get(provider, provider.capitalize())

	# Handle PSN/Xbox/etc with underscore in game name
	if provider in ["psn", "xbox"]:
		return GAME_NAMES.get(game_id, game_id.replace("_", " ").capitalize())

	# Steam: provider_appid_achievement - look up by app ID
	return GAME_NAMES.get(game_id, "Steam")

## Generate catalog array for Armory UI (dynamic generation from items)
## Returns array of dictionaries with: id, name, game, achievement, rarity, category, icon, lore
func get_armory_catalog() -> Array:
	var catalog = []

	for key in FORGE_ITEMS:
		var item = FORGE_ITEMS[key]
		var item_type_enum = item.get("item_type", ItemType.ACCESSORY)
		var entry = {
			"id": item.get("item_id", ""),
			"name": item.get("item_name", "Unknown Item"),
			"game": _get_game_from_key(key),
			"achievement": item.get("achievement_name", ""),
			"rarity": get_rarity_name(item.get("rarity", ItemRarity.COMMON)),
			"category": _type_to_category(item_type_enum),
			"item_type": ItemType.keys()[item_type_enum].to_lower(),  # e.g. "armor_chest", "weapon"
			"icon": item.get("sprites", {}).get("icon", ""),
			"lore": item.get("lore", item.get("description", ""))
		}
		catalog.append(entry)

	return catalog

## Print database summary
func print_summary() -> void:
	print("═══════════════════════════════════════════════════════════")
	print("FORGE ITEM DATABASE SUMMARY")
	print("═══════════════════════════════════════════════════════════")
	print("Total Items: %d" % get_total_item_count())
	print("Achievement Mappings: %d" % FORGE_ITEMS.size())
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

# ═══════════════════════════════════════════════════════════════════════════════
# ASSET VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

## Validate all forged item assets exist on disk
## Call this at startup or from debug menu to check for missing assets
## Returns: Dictionary with "missing_icons", "missing_sprites", "valid_count", "total_count"
func validate_assets(verbose: bool = false) -> Dictionary:
	var missing_icons = []
	var missing_sprites = []
	var valid_count = 0
	var total_count = _items_by_id.size()

	for item_id in _items_by_id:
		var item = _items_by_id[item_id]
		var item_name = item.get("item_name", "Unknown")
		var sprites = item.get("sprites", {})
		var item_type = item.get("item_type", ItemType.ACCESSORY)
		var is_valid = true

		# Check icon
		var icon_path = sprites.get("icon", "")
		if icon_path != "" and not ResourceLoader.exists(icon_path):
			missing_icons.append({
				"item_id": item_id,
				"item_name": item_name,
				"expected_path": icon_path
			})
			is_valid = false
			if verbose:
				push_warning("ForgeItemDB: Missing icon for '%s' at: %s" % [item_name, icon_path])

		# Check sprites (only for non-accessory items that should have sprites)
		var needs_sprites = item_type in [ItemType.WEAPON, ItemType.ARMOR_HEAD, ItemType.ARMOR_CHEST,
			ItemType.ARMOR_ARMS, ItemType.ARMOR_LEGS, ItemType.ARMOR_HANDS, ItemType.ARMOR_FEET,
			ItemType.CAPE, ItemType.SHIELD]

		if needs_sprites:
			var sprite_types = ["walk", "slash", "thrust", "hurt"]
			var missing_for_item = []

			for sprite_type in sprite_types:
				var sprite_path = sprites.get(sprite_type, "")
				if sprite_path != "" and not ResourceLoader.exists(sprite_path):
					missing_for_item.append(sprite_type)

			if missing_for_item.size() > 0:
				missing_sprites.append({
					"item_id": item_id,
					"item_name": item_name,
					"missing_types": missing_for_item
				})
				is_valid = false
				if verbose:
					push_warning("ForgeItemDB: Missing sprites for '%s': %s" % [item_name, missing_for_item])

		if is_valid:
			valid_count += 1

	var result = {
		"missing_icons": missing_icons,
		"missing_sprites": missing_sprites,
		"valid_count": valid_count,
		"total_count": total_count
	}

	if verbose:
		print("═══════════════════════════════════════════════════════════")
		print("FORGE ITEM ASSET VALIDATION")
		print("═══════════════════════════════════════════════════════════")
		print("Total Items: %d" % total_count)
		print("Valid Items: %d" % valid_count)
		print("Missing Icons: %d" % missing_icons.size())
		print("Missing Sprites: %d" % missing_sprites.size())
		if missing_icons.size() > 0:
			print("")
			print("Items with missing icons:")
			for item in missing_icons:
				print("  - %s (%s)" % [item.item_name, item.item_id])
		if missing_sprites.size() > 0:
			print("")
			print("Items with missing sprites:")
			for item in missing_sprites:
				print("  - %s (%s): %s" % [item.item_name, item.item_id, item.missing_types])
		print("═══════════════════════════════════════════════════════════")

	return result

## Quick check if a specific item has valid assets
func item_has_valid_assets(item_id: String) -> Dictionary:
	var item = get_item_by_id(item_id)
	if item.is_empty():
		return {"valid": false, "error": "Item not found"}

	var sprites = item.get("sprites", {})
	var has_icon = false
	var has_sprites = false

	# Check icon
	var icon_path = sprites.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		has_icon = true

	# Check walk sprite as indicator of full sprite set
	var walk_path = sprites.get("walk", "")
	if walk_path != "" and ResourceLoader.exists(walk_path):
		has_sprites = true

	return {
		"valid": has_icon,
		"has_icon": has_icon,
		"has_sprites": has_sprites,
		"item_id": item_id,
		"item_name": item.get("item_name", "Unknown")
	}
