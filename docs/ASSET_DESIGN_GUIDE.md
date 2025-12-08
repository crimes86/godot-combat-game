# Asset Design Guide for Godot Engineers

> How to build weapons, armor, and cosmetics that integrate seamlessly with the Mantle achievement system.

---

## The Core Concept

Players don't choose their tier cosmetics - **they earn them**. The backend knows:
- What achievements the player has unlocked
- What platforms they've linked (Steam, Battle.net, Xbox, PlayStation)
- Their overall tier (Initiate → Mythic)
- Which specific prestigious achievements they've completed

Your job: Build assets that the `MantleCosmetics` autoload can apply based on API data.

---

## Asset Naming Convention

**Critical:** Asset filenames must match API identifiers exactly.

### Tier-Based Assets
```
res://assets/armor/{tier}_{slot}.png
res://assets/effects/{tier}_{effect_name}.tscn

Examples:
res://assets/armor/initiate_chest.png
res://assets/armor/gold_chest.png
res://assets/armor/mythic_chest.png
res://assets/effects/legendary_ember_aura.tscn
res://assets/effects/mythic_particle_trail.tscn
```

### Provider Badge Assets
```
res://assets/badges/{provider}_verified.png

Examples:
res://assets/badges/steam_verified.png
res://assets/badges/battlenet_verified.png
res://assets/badges/xbox_verified.png
res://assets/badges/playstation_verified.png
```

### Achievement-Specific Assets
```
res://assets/unlocks/{provider}_{app_id}_{achievement_api_name}.tscn

Examples:
res://assets/unlocks/steam_374320_THE_DARK_SOUL.tscn      # Dark Souls 3 100%
res://assets/unlocks/steam_1245620_ELDEN_LORD.tscn        # Elden Ring
res://assets/unlocks/battlenet_wow_thunderfury.tscn       # WoW legendary
```

---

## Tier Visual Hierarchy

Each tier should be **visually distinct at a glance**. Higher tiers = more visual complexity.

| Tier | Color | Visual Budget | Effects Allowed |
|------|-------|---------------|-----------------|
| Initiate | #666666 (Gray) | Minimal | None |
| Bronze | #CD7F32 | Low | Subtle color tint |
| Silver | #C0C0C0 | Low-Medium | Metallic highlights |
| Gold | #FFD700 | Medium | Soft glow, gold trim |
| Platinum | #E5E4E2 | Medium-High | Soft blue glow, shimmer |
| Diamond | #B9F2FF | High | Crystal sparkles, refractions |
| Legendary | #FF6600 | High | Fire/ember particles, heat distortion |
| Mythic | #FF00FF | Maximum | Ethereal aura, ground runes, particle trails |

### Design Principles

1. **Initiate should look worn, not shameful** - Basic cloth/leather, but not ugly
2. **Each tier upgrade should feel earned** - Clear visual progression
3. **Top tiers should be unmistakable** - A Mythic player should be recognizable across the map
4. **Effects should not obstruct gameplay** - Cool but not distracting

---

## LPC Sprite Layer Integration

The character uses a 9-layer sprite system. Mantle cosmetics apply to specific layers:

| Layer | Z-Index | Purpose | Mantle Control |
|-------|---------|---------|----------------|
| Shadow | 0 | Ground shadow | Tier intensity |
| Body | 1 | Base body | Tier glow/tint |
| Head | 2 | Head cosmetics | Achievement unlocks |
| Hair | 3 | Hair style | Player choice (no override) |
| Pants | 4 | Leg armor | Tier-based |
| Shirt | 5 | Chest armor | Tier-based |
| Arms | 6 | Arm armor/bracers | Tier-based |
| Boots | 7 | Footwear | Tier-based |
| Hands | 8 | Gloves/gauntlets | Tier-based |
| Weapon | 9 | Weapon skin | Achievement unlocks |
| Effects | 10+ | Auras, particles | Tier + achievements |

### Asset Requirements Per Layer

Each armor piece needs these sprite sheets (LPC standard):

```
{tier}_{slot}_idle.png      # 4 directions, standing
{tier}_{slot}_walk.png      # 4 directions, 8 frames each
{tier}_{slot}_attack.png    # 4 directions, 6 frames each
{tier}_{slot}_hurt.png      # 4 directions, 2 frames each
{tier}_{slot}_death.png     # 4 directions, 6 frames each
```

**Dimensions:** 64x64 per frame (LPC standard)

---

## Effect Scenes Structure

Particle effects and auras should be self-contained scenes:

```gdscript
# res://assets/effects/legendary_ember_aura.tscn

extends Node2D

@onready var particles = $GPUParticles2D
@onready var glow = $PointLight2D

func set_intensity(value: float):
    particles.amount = int(lerp(10, 50, value))
    glow.energy = lerp(0.5, 2.0, value)

func play_burst():
    # For transformation sequence
    particles.emitting = true
    var tween = create_tween()
    tween.tween_property(glow, "energy", 3.0, 0.2)
    tween.tween_property(glow, "energy", 1.0, 0.5)
```

### Effect Guidelines

| Tier | Max Particles | Light Energy | Trail Length |
|------|--------------|--------------|--------------|
| Gold | 20 | 0.5 | None |
| Platinum | 30 | 0.8 | Short |
| Diamond | 40 | 1.0 | Medium |
| Legendary | 60 | 1.5 | Long |
| Mythic | 100 | 2.0 | Infinite trail |

---

## API Response → Asset Mapping

When a player authenticates, the API returns a profile like this:

```json
{
  "user_id": 12345,
  "username": "VeteranPlayer",
  "tier": "legendary",
  "total_achievements": 5200,
  "providers": [
    {"name": "steam", "total": 3500},
    {"name": "battlenet", "total": 1700}
  ],
  "by_rarity": {
    "Common": 2100,
    "Uncommon": 1800,
    "Rare": 900,
    "Epic": 320,
    "Legendary": 80
  },
  "notable_achievements": [
    {
      "provider": "steam",
      "app_id": "374320",
      "api_name": "THE_DARK_SOUL",
      "display_name": "The Dark Soul",
      "rarity_tier": "Legendary",
      "is_original_claim": true
    }
  ],
  "forged_items": [
    {
      "token_id": "0x123...",
      "achievement_api_name": "THE_DARK_SOUL",
      "is_earned": true
    }
  ]
}
```

### MantleCosmetics Resolution Logic

```gdscript
# This is how MantleCosmetics decides what to apply

func resolve_cosmetics(profile: Dictionary) -> Dictionary:
    var result = {}

    # 1. Base tier armor (always applied)
    var tier = profile.get("tier", "initiate")
    result["armor_set"] = load_tier_armor(tier)
    result["base_effects"] = load_tier_effects(tier)

    # 2. Provider badges (for each linked platform)
    result["badges"] = []
    for provider in profile.get("providers", []):
        result["badges"].append(load_provider_badge(provider["name"]))

    # 3. Achievement-specific overrides (prestige items)
    for ach in profile.get("notable_achievements", []):
        var unlock_path = "res://assets/unlocks/%s_%s_%s.tscn" % [
            ach["provider"], ach["app_id"], ach["api_name"]
        ]
        if ResourceLoader.exists(unlock_path):
            var unlock = load(unlock_path)
            result["overrides"].append(unlock)

    # 4. Forged items with provenance indicator
    for item in profile.get("forged_items", []):
        result["forged"].append({
            "item": load_forged_item(item["achievement_api_name"]),
            "is_earned": item["is_earned"]  # Gold vs Silver badge
        })

    return result
```

---

## Forged Item Provenance

Forged items (NFTs) show whether the player **earned** or **traded** for them:

| Provenance | Badge Color | Tooltip |
|------------|-------------|---------|
| EARNED | Gold | "Unlocked by {username}" |
| TRADED | Silver | "Acquired via trade" |

Both are valid ownership, but **earned** carries more prestige.

### Implementing Provenance Display

```gdscript
func display_forged_item(item_data: Dictionary):
    var badge = $ProvenanceBadge

    if item_data["is_earned"]:
        badge.texture = preload("res://assets/ui/badge_earned_gold.png")
        badge.tooltip_text = "EARNED - Original achievement holder"
    else:
        badge.texture = preload("res://assets/ui/badge_traded_silver.png")
        badge.tooltip_text = "TRADED - Acquired from marketplace"
```

---

## The Transformation Sequence

**This is the viral moment.** When a player first logs in with linked accounts:

### Sequence Timeline

| Time | Event | Assets Needed |
|------|-------|---------------|
| 0.0s | Character in basic Initiate gear | `initiate_*` set |
| 0.5s | Camera slight zoom | N/A (code) |
| 0.8s | Particles swirl around character | `transformation_swirl.tscn` |
| 1.2s | Boots materialize | Tier boots + `materialize.tscn` |
| 1.5s | Pants materialize | Tier pants |
| 1.8s | Chest materialize | Tier chest |
| 2.1s | Arms materialize | Tier arms |
| 2.4s | Head/helm materialize | Tier head |
| 2.8s | Weapon appears | Achievement weapon (if any) |
| 3.2s | Tier aura fades in | Tier effects |
| 3.5s | Final flash | `transformation_complete.tscn` |
| 4.0s | Done | Full cosmetic state |

### Required Transformation Assets

```
res://assets/effects/transformation/
├── swirl_particles.tscn        # Initial buildup
├── materialize_flash.tscn      # Per-slot appearance
├── tier_reveal_{tier}.tscn     # Tier-specific finale
└── complete_flash.tscn         # Final pulse
```

### Key Animation Principles

1. **Build anticipation** - The swirl before reveal
2. **Layer reveals create rhythm** - Don't show everything at once
3. **The finale matches tier** - Initiate = subtle fade, Mythic = explosive
4. **Other players see this** - Multiplayer visibility is key

---

## Multiplayer Considerations

### Badge Visibility
Every player's tier badge should be visible at reasonable zoom levels:

```gdscript
# Badge scales with camera zoom to stay readable
func _process(_delta):
    var zoom = get_viewport().get_camera_2d().zoom
    $TierBadge.scale = Vector2.ONE / zoom  # Counter zoom
```

### Effect Performance
High-tier effects must be LOD-aware:

```gdscript
func set_lod_level(level: int):
    match level:
        0:  # Close - full effects
            particles.amount = max_particles
            glow.visible = true
        1:  # Medium - reduced
            particles.amount = max_particles / 2
            glow.visible = true
        2:  # Far - minimal
            particles.amount = 0
            glow.visible = false
```

---

## Rarity Color Reference

Use these colors consistently across all UI and effects:

```gdscript
const RARITY_COLORS = {
    "Common": Color("#9d9d9d"),
    "Uncommon": Color("#1eff00"),
    "Rare": Color("#0070dd"),
    "Epic": Color("#a335ee"),
    "Legendary": Color("#ff8000")
}

const TIER_COLORS = {
    "initiate": Color("#666666"),
    "bronze": Color("#cd7f32"),
    "silver": Color("#c0c0c0"),
    "gold": Color("#ffd700"),
    "platinum": Color("#e5e4e2"),
    "diamond": Color("#b9f2ff"),
    "legendary": Color("#ff6600"),
    "mythic": Color("#ff00ff")
}
```

---

## Asset Checklist

### Per Tier (8 tiers total)
- [ ] Chest armor (5 animation states)
- [ ] Pants (5 animation states)
- [ ] Boots (5 animation states)
- [ ] Arms/bracers (5 animation states)
- [ ] Gloves (5 animation states)
- [ ] Head/helm (5 animation states)
- [ ] Tier aura effect scene
- [ ] Tier transformation finale

### Per Provider (4 providers)
- [ ] Verified badge icon (32x32)
- [ ] Provider accent color defined

### Achievement Unlocks (as prioritized)
- [ ] Each notable achievement = 1 unlock scene
- [ ] Can override: weapon, cape, head, or add effect
- [ ] Include provenance badge variants

### Transformation
- [ ] Swirl particles
- [ ] Materialize flash (reusable)
- [ ] Per-tier finale variants
- [ ] Complete flash

---

## File Delivery Format

When delivering assets:

```
/delivery_batch_001/
├── README.txt                    # What's in this batch
├── armor/
│   ├── gold_chest_idle.png
│   ├── gold_chest_walk.png
│   └── ...
├── effects/
│   ├── gold_subtle_glow.tscn
│   └── gold_subtle_glow/         # Dependencies
│       ├── particles.tres
│       └── glow_texture.png
└── unlocks/
    └── steam_374320_THE_DARK_SOUL/
        ├── scene.tscn
        ├── cape_sprite.png
        └── ember_footsteps.tscn
```

---

## Questions?

Check these docs:
- `API_CONTRACT.md` - Endpoint details and response formats
- `GODOT_HANDOFF.md` - Overall vision and tier system
- `ACHIEVEMENT_VERIFICATION.md` - How achievements are validated

The backend serves the data. Your assets bring it to life.
