# FORGE ICON GENERATION PROMPTS (171 Items)
# Generated for 256x256 with downscale to 64x64
# Copy/paste prompts into ChatGPT with DALL-E
# Updated: 2025-12-25 - Added Wave 1-3 (Feet/Legs, Arms/Hands/Shields, Rings/Amulets)
================================================================================

## GLOBAL STYLE REQUIREMENTS (Apply to ALL items)

**Icon Design Principles:**
- Icon-focused design with bold simplified shapes
- Minimal fine texture, strong silhouette clarity
- Readable at small sizes (will be viewed at 64x64 and 16x16)
- Avoid micro-textures and excessive detail
- Dark transparent background
- Centered with padding

--------------------------------------------------------------------------------

## ORIENTATION LOCK-IN MATRIX

| Category    | Orientation      | Rule                | Visual Intent           |
|-------------|------------------|---------------------|-------------------------|
| WEAPONS     | Side profile     | Right-facing        | Action, motion          |
| ARMOR       | Front-facing     | Symmetrical         | Stability, protection   |
| SHIELDS     | Front-facing     | Symmetrical         | Defense, identity       |
| CAPES       | Front-facing     | Symmetrical         | Status, flair           |
| RINGS       | Top-down         | Symmetrical         | Identity, power         |
| AMULETS     | Front-facing     | Symmetrical         | Identity, power         |
| ACCESSORIES | Natural angle    | Readability-first   | Utility, lore           |

**Why this works:** Players subconsciously parse item types before reading labels:
- Directional = usable (weapons)
- Symmetrical = worn (armor/jewelry)
- Floating = collectible (accessories)

================================================================================
## WEAPON ORIENTATION STANDARD (MANDATORY)
================================================================================

**Global Rule:** All weapons use side-profile view, oriented LEFT to RIGHT, functional end pointing RIGHT.

**Angle Standard:** 30-40 degree upward tilt. Tip/barrel points to upper-right quadrant.
- Never vertical
- Never flat-horizontal
- Creates natural left-to-right "action flow"

**Why "pointing right" is correct:**
1. **Western UI reading flow** - Left→right implies progress, forward motion, attack
2. **Grid harmony** - No visual clashes between adjacent icons, cleaner silhouettes
3. **Muscle memory** - Players learn "right-facing silhouette = weapon"

### By Weapon Type:

**⚔️ Bladed Weapons (swords, daggers, katanas)**
- Side profile
- Tip → upper-right
- Hilt anchored lower-left
- Blade occupies 65-75% of icon length

**🔫 Firearms (guns, rifles, shotguns)**
- Side profile
- Barrel → right
- Stock toward lower-left
- Muzzle glow (if any) never touches edge

**🪓 Axes / Hammers / Maces**
- Handle lower-left → head upper-right
- Head slightly oversized to survive downscale

**🏹 Bows**
- Side profile, 30-40 degree tilt (tips point upper-right/lower-left)
- Curve opens toward the right
- String visible but simplified to single line
- Arrow optional (only if iconic to the weapon)
- Bow centered in frame, not touching edges

**🔱 Polearms (spears, halberds, tridents)**
- Side profile
- Tip pointing to upper-right
- Shaft to lower-left

**🪄 Staves**
- Side profile
- Head/focus at upper-right
- Base at lower-left

### FORBIDDEN (Weapons):
- ❌ Facing left
- ❌ Vertical "floating" weapons
- ❌ 3/4 perspective rotations
- ❌ Camera-facing weapons
- ❌ Symmetrical "straight up" compositions

================================================================================
## ARMOR ORIENTATION STANDARD (MANDATORY)
================================================================================

**Global Rule:** All armor is FRONT-FACING, CENTERED, and SYMMETRICAL.

No left/right bias. No rotation. No perspective tricks.

### By Armor Type:

**🪖 Helmets**
- Front-facing
- Show face/visor area clearly
- Centered in frame

**🛡️ Chestplates**
- Front-facing
- Show full torso armor
- Symmetrical presentation

**👖 Leg Armor / Pants**
- Front-facing
- Show as pants/greaves
- Can be folded presentation

**👢 Boots**
- Front-facing
- Single boot or matching pair
- Centered, symmetrical

**🧤 Gauntlets / Gloves**
- Front-facing
- Single gauntlet or matching pair
- Centered, symmetrical

### FORBIDDEN (Armor):
- ❌ Side profiles
- ❌ 3/4 perspective
- ❌ Tilted or rotated armor
- ❌ Asymmetrical compositions

================================================================================
## SHIELD & CAPE ORIENTATION STANDARD (MANDATORY)
================================================================================

**🛡️ Shields**
- Front-facing, centered, symmetrical
- Show the face of the shield clearly
- Emblem/design readable

**🧣 Capes / Cloaks**
- Front-facing or slight drape view
- Centered, symmetrical
- Show the design/emblem clearly

================================================================================
## JEWELRY ORIENTATION STANDARD (MANDATORY)
================================================================================

Jewelry is worn on the body - treated like armor, not accessories.

### 💍 Rings
- Top-down or straight-on circle view
- Ring opening clearly visible
- Gem/emblem centered
- No tilt
- No perspective depth
- Slight highlight at top only

**Why:** Rings are symbolic, not directional. Tilted rings look like loose loot, not equipped power.

### 🧿 Amulets / Talismans
- Front-facing medallion view
- Chain implied, not dominant
- Medallion centered
- Vertical symmetry
- Emblem readable at 32-64px

**Think:** "Relic on display," not "swinging necklace."

### FORBIDDEN (Jewelry):
- ❌ Side-profile rings
- ❌ Diagonal amulets
- ❌ Dangling chains taking focus
- ❌ Perspective foreshortening

================================================================================
## ACCESSORY ORIENTATION STANDARD (FLEXIBLE)
================================================================================

Accessories are NOT worn - they follow object rules, not armor rules.

**Rule:** Natural presentation angle that best communicates the object.

This is the **only category** where orientation is flexible.

### Examples:
| Item Type       | Orientation        |
|-----------------|-------------------|
| Key             | Diagonal          |
| Fragment/Shard  | Floating/angled   |
| Coin/Token      | Front-facing      |
| Badge/Emblem    | Flat, frontal     |
| Relic           | Slight rotation   |
| Consumable      | Mild tilt         |

**Golden Rule:** Choose the angle that makes it instantly recognizable.

### Constraints (Still Locked):
Even though orientation is flexible:
- ✅ Must remain centered
- ✅ Must avoid extreme rotation
- ✅ Must maintain silhouette clarity
- ✅ Must not conflict with equipped-item readability

================================================================================
## VISUAL DESCRIPTION REQUIREMENTS (CRITICAL FOR CONSISTENCY)
================================================================================

Every prompt MUST include a "Visual elements:" section with CONCRETE details:

### Required Elements:
1. **Materials** - What is it made of? (steel, leather, bone, crystal, etc.)
2. **Colors** - Primary and accent colors, not just glow
3. **Distinctive Features** - What makes THIS item unique?
4. **Surface Details** - Engravings, runes, patterns, wear marks
5. **Energy/Effects** - Glows, particles, auras (match the glow color)

### Good vs Bad Examples:

**❌ BAD (too vague):**
```
Reference: A sword from Dark Souls. Wielded by warriors.
```

**✅ GOOD (concrete details):**
```
Visual elements: Curved greatsword with jagged, flame-warped blade.
Dark iron with orange ember cracks along the edge. Wrapped leather grip,
wolf-head pommel. Faint orange flame particles rising from blade.
```

### By Category Quick Guide:

| Type | Must Include |
|------|--------------|
| Swords | Blade shape, crossguard style, grip material, any engravings |
| Axes | Head shape, blade edge style, handle material, weight feel |
| Bows | Limb material, grip wrapping, string type, any decorations |
| Helmets | Visor style, material, horns/crests, face coverage |
| Armor | Plate/leather/cloth, fasteners, emblems, wear level |
| Rings | Band material, gem type/shape, engravings, magical effect |
| Amulets | Pendant shape, chain style, central emblem, magical glow |

================================================================================

## 1. **Coiled Sword** (coiled_sword)
Type: weapon | Theme: dark_souls | Rarity: legendary
Glow: #FF6A00
Save to: assets/icons/forged/weapons/coiled_sword.png

Create a 256x256 game icon for "Coiled Sword" - a legendary weapon from Dark Souls.

Visual elements: Straight longsword with blade that spirals/coils near the tip like a corkscrew. Blackened steel with glowing orange ember cracks running through the metal. Simple crossguard, leather-wrapped grip. Orange flame particles emanating from the coiled section. The blade appears to be made of solidified fire.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FF6A00

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 2. **Farron Greatsword** (farron_greatsword)
Type: weapon | Theme: dark_souls | Rarity: epic
Glow: #4A6B8A
Save to: assets/icons/forged/weapons/farron_greatsword.png

Create a 256x256 game icon for "Farron Greatsword" - an epic weapon from Dark Souls.

Visual elements: Massive curved greatsword with unique hooked tip. Weathered grey steel with blue-grey abyss energy wisps along the edge. Elongated grip for two-handed use, wrapped in dark leather. Wolf motif engraved near the crossguard. Blade has a distinctive backwards curve like a giant dagger.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #4A6B8A

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 3. **Dragonslayer Swordspear** (dragonslayer_swordspear)
Type: weapon | Theme: dark_souls | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/weapons/dragonslayer_swordspear.png

Create a 256x256 game icon for "Dragonslayer Swordspear" - a legendary weapon from Dark Souls.

Visual elements: Hybrid weapon - long spear with a sword-like blade as the head. Polished golden metal crackling with yellow lightning energy. Ornate dragon-scale pattern etched into the blade. Long wooden shaft wrapped in golden leather. Lightning bolts arcing from the blade tip. Royal, divine aesthetic.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

POLEARM ORIENTATION: Side profile, tip pointing to upper-right, shaft to lower-left. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 4. **Grafted Blade Greatsword** (grafted_blade)
Type: weapon | Theme: elden_ring | Rarity: rare
Glow: #B8860B
Save to: assets/icons/forged/weapons/grafted_blade.png

Create a 256x256 game icon for "Grafted Blade Greatsword" - a rare weapon from Elden Ring.

Visual elements: Massive colossal sword made of dozens of smaller swords fused together. Chaotic blade edge with multiple sword tips pointing outward. Rusted iron and dark gold metal, worn and ancient. Hilt wrapped in old leather with bone fragments. Dark bronze glow where the grafted blades meet. Grotesque, organic-looking fusion points.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #B8860B

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 5. **Hand of Malenia** (hand_of_malenia)
Type: weapon | Theme: elden_ring | Rarity: legendary
Glow: #FF6B6B
Save to: assets/icons/forged/weapons/hand_of_malenia.png

Create a 256x256 game icon for "Hand of Malenia" - a legendary weapon from Elden Ring.

Visual elements: Elegant curved katana with impossibly long, slender blade. Pale silver steel with scarlet rot veins spreading across the metal like infection. Delicate golden crossguard shaped like butterfly wings. White wrapping on grip with red accents. Faint pink-red scarlet rot particles floating off the blade. Beautiful yet deadly, fragile appearance.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FF6B6B

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 6. **Starscourge Greatswords** (radahns_greatswords)
Type: weapon | Theme: elden_ring | Rarity: legendary
Glow: #8B4513
Save to: assets/icons/forged/weapons/radahns_greatswords.png

Create a 256x256 game icon for "Starscourge Greatswords" - a legendary weapon from Elden Ring.

Visual elements: Two massive curved greatswords crossed or overlapping. Weathered bronze-brown metal with cosmic purple energy crackling between them. Thick, brutal blades meant for a giant. Lion motifs on the pommels. Gravity magic purple-brown particles swirling around the weapons. Desert-worn, battle-scarred appearance.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #8B4513

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt. Show both blades crossed.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 7. **Moonveil** (moonveil)
Type: weapon | Theme: elden_ring | Rarity: epic
Glow: #A0D0FF
Save to: assets/icons/forged/weapons/moonveil.png

Create a 256x256 game icon for "Moonveil" - an epic weapon from Elden Ring.

Visual elements: Sleek curved katana with ethereal blue moonlight glow along the blade edge. Polished silver steel with Carian moon runes etched near the hilt. Traditional wrapped grip in dark blue. Faint blue magical particles trailing from the blade. Elegant, mystical eastern sword design.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #A0D0FF

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 8. **Elden Lord's Greathelm** (elden_lord_helm)
Type: armor_head | Theme: elden_ring | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/armor/elden_lord_helm.png

Create a 256x256 game icon for "Elden Lord's Greathelm" - a legendary helmet/headgear from Elden Ring.

Visual elements: Ornate golden greathelm with full face coverage. Regal crown-like ridge along the top. Narrow T-shaped visor slit. Intricate Erdtree branch engravings on the cheeks. Polished gold metal with faint divine glow. Royal, majestic presence befitting a lord.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 9. **Carian Royal Crown** (carian_crown)
Type: armor_head | Theme: elden_ring | Rarity: epic
Glow: #A0D0FF
Save to: assets/icons/forged/armor/carian_crown.png

Create a 256x256 game icon for "Carian Royal Crown" - an epic helmet/headgear from Elden Ring.

Visual elements: Elegant silver crown with tall pointed spires. Blue glintstone gems embedded in the band. Crescent moon motif at the center. Delicate silver filigree work. Pale blue magical aura emanating from the stones. Scholarly, mystical royal aesthetic.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #A0D0FF

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 10. **Fingerprint Stone Shield** (fingerprint_stone_shield)
Type: shield | Theme: elden_ring | Rarity: epic
Glow: #808080
Save to: assets/icons/forged/shields/fingerprint_stone_shield.png

Create a 256x256 game icon for "Fingerprint Stone Shield" - an epic shield from Elden Ring.

Visual elements: Massive rectangular greatshield carved from grey stone. Distinctive spiral fingerprint pattern carved deeply into the entire surface. Rough, ancient texture. Metal reinforcement bands at the edges. Subtle grey glow from the carved grooves. Impossibly heavy, fortress-like appearance.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #808080

SHIELD ORIENTATION: Front-facing, centered, symmetrical. Show the face of the shield clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 11. **Pure Nail** (pure_nail)
Type: weapon | Theme: hollow_knight | Rarity: rare
Glow: #E0E0E0
Save to: assets/icons/forged/weapons/pure_nail.png

Create a 256x256 game icon for "Pure Nail" - a rare weapon from Hollow Knight.

Visual elements: Sleek needle-like sword with pale white blade that gleams like polished bone. Simple minimalist design - no crossguard, just a thin pale handle flowing into the blade. Surface is perfectly smooth and pristine. Faint white luminescence along the edges. The blade tapers to an impossibly sharp point. Clean, refined, almost surgical in appearance.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #E0E0E0

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 12. **Shade Cloak** (shade_cloak)
Type: cape | Theme: hollow_knight | Rarity: epic
Glow: #1A0033
Save to: assets/icons/forged/capes/shade_cloak.png

Create a 256x256 game icon for "Shade Cloak" - an epic cape/cloak from Hollow Knight.

Visual elements: Ethereal cloak made of living darkness. Deep purple-black void fabric that seems to dissolve at the edges into wisps of shadow. No visible clasps - the cloak appears to be made of pure shadow given form. Dark purple particles drifting off the hem. Interior shows deeper void than the exterior. Insubstantial, spectral appearance.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #1A0033

CAPE ORIENTATION: Front-facing or slight drape view, centered, symmetrical. Show the design/emblem clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 13. **Stygian Blade** (stygian_blade)
Type: weapon | Theme: hades | Rarity: rare
Glow: #8B0000
Save to: assets/icons/forged/weapons/stygian_blade.png

Create a 256x256 game icon for "Stygian Blade" - a rare weapon from Hades.

Visual elements: Curved Greek-style sword with dark iron blade. Deep crimson blood-red glow along the cutting edge. Ornate bronze crossguard with skull motif. Black leather wrapped grip. Hellish red embers floating from the blade. Ancient underworld aesthetic - part xiphos sword, part infernal weapon.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #8B0000

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 14. **Adamant Rail** (adamant_rail)
Type: weapon | Theme: hades | Rarity: rare
Glow: #FF4500
Save to: assets/icons/forged/weapons/adamant_rail.png

Create a 256x256 game icon for "Adamant Rail" - a rare weapon from Hades.

Visual elements: Ornate bronze-and-black handheld gun with Greek decorative flourishes. Elongated barrel with fiery orange energy core visible inside. Skull motifs and Greek key patterns engraved on the receiver. Orange-red hellfire glow emanating from the barrel. Mechanical yet ancient aesthetic - steampunk meets mythology.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FF4500

FIREARM ORIENTATION: Side profile, barrel pointing RIGHT, stock toward lower-left. Muzzle at upper-right. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 15. **BR55 Battle Rifle** (halo_battle_rifle)
Type: weapon | Theme: halo | Rarity: epic
Glow: #00CED1
Save to: assets/icons/forged/weapons/halo_battle_rifle.png

Create a 256x256 game icon for "BR55 Battle Rifle" - an epic weapon from Halo.

Visual elements: Futuristic military rifle with angular olive-green and black body. Prominent top-mounted scope. Distinctive bullpup configuration with magazine behind grip. Cyan holographic sight glow. Clean military sci-fi lines with visible panel segments. UNSC utilitarian design - functional, no-nonsense, battle-worn.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #00CED1

FIREARM ORIENTATION: Side profile, barrel pointing RIGHT, stock toward lower-left. Muzzle at upper-right. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 16. **Terra Blade** (terra_blade)
Type: weapon | Theme: terraria | Rarity: legendary
Glow: #00FF80
Save to: assets/icons/forged/weapons/terra_blade.png

Create a 256x256 game icon for "Terra Blade" - a legendary weapon from Terraria.

Visual elements: Broad-bladed sword glowing with vibrant green earth energy. Blade transitions from emerald green at the edge to deeper forest green at the center. Crystalline structure with faceted surfaces catching light. Simple golden crossguard. Green energy particles radiating outward. The blade appears to be made of solidified nature magic - leaves and vines subtly visible within.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00FF80

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 17. **Mortal Blade** (mortal_blade)
Type: weapon | Theme: sekiro | Rarity: legendary
Glow: #CC0000
Save to: assets/icons/forged/weapons/mortal_blade.png

Create a 256x256 game icon for "Mortal Blade" - a legendary weapon from Sekiro.

Visual elements: Elegant odachi with deep crimson-red blade that seems to bleed color. Traditional Japanese sword shape with subtle curve. Black lacquered sheath visible at the grip. Red mist or blood-colored aura emanating from the blade. Ornate golden tsuba (hand guard) with floral pattern. The blade surface has a liquid, almost organic sheen.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #CC0000

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 18. **Gyoubu's Broken Horn** (gyoubu_spear)
Type: weapon | Theme: sekiro | Rarity: epic
Glow: #8B0000
Save to: assets/icons/forged/weapons/gyoubu_spear.png

Create a 256x256 game icon for "Gyoubu's Broken Horn" - an epic weapon from Sekiro.

Visual elements: Massive Japanese war spear (yari) with a distinctive broken/jagged spearhead. Dark iron blade with battle damage and chips. Long wooden shaft wrapped in faded red leather. Blood-red tassels hanging from below the blade. The spearhead has a horn-like curve. Worn, battle-tested appearance befitting a samurai general.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #8B0000

POLEARM ORIENTATION: Side profile, tip pointing to upper-right, shaft to lower-left. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 19. **Witcher's Silver Sword** (witcher_silver_sword)
Type: weapon | Theme: witcher | Rarity: rare
Glow: #C0C0C0
Save to: assets/icons/forged/weapons/witcher_silver_sword.png

Create a 256x256 game icon for "Witcher's Silver Sword" - a rare weapon from The Witcher.

Visual elements: Elegant longsword with polished silver blade that gleams with moonlight. Distinctive witcher crossguard with wolf-head pommel. Blade has runic etchings along the fuller. Black leather wrapped grip with silver wire accents. Faint silver glow indicating anti-monster enchantment. Professional, refined craftsmanship.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #C0C0C0

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 20. **Aloy's Sharpshot Bow** (aloy_sharpshot_bow)
Type: weapon | Theme: horizon | Rarity: rare
Glow: #FF6B35
Save to: assets/icons/forged/weapons/aloy_sharpshot_bow.png

Create a 256x256 game icon for "Aloy's Sharpshot Bow" - a rare weapon from Horizon Zero Dawn.

Visual elements: Tribal hunting bow with machine parts integrated into the design. Wood and metal hybrid construction. Orange-red cables and wires woven through the limbs. Salvaged tech components visible at the grip. Orange energy glow from the mechanical elements. Post-apocalyptic tribal meets high-tech aesthetic.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FF6B35

BOW ORIENTATION: Side profile, curve opens toward RIGHT, string visible but simplified. 30-40 degree tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 21. **Lara's Makeshift Bow** (tomb_raider_bow)
Type: weapon | Theme: tomb_raider | Rarity: rare
Glow: #8B4513
Save to: assets/icons/forged/weapons/tomb_raider_bow.png

Create a 256x256 game icon for "Lara's Makeshift Bow" - a rare weapon from Tomb Raider.

Visual elements: Rugged survival bow made from scavenged materials. Wooden core wrapped with cloth bandages and duct tape. Improvised string from cabling. Scratched and worn surfaces showing heavy use. Brown-earthy tones with survival gear aesthetic. Functional, desperate craftsmanship - built to survive, not to be pretty.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #8B4513

BOW ORIENTATION: Side profile, curve opens toward RIGHT, string visible but simplified. 30-40 degree tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 22. **Farmer's Straw Hat** (straw_hat)
Type: armor_head | Theme: stardew | Rarity: rare
Glow: #D4A574
Save to: assets/icons/forged/armor/straw_hat.png

Create a 256x256 game icon for "Farmer's Straw Hat" - a rare helmet/headgear from Stardew Valley.

Visual elements: Wide-brimmed straw hat with golden-tan woven texture. Simple red or blue ribbon band around the crown. Slightly worn and sun-faded appearance. A few straw pieces sticking out naturally. Cozy, pastoral charm. Warm honey-colored glow suggesting sunny farmland days.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #D4A574

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 23. **Coiled Sword Fragment** (coiled_sword_fragment)
Type: accessory | Theme: dark_souls | Rarity: epic
Glow: #FF6A00
Save to: assets/icons/forged/accessories/coiled_sword_fragment.png

Create a 256x256 game icon for "Coiled Sword Fragment" - an epic accessory from Dark Souls.

Visual elements: Broken shard of the Coiled Sword - a curved metallic fragment with spiral texture. Blackened steel with glowing orange ember cracks. Jagged broken edge where it snapped from the full blade. Small orange flames flickering from the surface. Bonfire warmth emanating from within. Pocket-sized relic of undying flame.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FF6A00

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 24. **Margit's Shackle** (margits_shackle)
Type: accessory | Theme: elden_ring | Rarity: rare
Glow: #FFD700
Save to: assets/icons/forged/accessories/margits_shackle.png

Create a 256x256 game icon for "Margit's Shackle" - a rare accessory from Elden Ring.

Visual elements: Heavy iron shackle with broken chain links attached. Dark rusted metal with golden Erdtree runes inscribed. Circular cuff design meant to bind a powerful creature. Faint golden divine glow from the binding runes. Worn, ancient appearance. Ominous power contained within simple iron restraint.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FFD700

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 25. **Nitro Supporter Badge** (discord_nitro_badge)
Type: accessory | Theme: discord | Rarity: rare
Glow: #5865F2
Save to: assets/icons/forged/accessories/discord_nitro_badge.png

Create a 256x256 game icon for "Nitro Supporter Badge" - a rare accessory from Discord.

Visual elements: Sleek modern badge with Discord's signature blurple color. Rocket or lightning bolt motif in the center. Metallic purple-blue gradient finish. Clean geometric design with rounded edges. Subtle purple glow emanating outward. Premium, digital aesthetic - social platform prestige made physical.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #5865F2

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 26. **Stargazer Badge** (github_star_badge)
Type: accessory | Theme: github | Rarity: rare
Glow: #238636
Save to: assets/icons/forged/accessories/github_star_badge.png

Create a 256x256 game icon for "Stargazer Badge" - a rare accessory from GitHub.

Visual elements: Octagonal badge featuring GitHub's octocat silhouette. Multiple star shapes surrounding the center. Dark background with bright green accent color. Clean developer aesthetic with code-like precision. Green glow suggesting open source contribution. Tech-forward, minimalist design.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #238636

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 27. **Scarab Lord's Ring** (scarab_lord_badge)
Type: ring | Theme: wow | Rarity: legendary
Glow: #FFB932
Save to: assets/icons/forged/accessories/scarab_lord_badge.png

Create a 256x256 game icon for "Scarab Lord's Ring" - a legendary ring from World of Warcraft.

Visual elements: Ancient golden ring band with elaborate scarab beetle centerpiece. The beetle is crafted from dark obsidian with amber gemstone eyes. Egyptian-style hieroglyphic engravings around the band. Sand-gold metallic finish with desert patina. Golden glow emanating from the scarab's eyes. Regal, ancient power from the sands of Silithus.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFB932

RING ORIENTATION: Top-down or straight-on ring presentation, centered and symmetrical. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 28. **Herald of the Titans Crown** (herald_of_the_titans)
Type: armor_head | Theme: wow | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/armor/herald_of_the_titans.png

Create a 256x256 game icon for "Herald of the Titans Crown" - a legendary helmet/headgear from World of Warcraft.

Visual elements: Celestial crown made of swirling cosmic energy and starlight. Ethereal purple-blue construction with floating star particles. Multiple tall spires reaching upward like frozen starbursts. Constellation patterns visible in the metal. Brilliant golden core light emanating from within. Otherworldly, astronomical grandeur befitting a titan's herald.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 29. **Tabard of the Immortal** (immortal_tabard)
Type: cape | Theme: wow | Rarity: legendary
Glow: #FFFFFF
Save to: assets/icons/forged/capes/immortal_tabard.png

Create a 256x256 game icon for "Tabard of the Immortal" - a legendary cape/cloak from World of Warcraft.

Visual elements: Pure white tabard with silver trim and pristine fabric. Central emblem shows an inverted skull with wings - the mark of Naxxramas. Ghostly white glow surrounding the entire piece. Fabric appears ethereal, almost translucent. Perfect, unmarred condition symbolizing deathless achievement. Divine, immaculate radiance.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFFFFF

CAPE ORIENTATION: Front-facing or slight drape view, centered, symmetrical. Show the design/emblem clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 30. **Hand of A'dal Tabard** (hand_of_adal_tabard)
Type: cape | Theme: wow | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/capes/hand_of_adal_tabard.png

Create a 256x256 game icon for "Hand of A'dal Tabard" - a legendary cape/cloak from World of Warcraft.

Visual elements: Rich purple tabard with golden Naaru symbol at the center - a vertical diamond of crystalline light. Ornate gold trim with draenei geometric patterns. Deep violet fabric with subtle luminescent threads. Golden divine light radiating from the central symbol. Outland aesthetic - alien yet holy, otherworldly grace.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

CAPE ORIENTATION: Front-facing or slight drape view, centered, symmetrical. Show the design/emblem clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 31. **Cutting Edge Amulet** (mythic_insignia)
Type: amulet | Theme: wow | Rarity: epic
Glow: #A335EE
Save to: assets/icons/forged/accessories/mythic_insignia.png

Create a 256x256 game icon for "Cutting Edge Amulet" - an epic amulet/necklace from World of Warcraft.

Visual elements: Heavy medallion with jagged, blade-like edges around the perimeter. Central purple gem pulsing with mythic energy. Dark metal frame with skull motifs. Thin chain visible above. Epic purple glow emanating from the center. Aggressive, elite design - proof of hardcore raiding prowess.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #A335EE

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 32. **Keystone Master's Trinket** (keystone_trinket)
Type: accessory | Theme: wow | Rarity: epic
Glow: #00CED1
Save to: assets/icons/forged/accessories/keystone_trinket.png

Create a 256x256 game icon for "Keystone Master's Trinket" - an epic accessory from World of Warcraft.

Visual elements: Ornate key-shaped trinket with mystical timer runes around the shaft. Cyan-blue crystal embedded in the key's bow (handle). Bronze metallic finish with arcane engravings. Roman numeral XX (20) subtly visible. Teal energy wisps suggesting time magic. Precision-crafted dungeon master's token.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #00CED1

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 33. **Gladiator's Tabard** (gladiator_tabard)
Type: cape | Theme: wow | Rarity: legendary
Glow: #CC0000
Save to: assets/icons/forged/capes/gladiator_tabard.png

Create a 256x256 game icon for "Gladiator's Tabard" - a legendary cape/cloak from World of Warcraft.

Visual elements: Blood-red tabard with golden gladiator helm emblem at center. Battle-worn fabric with subtle bloodstains. Heavy gold chain clasps at the shoulders. Crimson glow of arena glory. Torn edges suggesting countless battles. Warrior's pride made manifest - victory through combat.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #CC0000

CAPE ORIENTATION: Front-facing or slight drape view, centered, symmetrical. Show the design/emblem clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 34. **Insane Straitjacket** (insane_straitjacket)
Type: armor_chest | Theme: wow | Rarity: legendary
Glow: #FFB932
Save to: assets/icons/forged/armor/insane_straitjacket.png

Create a 256x256 game icon for "Insane Straitjacket" - a legendary chest armor from World of Warcraft.

Visual elements: Weathered white straitjacket with buckled straps and restraints. Padded canvas material with visible stitching. Multiple leather straps crossing the chest. Frayed edges and asylum-worn appearance. Golden glow suggesting madness transformed to power. Unsettling yet prestigious - proof of obsessive dedication.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFB932

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 35. **Saw Cleaver** (saw_cleaver)
Type: weapon | Theme: bloodborne | Rarity: legendary
Glow: #8B0000
Save to: assets/icons/forged/weapons/saw_cleaver.png

Create a 256x256 game icon for "Saw Cleaver" - a legendary weapon from Bloodborne.

Visual elements: Brutal folding cleaver with serrated saw-blade edge. Dark grey steel covered in old bloodstains. Mechanical folding mechanism visible at the hinge. Worn wooden handle wrapped in stained bandages. Deep crimson blood glow along the teeth. Industrial, medical horror aesthetic - surgery meets slaughter.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #8B0000

AXE/HAMMER ORIENTATION: Handle from lower-left to head at upper-right. Head slightly oversized. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 36. **False King's Helm** (false_king_helm)
Type: armor_head | Theme: demons_souls | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/armor/false_king_helm.png

Create a 256x256 game icon for "False King's Helm" - a legendary helmet/headgear from Demon's Souls.

Visual elements: Ornate golden crown-helm with two massive curved horns sweeping upward. Full-face greathelm design with narrow visor slit. Intricate demonic engravings on the cheeks and brow. Polished gold metal with an otherworldly sheen. Golden divine glow from within. Regal yet corrupted - false divinity made manifest.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 37. **Blades of Chaos Fragment** (blades_of_chaos)
Type: accessory | Theme: god_of_war | Rarity: epic
Glow: #C41E3A
Save to: assets/icons/forged/accessories/blades_of_chaos.png

Create a 256x256 game icon for "Blades of Chaos Fragment" - an epic accessory from God of War.

Visual elements: Broken shard of a curved Greek blade with jagged edges. Blackened metal with glowing orange-red chains still attached. Omega symbol faintly visible on the surface. Hellfire red embers crackling along the fragment. Ash and cinder particles floating upward. Cursed, burning remnant of divine weaponry.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #C41E3A

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 38. **Ghost Mask** (ghost_mask)
Type: armor_head | Theme: ghost_of_tsushima | Rarity: epic
Glow: #1A1A2E
Save to: assets/icons/forged/armor/ghost_mask.png

Create a 256x256 game icon for "Ghost Mask" - an epic helmet/headgear from Ghost of Tsushima.

Visual elements: White ceramic Japanese demon mask (oni/hannya style). Pale ghostly white with cracked surface showing age. Red accents around the eyes and mouth. Furrowed angry brow and grimacing expression. Dark shadowy aura emanating from behind. Traditional yet terrifying - the face of vengeance.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #1A1A2E

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 39. **Selene's Fragment** (selene_fragment)
Type: accessory | Theme: generic | Rarity: legendary
Glow: #00FFFF
Save to: assets/icons/forged/accessories/selene_fragment.png

Create a 256x256 game icon for "Selene's Fragment" - a legendary accessory from Gaming.

Visual elements: Alien crystalline shard with bioluminescent cyan glow. Organic-looking surface with circuit-like patterns. Translucent material showing internal energy flowing. Sharp geometric facets meeting organic curves. Cyan-teal particles spiraling around it. Xenotech artifact - ancient and impossibly advanced.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00FFFF

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 40. **Spider Emblem** (spider_emblem)
Type: accessory | Theme: generic | Rarity: epic
Glow: #FF0000
Save to: assets/icons/forged/accessories/spider_emblem.png

Create a 256x256 game icon for "Spider Emblem" - an epic accessory from Gaming.

Visual elements: Stylized spider emblem in red and black. Eight angular legs radiating from central body. Bold graphic design - clean lines, sharp angles. Metallic red finish with black accents. Red glow pulsing from the center. Heroic, iconic silhouette instantly recognizable.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FF0000

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 41. **MJOLNIR Helmet** (master_chief_helmet)
Type: armor_head | Theme: halo | Rarity: legendary
Glow: #00CED1
Save to: assets/icons/forged/armor/master_chief_helmet.png

Create a 256x256 game icon for "MJOLNIR Helmet" - a legendary helmet/headgear from Halo.

Visual elements: Iconic olive-green MJOLNIR powered armor helmet. Distinctive golden-orange reflective visor. Angular futuristic design with armored cheek plates. Visible tech ports and vents on the sides. Cyan holographic HUD glow reflecting in the visor. Military sci-fi perfection - the face of a Spartan.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00CED1

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 42. **Pilot's Helmet** (pilot_helmet)
Type: armor_head | Theme: titanfall | Rarity: legendary
Glow: #FF6600
Save to: assets/icons/forged/armor/pilot_helmet.png

Create a 256x256 game icon for "Pilot's Helmet" - a legendary helmet/headgear from Titanfall.

Visual elements: Sleek tactical helmet with angular pilot design. Dark grey-black with orange accent stripes. Distinctive full-face visor with HUD overlay visible. Jump kit connection ports on the back. Communication antenna on one side. Orange tactical glow from visor elements. Elite military pilot aesthetic - speed and precision.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FF6600

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 43. **COG Medal of Honor** (cog_medal)
Type: accessory | Theme: gears | Rarity: legendary
Glow: #990000
Save to: assets/icons/forged/accessories/cog_medal.png

Create a 256x256 game icon for "COG Medal of Honor" - a legendary accessory from Gears of War.

Visual elements: Heavy military medal with the crimson COG (Coalition of Ordered Governments) gear emblem. Dark metal frame with blood-red enamel center. Thick ribbon attachment in military style. Battle-worn scratches on the surface. Deep crimson glow from the gear symbol. Brutal, industrial military decoration.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #990000

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 44. **Pirate Legend Hat** (pirate_legend_hat)
Type: armor_head | Theme: sea_of_thieves | Rarity: epic
Glow: #1E90FF
Save to: assets/icons/forged/armor/pirate_legend_hat.png

Create a 256x256 game icon for "Pirate Legend Hat" - an epic helmet/headgear from Sea of Thieves.

Visual elements: Extravagant tricorn pirate hat with purple-blue legendary colors. Golden trim and ornate skull-and-crossbones emblem. Large feather plume in mystical blue. Rich velvet material with weathered sea-worn edges. Ocean blue glow emanating from the fabric. Legendary pirate finery - captain of the seas.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #1E90FF

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 45. **Early Supporter Badge** (early_supporter_badge)
Type: accessory | Theme: discord | Rarity: legendary
Glow: #5865F2
Save to: assets/icons/forged/accessories/early_supporter_badge.png

Create a 256x256 game icon for "Early Supporter Badge" - a legendary accessory from Discord.

Visual elements: Vintage-styled badge with Discord's classic Wumpus mascot. Purple-blue gradient with "OG" styling. Small lightning bolt accents. Worn patina suggesting age and history. Premium metallic purple finish. Legendary purple glow. Exclusive, unobtainable collector's item.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #5865F2

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 46. **Partner Badge** (partner_badge)
Type: accessory | Theme: discord | Rarity: epic
Glow: #5865F2
Save to: assets/icons/forged/accessories/partner_badge.png

Create a 256x256 game icon for "Partner Badge" - an epic accessory from Discord.

Visual elements: Hexagonal badge with Discord Partner verification checkmark. Purple-blue blurple gradient finish. Sleek modern design with beveled edges. Partner logo prominent in center. Metallic sheen with premium quality feel. Purple glow radiating outward. Verified community leader's emblem.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #5865F2

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 47. **Bug Hunter Badge** (bug_hunter_badge)
Type: accessory | Theme: discord | Rarity: epic
Glow: #43B581
Save to: assets/icons/forged/accessories/bug_hunter_badge.png

Create a 256x256 game icon for "Bug Hunter Badge" - an epic accessory from Discord.

Visual elements: Golden badge featuring a stylized bug/beetle silhouette. Magnifying glass motif incorporated into design. Bright green accent color for "hunt successful" feel. Metallic gold rim with polished finish. Green glow from the bug icon. Detective-meets-developer aesthetic.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #43B581

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 48. **HypeSquad Badge** (hypesquad_badge)
Type: accessory | Theme: discord | Rarity: rare
Glow: #FAA61A
Save to: assets/icons/forged/accessories/hypesquad_badge.png

Create a 256x256 game icon for "HypeSquad Badge" - a rare accessory from Discord.

Visual elements: Dynamic badge with HypeSquad shield emblem. Bright orange-gold energetic color scheme. Three house icons subtly visible (Bravery, Brilliance, Balance). Event-ready, promotional styling. Metallic orange finish with excitement energy. Orange glow pulsing outward. Community ambassador's badge of honor.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FAA61A

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 49. **Arctic Code Vault Badge** (arctic_code_badge)
Type: accessory | Theme: github | Rarity: legendary
Glow: #00BFFF
Save to: assets/icons/forged/accessories/arctic_code_badge.png

Create a 256x256 game icon for "Arctic Code Vault Badge" - a legendary accessory from GitHub.

Visual elements: Crystalline ice-themed badge with frozen archive vault motif. Pale blue-white coloring like arctic ice. GitHub octocat silhouette preserved in ice. Snowflake patterns around the edges. Frigid cyan glow emanating from within. 1000-year preservation seal visible. Cryogenic legacy artifact.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00BFFF

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 50. **Mars 2020 Badge** (mars_badge)
Type: accessory | Theme: github | Rarity: legendary
Glow: #FF4500
Save to: assets/icons/forged/accessories/mars_badge.png

Create a 256x256 game icon for "Mars 2020 Badge" - a legendary accessory from GitHub.

Visual elements: Rusty red Mars-themed badge with Perseverance rover silhouette. Red planet surface texture visible. NASA-style mission patch aesthetic. Rocket trajectory arc in the background. Martian orange-red glow emanating outward. Stars visible around the edges. Interplanetary achievement badge.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FF4500

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 51. **Pull Shark Badge** (pull_shark_badge)
Type: accessory | Theme: github | Rarity: epic
Glow: #238636
Save to: assets/icons/forged/accessories/pull_shark_badge.png

Create a 256x256 game icon for "Pull Shark Badge" - an epic accessory from GitHub.

Visual elements: Stylized shark fin cutting through water (code). GitHub green merge color scheme. Shark silhouette with aggressive forward motion. Digital water/code stream effect. Bright green glow suggesting successful merges. Predatory developer efficiency - PRs don't stand a chance.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #238636

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 52. **Galaxy Brain Badge** (galaxy_brain_badge)
Type: accessory | Theme: github | Rarity: epic
Glow: #8B5CF6
Save to: assets/icons/forged/accessories/galaxy_brain_badge.png

Create a 256x256 game icon for "Galaxy Brain Badge" - an epic accessory from GitHub.

Visual elements: Stylized brain silhouette filled with swirling galaxy patterns. Purple-violet cosmic nebula colors inside the brain shape. Stars and constellation dots visible within. Radiant purple glow emanating outward. Knowledge-as-universe aesthetic. Helpful genius community member emblem.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #8B5CF6

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 53. **YOLO Badge** (yolo_badge)
Type: accessory | Theme: github | Rarity: rare
Glow: #FF6B6B
Save to: assets/icons/forged/accessories/yolo_badge.png

Create a 256x256 game icon for "YOLO Badge" - a rare accessory from GitHub.

Visual elements: Reckless danger-themed badge with skull-and-crossbones motif. Bright warning red coloring. "YOLO" text or lightning bolt visible. Cracked or shattered edge effects. Red warning glow like an alarm. Daredevil developer's mark of chaos.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FF6B6B

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 54. **Veteran Robloxian Necklace** (veteran_roblox_necklace)
Type: amulet | Theme: roblox | Rarity: legendary
Glow: #00A2FF
Save to: assets/icons/forged/accessories/veteran_roblox_necklace.png

Create a 256x256 game icon for "Veteran Robloxian Necklace" - a legendary amulet/necklace from Roblox.

Visual elements: Blocky pixelated medallion in Roblox's signature cyan-blue. Classic Roblox "R" logo as centerpiece. Chunky chain links in gold. Retro 2008-era aesthetic with clean geometric shapes. Bright blue glow emanating from the logo. OG prestige - before the masses arrived.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00A2FF

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 55. **Classic Robloxian Ring** (classic_roblox_ring)
Type: ring | Theme: roblox | Rarity: epic
Glow: #00A2FF
Save to: assets/icons/forged/accessories/classic_roblox_ring.png

Create a 256x256 game icon for "Classic Robloxian Ring" - an epic ring from Roblox.

Visual elements: Blocky geometric ring band with Roblox blue coloring. Small square gem in classic Roblox style. Clean pixel-art inspired design. Simple metallic blue finish. Blue glow from the centerpiece. Veteran player's proof of dedication.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #00A2FF

RING ORIENTATION: Top-down or straight-on ring presentation, centered and symmetrical. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 56. **Builder's Ring** (builder_roblox_ring)
Type: ring | Theme: roblox | Rarity: rare
Glow: #00A2FF
Save to: assets/icons/forged/accessories/builder_roblox_ring.png

Create a 256x256 game icon for "Builder's Ring" - a rare ring from Roblox.

Visual elements: Simple blocky ring with brick texture pattern. Roblox blue metal band. Small studded details around the band. Builder's tool (wrench or hammer) motif on top. Blue glow suggesting creative energy. Established player's mark of experience.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00A2FF

RING ORIENTATION: Top-down or straight-on ring presentation, centered and symmetrical. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 57. **Ashen Estus Flask** (ashen_estus)
Type: accessory | Theme: dark_souls | Rarity: rare
Glow: #FF6A00
Save to: assets/icons/forged/accessories/ashen_estus.png

Create a 256x256 game icon for "Ashen Estus Flask" - a rare accessory from Dark Souls.

Visual elements: Distinctive gourd-shaped flask with warm orange liquid visible inside. Metallic bronze cap and base. Worn leather strap attachment. Glass surface catching firelight. Warm orange glow from the healing liquid within. Ember particles floating around it. Beacon of hope in dark times.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FF6A00

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 58. **Tarnished's Ring** (tarnished_ring)
Type: ring | Theme: elden_ring | Rarity: rare
Glow: #FFD700
Save to: assets/icons/forged/accessories/tarnished_ring.png

Create a 256x256 game icon for "Tarnished's Ring" - a rare ring from Elden Ring.

Visual elements: Ornate golden ring with Erdtree branch pattern engraved. Central amber gem pulsing with grace. Tarnished and worn golden finish showing age. Subtle Elden Ring rune markings around the band. Golden divine glow from the gem. Mark of one who claimed the throne.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FFD700

RING ORIENTATION: Top-down or straight-on ring presentation, centered and symmetrical. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 59. **Void Heart** (void_heart)
Type: accessory | Theme: hollow_knight | Rarity: legendary
Glow: #1A0033
Save to: assets/icons/forged/accessories/void_heart.png

Create a 256x256 game icon for "Void Heart" - a legendary accessory from Hollow Knight.

Visual elements: Stylized heart-shaped charm made of pure void essence. Deep purple-black with inky tendrils wisping outward. Pale white crack or seam down the center. Void particles dissolving from the edges. Dark purple abyss glow emanating outward. Container of infinite darkness.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #1A0033

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 60. **Olympian Keepsake** (boon_trinket)
Type: accessory | Theme: hades | Rarity: rare
Glow: #FFD700
Save to: assets/icons/forged/accessories/boon_trinket.png

Create a 256x256 game icon for "Olympian Keepsake" - a rare accessory from Hades.

Visual elements: Greek-style pendant with laurel wreath motif. Golden metal with divine sheen. Small lightning bolt or olive branch detail. Ornate border with Greek key pattern. Warm golden glow of Olympian blessing. Gift from the gods above.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FFD700

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 61. **Winged Golden Strawberry** (winged_strawberry)
Type: accessory | Theme: celeste | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/accessories/winged_strawberry.png

Create a 256x256 game icon for "Winged Golden Strawberry" - a legendary accessory from Celeste.

Visual elements: Plump strawberry made of solid gold with crystalline sheen. Small angelic white wings sprouting from the sides. Leaf stem in emerald green. Seeds visible as small golden dots. Heavenly golden glow radiating outward. The ultimate prize - perfection achieved.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 62. **Devil's Pitchfork** (devil_pitchfork)
Type: weapon | Theme: cuphead | Rarity: legendary
Glow: #DC143C
Save to: assets/icons/forged/weapons/devil_pitchfork.png

Create a 256x256 game icon for "Devil's Pitchfork" - a legendary weapon from Cuphead.

Visual elements: Classic three-pronged pitchfork with 1930s cartoon styling. Deep crimson red metal with black accents. Slightly curved prongs with menacing sharpness. Long ebony handle with ornate demonic carvings. Hellfire red flames licking up from the tines. Retro cartoon devil aesthetic meets real menace.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #DC143C

POLEARM ORIENTATION: Side profile, tip pointing to upper-right, shaft to lower-left. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 63. **King Slayer** (king_slayer)
Type: weapon | Theme: dead_cells | Rarity: legendary
Glow: #00FF00
Save to: assets/icons/forged/weapons/king_slayer.png

Create a 256x256 game icon for "King Slayer" - a legendary weapon from Dead Cells.

Visual elements: Jagged biological-looking sword with mutated cell structures visible. Sickly green blade with organic veiny patterns. Biomechanical hilt that seems to grow from the blade. Dripping green mutation fluid. Bright toxic green glow pulsing through. Rogue-like chaos made manifest.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00FF00

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 64. **Corrupted Heart Shard** (heart_shard)
Type: accessory | Theme: slay_the_spire | Rarity: legendary
Glow: #FF6B6B
Save to: assets/icons/forged/accessories/heart_shard.png

Create a 256x256 game icon for "Corrupted Heart Shard" - a legendary accessory from Slay the Spire.

Visual elements: Crystalline heart fragment pulsing with malevolent red energy. Jagged broken edges where it was torn from the whole. Deep red-pink coloring with darker corruption veins. Geometric card-game inspired facets. Red glow emanating from cracks. Fragment of the ultimate challenge conquered.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FF6B6B

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 65. **Companion Cube** (companion_cube)
Type: accessory | Theme: portal | Rarity: rare
Glow: #FFB6C1
Save to: assets/icons/forged/accessories/companion_cube.png

Create a 256x256 game icon for "Companion Cube" - a rare accessory from Portal.

Visual elements: Grey weighted storage cube with distinctive pink heart on each visible face. Clean Aperture Science aesthetic - metal panels with rounded corners. Pink accent color on hearts. Slightly worn test chamber appearance. Soft pink glow of companionship. Your best friend. Never forget.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FFB6C1

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 66. **Lambda Badge** (lambda_badge)
Type: accessory | Theme: valve | Rarity: rare
Glow: #FF8C00
Save to: assets/icons/forged/accessories/lambda_badge.png

Create a 256x256 game icon for "Lambda Badge" - a rare accessory from Valve.

Visual elements: Orange-red circular badge with Greek lambda (λ) symbol. Clean spray-painted resistance logo aesthetic. Worn metal badge backing. Black lambda on bright orange field. Orange glow suggesting rebellion energy. Half-Life resistance fighter's mark of allegiance.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FF8C00

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 67. **Dragonbone Helm** (dragonbone_helm)
Type: armor_head | Theme: skyrim | Rarity: epic
Glow: #4A5568
Save to: assets/icons/forged/armor/dragonbone_helm.png

Create a 256x256 game icon for "Dragonbone Helm" - an epic helmet/headgear from Skyrim.

Visual elements: Intimidating helmet carved from actual dragon bones. Ivory-white bone material with visible texture and joints. Small curved horns protruding from the sides. Spiky ridge along the crown. Dark eye sockets for menacing appearance. Grey bone glow suggesting dragon's ancient power. The ultimate Nordic warrior's prize.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #4A5568

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 68. **Grandmaster Wolf Armor** (grandmaster_armor)
Type: armor_chest | Theme: witcher | Rarity: legendary
Glow: #E6B833
Save to: assets/icons/forged/armor/grandmaster_armor.png

Create a 256x256 game icon for "Grandmaster Wolf Armor" - a legendary chest armor from The Witcher.

Visual elements: Layered leather and chainmail armor with wolf medallion prominent at the chest. Dark brown and black leather with silver chainmail visible beneath. Wolf head emblem in silver at the collar. Witcher school buckles and straps. Golden trim on the edges. Golden glow from the wolf medallion. Master witcher's battle-tested gear.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #E6B833

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 69. **Ashen Armor** (ashen_armor)
Type: armor_chest | Theme: dark_souls | Rarity: rare
Glow: #FF6A00
Save to: assets/icons/forged/armor/ashen_armor.png

Create a 256x256 game icon for "Ashen Armor" - a rare chest armor from Dark Souls.

Visual elements: Simple chainmail armor over dark leather. Ash-grey metal rings with visible link pattern. Tattered cloth tabard hanging over the chest. Worn, weathered appearance of countless deaths. Orange ember glow seeping through the chains. Humble beginnings - the armor of one who rises again.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FF6A00

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 70. **Elden Armory Chestplate** (elden_armory_chest)
Type: armor_chest | Theme: elden_ring | Rarity: epic
Glow: #FFD700
Save to: assets/icons/forged/armor/elden_armory_chest.png

Create a 256x256 game icon for "Elden Armory Chestplate" - an epic chest armor from Elden Ring.

Visual elements: Ornate bronze chestplate with weapon silhouettes engraved across the surface. Burnished bronze-gold metal with divine patina. Multiple legendary weapon symbols etched into the plate. Elaborate Erdtree filigree around the edges. Golden divine glow from the engravings. Collector's armor - every legendary weapon's blessing.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FFD700

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 71. **Eye of Cthulhu Shield** (eye_of_cthulhu_shield)
Type: shield | Theme: terraria | Rarity: rare
Glow: #00FF80
Save to: assets/icons/forged/shields/eye_of_cthulhu_shield.png

Create a 256x256 game icon for "Eye of Cthulhu Shield" - a rare shield from Terraria.

Visual elements: Round shield with giant eyeball design dominating the face. Bloodshot white with large central pupil staring outward. Veiny red tendrils around the edges like eyelid tissue. Gore-red trim around the outer rim. Green eldritch glow from the pupil. First major trophy - the Eye sees all.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00FF80

SHIELD ORIENTATION: Front-facing, centered, symmetrical. Show the face of the shield clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 72. **Ironclad's Plate** (ironclad_armor)
Type: armor_chest | Theme: slay_the_spire | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/armor/ironclad_armor.png

Create a 256x256 game icon for "Ironclad's Plate" - a legendary chest armor from Slay the Spire.

Visual elements: Heavy battle-worn iron chestplate with distinctive red accents. Dented and scarred surface from countless battles. Playing card suits subtly engraved into the metal. Bold red cloth underneath visible at the edges. Golden glow from relic power within. Warrior's determination made steel.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 73. **Loremaster's Hood** (loremaster_hood)
Type: armor_head | Theme: wow | Rarity: legendary
Glow: #9370DB
Save to: assets/icons/forged/armor/loremaster_hood.png

Create a 256x256 game icon for "Loremaster's Hood" - a legendary helmet/headgear from World of Warcraft.

Visual elements: Deep purple scholarly hood with mystical runes embroidered in gold. Soft fabric draping around an invisible face. Ancient tome or scroll symbol at the brow. Golden knowledge-light emanating from within the hood. Aged, well-traveled fabric texture. Purple arcane glow. Keeper of all stories.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #9370DB

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 74. **Master Farmer's Hoe** (master_hoe)
Type: weapon | Theme: stardew | Rarity: rare
Glow: #FFD700
Save to: assets/icons/forged/weapons/master_hoe.png

Create a 256x256 game icon for "Master Farmer's Hoe" - a rare weapon from Stardew Valley.

Visual elements: Elegant golden farming hoe with polished metal blade. Warm honey-gold metal head with gentle sheen. Wooden handle wrapped in worn leather. Small stardrop-shaped gem embedded near the head. Golden glow of mastery emanating outward. The pinnacle of farming expertise.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FFD700

AXE/HAMMER ORIENTATION: Handle from lower-left to head at upper-right. Head slightly oversized. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 75. **Prairie King's Poncho** (prairie_king_cape)
Type: cape | Theme: stardew | Rarity: legendary
Glow: #CD853F
Save to: assets/icons/forged/capes/prairie_king_cape.png

Create a 256x256 game icon for "Prairie King's Poncho" - a legendary cape/cloak from Stardew Valley.

Visual elements: Dusty brown-tan poncho with Western fringe along the edges. Faded desert colors - browns, tans, burnt orange. Sheriff star or cactus motif subtly visible. Worn, sun-bleached fabric texture. Copper-brown glow of frontier legend. Wild West arcade hero's signature garb.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #CD853F

CAPE ORIENTATION: Front-facing or slight drape view, centered, symmetrical. Show the design/emblem clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 76. **Stardrop Pendant** (stardrop_pendant)
Type: amulet | Theme: stardew | Rarity: epic
Glow: #FFD700
Save to: assets/icons/forged/accessories/stardrop_pendant.png

Create a 256x256 game icon for "Stardrop Pendant" - an epic amulet/necklace from Stardew Valley.

Visual elements: Star-shaped pendant with seven points glowing with cosmic energy. Pale blue-gold crystalline material. Delicate silver chain visible above. Each point of the star representing a collected stardrop. Warm golden glow with sparkle particles. Taste of the cosmos contained within.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FFD700

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 77. **Survivor's Vest** (survivor_vest)
Type: armor_chest | Theme: valve | Rarity: rare
Glow: #556B2F
Save to: assets/icons/forged/armor/survivor_vest.png

Create a 256x256 game icon for "Survivor's Vest" - a rare chest armor from Valve.

Visual elements: Military tactical vest in olive drab with multiple pouches. Bloodstains and zombie scratch marks across the fabric. Visible ammunition magazines in pouches. Frayed straps showing heavy use. Dark green survival glow. Battle-worn apocalypse survivor's essential gear.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #556B2F

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 78. **Prince's Laurel Crown** (zagreus_helm)
Type: armor_head | Theme: hades | Rarity: epic
Glow: #FFD700
Save to: assets/icons/forged/armor/zagreus_helm.png

Create a 256x256 game icon for "Prince's Laurel Crown" - an epic helmet/headgear from Hades.

Visual elements: Classical Greek laurel wreath crown in shimmering gold. Delicate olive leaves woven together. Red gemstone or skull motif at the front. Underworld flames subtly visible between leaves. Golden divine glow of Olympian heritage. Prince of the underworld's rightful crown.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FFD700

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 79. **Ezio's Hidden Blade** (ezios_hidden_blade)
Type: weapon | Theme: assassins_creed | Rarity: legendary
Glow: #FFFFFF
Save to: assets/icons/forged/weapons/ezios_hidden_blade.png

Create a 256x256 game icon for "Ezio's Hidden Blade" - a legendary weapon from Assassin's Creed.

Visual elements: Sleek concealed wrist-blade extended from bracer mechanism. Polished steel blade with deadly sharp point. Ornate leather and metal bracer with Assassin insignia. Mechanical spring mechanism visible. Clean white luminescence along blade edge. Renaissance engineering meets lethal precision.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFFFFF

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 80. **Sam Fisher's Ka-Bar** (sam_fishers_kabar)
Type: weapon | Theme: splinter_cell | Rarity: legendary
Glow: #2F4F4F
Save to: assets/icons/forged/weapons/sam_fishers_kabar.png

Create a 256x256 game icon for "Sam Fisher's Ka-Bar" - a legendary weapon from Splinter Cell.

Visual elements: Military combat knife with black-finished blade. Distinctive Ka-Bar profile with clip point. Dark grey textured grip for stealth operations. Matte non-reflective coating. Subtle dark teal night-vision glow along edge. Covert operator's silent companion.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #2F4F4F

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 81. **Agent 47's Fiber Wire** (fiber_wire)
Type: weapon | Theme: hitman | Rarity: legendary
Glow: #8B0000
Save to: assets/icons/forged/weapons/fiber_wire.png

Create a 256x256 game icon for "Agent 47's Fiber Wire" - a legendary weapon from Hitman.

Visual elements: Thin metallic garrote wire coiled in a figure-eight loop. Red wooden or metal handles at each end. Steel wire gleaming with deadly purpose. Professional, clinical appearance. Dark crimson glow suggesting silent lethality. Assassin's most intimate tool.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #8B0000

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 82. **StatTrakÃ¢â€žÂ¢ Karambit** (csgo_karambit)
Type: weapon | Theme: counter_strike | Rarity: epic
Glow: #FF4500
Save to: assets/icons/forged/weapons/csgo_karambit.png

Create a 256x256 game icon for "StatTrak Karambit" - an epic weapon from Counter-Strike.

Visual elements: Curved claw-shaped knife with distinctive ring on the grip. Fade pattern gradient - purple to pink to yellow. Polished steel with holographic sheen. StatTrak digital counter visible on the blade spine. Orange-red energy glow from the ring. The ultimate CS flex made real.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FF4500

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 83. **Ranni's Dark Moon Ring** (rannis_dark_moon_ring)
Type: ring | Theme: elden_ring | Rarity: epic
Glow: #4169E1
Save to: assets/icons/forged/accessories/rannis_dark_moon_ring.png

Create a 256x256 game icon for "Ranni's Dark Moon Ring" - an epic ring from Elden Ring.

Visual elements: Elegant silver ring with dark crescent moon centerpiece. Deep royal blue gem surrounded by starfield pattern. Frost crystals forming on the band. Cold ethereal glow emanating from the moon symbol. Witch-like lunar energy particles. Consort's pledge to the dark moon.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #4169E1

RING ORIENTATION: Top-down or straight-on ring presentation, centered and symmetrical. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 84. **Havel's Ring** (havel_ring)
Type: ring | Theme: dark_souls | Rarity: rare
Glow: #708090
Save to: assets/icons/forged/accessories/havel_ring.png

Create a 256x256 game icon for "Havel's Ring" - a rare ring from Dark Souls.

Visual elements: Heavy stone ring carved from grey granite. Rough, rocky texture visible on the band. Small boulder or dragon tooth motif on top. Solid, immovable weight suggested by thick band. Grey-blue stone glow. The Rock's gift - carry everything.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #708090

RING ORIENTATION: Top-down or straight-on ring presentation, centered and symmetrical. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 85. **Amulet of Kings** (amulet_of_kings)
Type: amulet | Theme: elder_scrolls | Rarity: legendary
Glow: #FF0000
Save to: assets/icons/forged/accessories/amulet_of_kings.png

Create a 256x256 game icon for "Amulet of Kings" - a legendary amulet/necklace from Elder Scrolls.

Visual elements: Ornate golden amulet with large red Akatosh gemstone. Dragon or dragonborn symbol engraved into the metal. Heavy gold chain with Imperial links. Ancient Cyrodilic runic inscriptions. Crimson divine glow from the central gem. Symbol of Imperial authority and dragonblood lineage.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FF0000

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 86. **Wraith's Kunai** (apex_heirloom_kunai)
Type: weapon | Theme: apex_legends | Rarity: legendary
Glow: #7B68EE
Save to: assets/icons/forged/weapons/apex_heirloom_kunai.png

Create a 256x256 game icon for "Wraith's Kunai" - a legendary weapon from Apex Legends.

Visual elements: Sleek futuristic kunai with void energy crackling along the blade. Dark steel with purple phase-shift energy accents. Angular sci-fi design. Dimensional rift particles emanating from the tip. Purple void glow pulsing through. Ultra-rare heirloom status made manifest.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #7B68EE

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 87. **Black Ice Weapon Skin** (r6_black_ice_skin)
Type: accessory | Theme: rainbow_six | Rarity: legendary
Glow: #00CED1
Save to: assets/icons/forged/accessories/r6_black_ice_skin.png

Create a 256x256 game icon for "Black Ice Weapon Skin" - a legendary accessory from Rainbow Six Siege.

Visual elements: Crystalline ice shard pattern in cyan and black. Frozen glacier texture with deep blue depths. Sharp angular ice formations. Translucent blue-white surface catching light. Cyan frozen glow from within. The legendary skin made tangible.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00CED1

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 88. **Thompson SMG** (rust_thompson)
Type: weapon | Theme: rust | Rarity: epic
Glow: #A9A9A9
Save to: assets/icons/forged/weapons/rust_thompson.png

Create a 256x256 game icon for "Thompson SMG" - an epic weapon from Rust.

Visual elements: Classic 1920s-style submachine gun with drum magazine. Worn gunmetal grey finish with rust spots. Distinctive cooling fins on the barrel. Wooden stock and grip worn smooth. Crude post-apocalyptic repairs visible. Grey steel glow of makeshift power.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #A9A9A9

FIREARM ORIENTATION: Side profile, barrel pointing RIGHT, stock toward lower-left. Muzzle at upper-right. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 89. **Diamond Pickaxe** (minecraft_diamond_pickaxe)
Type: tool | Theme: minecraft | Rarity: rare
Glow: #00FFFF
Save to: assets/icons/forged/tools/minecraft_diamond_pickaxe.png

Create a 256x256 game icon for "Diamond Pickaxe" - a rare tool from Minecraft.

Visual elements: Pixelated diamond pickaxe with iconic blocky design. Bright cyan diamond head with faceted surfaces. Brown wooden stick handle. Clean geometric Minecraft aesthetic. Enchantment shimmer particles (purple sparkles). Cyan diamond glow. The ultimate mining tool.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00FFFF

AXE/HAMMER ORIENTATION: Handle from lower-left to head at upper-right. Head slightly oversized. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 90. **Tyrael's Might** (tyraels_might)
Type: armor_chest | Theme: diablo | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/armor/tyraels_might.png

Create a 256x256 game icon for "Tyrael's Might" - a legendary chest armor from Diablo.

Visual elements: Radiant white-gold plate armor with angelic wing motifs. Heavenly light emanating from within. Pristine metal with divine craftsmanship. Justice scales or sword emblems engraved on chest. Wings of light subtly visible at shoulders. Golden divine glow of the High Heavens. Archangel's protection made wearable.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 91. **Stone of Jordan** (stone_of_jordan)
Type: ring | Theme: diablo | Rarity: legendary
Glow: #4169E1
Save to: assets/icons/forged/accessories/stone_of_jordan.png

Create a 256x256 game icon for "Stone of Jordan" - a legendary ring from Diablo.

Visual elements: Simple gold ring with a brilliant blue sapphire. Clean, ancient design with minimal ornamentation. The gem seems impossibly deep, like looking into the void. Subtle arcane runes around the band. Royal blue glow emanating from the stone. Currency of legends - the ultimate trading symbol.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #4169E1

RING ORIENTATION: Top-down or straight-on ring presentation, centered and symmetrical. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 92. **The Butcher's Cleaver** (butchers_cleaver)
Type: weapon | Theme: diablo | Rarity: legendary
Glow: #8B0000
Save to: assets/icons/forged/weapons/butchers_cleaver.png

Create a 256x256 game icon for "The Butcher's Cleaver" - a legendary weapon from Diablo.

Visual elements: Massive meat cleaver with dark bloodstained blade. Rusty iron covered in dried gore. Crude wrapped handle made from bone and leather. Jagged, chipped edge from countless kills. Hooks or meat fragments hanging from the blade. Dark crimson blood glow. Fresh meat incarnate.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #8B0000

AXE/HAMMER ORIENTATION: Handle from lower-left to head at upper-right. Head slightly oversized. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 93. **Horadric Cube** (horadric_cube)
Type: accessory | Theme: diablo | Rarity: legendary
Glow: #FF8C00
Save to: assets/icons/forged/accessories/horadric_cube.png

Create a 256x256 game icon for "Horadric Cube" - a legendary accessory from Diablo.

Visual elements: Ancient cubic box with mystical golden patterns on each face. Bronze-gold metal with arcane geometric inscriptions. Faint glow seeping from the seams as if power is contained within. Horadrim symbols etched on the sides. Orange arcane energy particles floating around it. Infinite transmutation potential.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FF8C00

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 94. **El'druin, the Sword of Justice** (el_druins_sword)
Type: weapon | Theme: diablo | Rarity: epic
Glow: #87CEEB
Save to: assets/icons/forged/weapons/el_druins_sword.png

Create a 256x256 game icon for "El'druin, the Sword of Justice" - an epic weapon from Diablo.

Visual elements: Elegant angelic longsword radiating holy light. Blade of pure white-gold luminescence. Crossguard shaped like angelic wings. Crystal blue gems embedded in the hilt. Divine light particles trailing from the blade. Sky blue holy glow. Justice incarnate in sword form.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #87CEEB

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 95. **Natalya's Shadow** (natalyas_shadow)
Type: armor_chest | Theme: diablo | Rarity: epic
Glow: #2F4F4F
Save to: assets/icons/forged/armor/natalyas_shadow.png

Create a 256x256 game icon for "Natalya's Shadow" - an epic chest armor from Diablo.

Visual elements: Sleek dark leather armor designed for stealth. Deep charcoal and black layered leather. Shadow magic wisping off the edges. Concealed blade holsters visible. Hooded collar for anonymity. Dark teal-grey shadow glow. Assassin's perfect camouflage made armor.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #2F4F4F

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 96. **Echoing Fury** (echoing_fury)
Type: weapon | Theme: diablo | Rarity: epic
Glow: #9400D3
Save to: assets/icons/forged/weapons/echoing_fury.png

Create a 256x256 game icon for "Echoing Fury" - an epic weapon from Diablo.

Visual elements: Demonic mace with screaming faces embedded in the head. Dark purple metal with swirling soul energy. Multiple tortured faces visible in the weapon surface. Spectral wails visualized as purple wisps. Skull motif on the handle. Purple demonic glow of captured fury. Weapon that screams with each swing.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #9400D3

AXE/HAMMER ORIENTATION: Handle from lower-left to head at upper-right. Head slightly oversized. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 97. **Black Soulstone** (black_soulstone)
Type: amulet | Theme: diablo | Rarity: rare
Glow: #000000
Save to: assets/icons/forged/accessories/black_soulstone.png

Create a 256x256 game icon for "Black Soulstone" - a rare amulet/necklace from Diablo.

Visual elements: Ominous black crystal pendant pulsing with evil. Void-black surface with crimson veins of corruption. Seven subtle demonic symbols etched within. Dark energy swirling inside the stone. Heavy iron chain visible above. Void-black glow with red corruption hints. Container of ultimate evil.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #000000

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 98. **Andariel's Visage** (andariel_visage)
Type: armor_head | Theme: diablo | Rarity: rare
Glow: #00FF00
Save to: assets/icons/forged/armor/andariel_visage.png

Create a 256x256 game icon for "Andariel's Visage" - a rare helmet/headgear from Diablo.

Visual elements: Demonic horned helm dripping with poison. Dark green corrupted metal with organic growths. Curved demon horns sweeping backward. Toxic green venom dripping from the edges. Insectoid design elements. Sickly green poison glow. Maiden of Anguish's toxic presence.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00FF00

HELMET ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show the face/visor area clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 99. **Genji's Dragon Blade** (genji_dragonblade)
Type: weapon | Theme: overwatch | Rarity: legendary
Glow: #00FF00
Save to: assets/icons/forged/weapons/genji_dragonblade.png

Create a 256x256 game icon for "Genji's Dragon Blade" - a legendary weapon from Overwatch.

Visual elements: Sleek futuristic katana with glowing green dragon spirit energy. High-tech blade with circuit patterns. Green dragon spirit coiling around the blade. Carbon-fiber handle with tech grips. Neon green energy crackling along the edge. Cyber-ninja perfection.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00FF00

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 100. **Tracer's Chronal Accelerator** (tracer_chronal_accelerator)
Type: accessory | Theme: overwatch | Rarity: legendary
Glow: #FF8C00
Save to: assets/icons/forged/accessories/tracer_chronal_accelerator.png

Create a 256x256 game icon for "Tracer's Chronal Accelerator" - a legendary accessory from Overwatch.

Visual elements: Glowing circular chest device with time-energy core. Bright orange-blue energy swirling in the center. Sleek white and orange housing. Harness straps visible around the edges. Time distortion particles emanating outward. Orange chronal energy glow. The anchor to the present.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FF8C00

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 101. **Reaper's Hellfire Shotguns** (reaper_hellfire_shotguns)
Type: weapon | Theme: overwatch | Rarity: legendary
Glow: #000000
Save to: assets/icons/forged/weapons/reaper_hellfire_shotguns.png

Create a 256x256 game icon for "Reaper's Hellfire Shotguns" - a legendary weapon from Overwatch.

Visual elements: Twin black shotguns crossed in an X pattern. Matte black metal with skull motifs. Red-orange hellfire glowing in the barrels. Smoke or shadow wisping off the weapons. Death reaper aesthetic with angular design. Black void glow with hellfire accents. Death's personal arsenal.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #000000

FIREARM ORIENTATION: Side profile, barrel pointing RIGHT, stock toward lower-left. Muzzle at upper-right. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 102. **Doomfist's Gauntlet** (doomfist_gauntlet)
Type: armor_hands | Theme: overwatch | Rarity: legendary
Glow: #FF4500
Save to: assets/icons/forged/armor/doomfist_gauntlet.png

Create a 256x256 game icon for "Doomfist's Gauntlet" - a legendary gauntlets/gloves from Overwatch.

Visual elements: Massive mechanical power gauntlet in black and gold. Oversized fist with rocket propulsion vents. Orange-red energy core visible in the knuckles. Talon insignia etched into the metal. Imposing, devastating weapon aesthetic. Orange energy glow from power cells. Fist that ends wars.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FF4500

GAUNTLETS ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Single gauntlet or matching pair.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 103. **Reinhardt's Crusader Armor** (reinhardt_crusader_armor)
Type: armor_chest | Theme: overwatch | Rarity: epic
Glow: #4682B4
Save to: assets/icons/forged/armor/reinhardt_crusader_armor.png

Create a 256x256 game icon for "Reinhardt's Crusader Armor" - an epic chest armor from Overwatch.

Visual elements: Massive powered plate armor in steel blue and gold. Lion crest emblazoned on the chest. Heavy pauldrons with crusader cross motifs. Thick metal plates with rivets and battle damage. Rocket boosters visible at the back. Steel blue energy glow. German engineering meets medieval knight.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #4682B4

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 104. **Mercy's Caduceus Staff** (mercy_caduceus_staff)
Type: weapon | Theme: overwatch | Rarity: epic
Glow: #FFD700
Save to: assets/icons/forged/weapons/mercy_caduceus_staff.png

Create a 256x256 game icon for "Mercy's Caduceus Staff" - an epic weapon from Overwatch.

Visual elements: Elegant healing staff with angelic medical design. White and gold with glowing yellow energy core. Twin serpent or wing motifs wrapped around the head. Bio-stream emitter at the top. Sleek, compassionate technology aesthetic. Golden healing energy glow. Valkyrie's instrument of salvation.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FFD700

STAFF ORIENTATION: Side profile, head/focus at upper-right, base at lower-left. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 105. **Winston's Jump Pack** (winston_jump_pack)
Type: cape | Theme: overwatch | Rarity: epic
Glow: #87CEEB
Save to: assets/icons/forged/capes/winston_jump_pack.png

Create a 256x256 game icon for "Winston's Jump Pack" - an epic cape/cloak from Overwatch.

Visual elements: Bulky scientific jetpack with twin boosters. White and blue color scheme with tech panels. Glowing blue energy coils. Primate-sized proportions, clearly overbuilt. Exhaust vents and power cells visible. Sky blue propulsion energy glow. Genius gorilla engineering.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #87CEEB

CAPE ORIENTATION: Front-facing or slight drape view, centered, symmetrical. Show the design/emblem clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 106. **Widowmaker's Kiss** (widowmaker_kiss)
Type: weapon | Theme: overwatch | Rarity: rare
Glow: #9400D3
Save to: assets/icons/forged/weapons/widowmaker_kiss.png

Create a 256x256 game icon for "Widowmaker's Kiss" - a rare weapon from Overwatch.

Visual elements: Sleek futuristic sniper rifle with spider motifs. Deep purple and black color scheme. Elegant, feminine curves to the design. Advanced scope with targeting systems. Purple venom-like energy in the barrel. Purple deadly precision glow. The last thing many see.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #9400D3

FIREARM ORIENTATION: Side profile, barrel pointing RIGHT, stock toward lower-left. Muzzle at upper-right. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 107. **Orisa's Halt Projector** (orisa_halt_projector)
Type: accessory | Theme: overwatch | Rarity: rare
Glow: #00FF00
Save to: assets/icons/forged/accessories/orisa_halt_projector.png

Create a 256x256 game icon for "Orisa's Halt Projector" - a rare accessory from Overwatch.

Visual elements: Spherical graviton device with green energy core. Black and green Numbani design aesthetics. Concentric rings suggesting gravity manipulation. Floating green energy particles around it. Tech-forward African-inspired patterns. Green graviton glow. Pull everything to the center.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00FF00

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 108. **Raynor's Marine Armor** (raynor_marine_armor)
Type: armor_chest | Theme: starcraft | Rarity: legendary
Glow: #4682B4
Save to: assets/icons/forged/armor/raynor_marine_armor.png

Create a 256x256 game icon for "Raynor's Marine Armor" - a legendary chest armor from StarCraft.

Visual elements: Massive blue-grey CMC powered combat suit. Heavy armored plating with Raider insignia. Ammunition belt across the chest. Visor slot for helmet integration. Battle damage and kill tallies visible. Steel blue Terran military glow. The armor of a revolutionary leader.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #4682B4

CHESTPLATE ORIENTATION: Front-facing, centered, symmetrical. No rotation or perspective. Show full torso armor.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 109. **Kerrigan's Psi-Blade** (kerrigan_psi_blade)
Type: weapon | Theme: starcraft | Rarity: legendary
Glow: #9400D3
Save to: assets/icons/forged/weapons/kerrigan_psi_blade.png

Create a 256x256 game icon for "Kerrigan's Psi-Blade" - a legendary weapon from StarCraft.

Visual elements: Organic wing-blade made of Zerg carapace. Bone-like chitin structure with sharp edges. Purple psionic energy crackling along the blade. Living weapon that seems to breathe. Zerg organic textures and patterns. Purple psionic glow. The Queen's evolved claws.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #9400D3

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 110. **Protoss Warp Prism** (protoss_warp_prism)
Type: accessory | Theme: starcraft | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/accessories/protoss_warp_prism.png

Create a 256x256 game icon for "Protoss Warp Prism" - a legendary accessory from StarCraft.

Visual elements: Crystalline prism device radiating golden Protoss energy. Geometric faceted crystal structure. Khaydarin crystal blue-gold glow within. Warp field distortion visible around it. Elegant Protoss architecture aesthetic. Golden warp energy emanating outward. Power to reshape battlefield.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

ACCESSORY ORIENTATION: Natural object orientation chosen for silhouette clarity. Centered, readable, non-character presentation. Choose angle that makes it instantly recognizable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 111. **Zeratul's Warp Blade** (zeratul_warp_blade)
Type: weapon | Theme: starcraft | Rarity: legendary
Glow: #00CED1
Save to: assets/icons/forged/weapons/zeratul_warp_blade.png

Create a 256x256 game icon for "Zeratul's Warp Blade" - a legendary weapon from StarCraft.

Visual elements: Curved psionic blade of solid cyan void energy. Dark Templar wrist gauntlet generating the blade. No physical metal - pure psionic energy. Shadow and void particles trailing behind. Alien geometric patterns in the energy. Cyan void glow. Shadow warrior's signature weapon.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00CED1

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 112. **Artanis's Psi Blades** (artanis_psi_blades)
Type: weapon | Theme: starcraft | Rarity: epic
Glow: #FFD700
Save to: assets/icons/forged/weapons/artanis_psi_blades.png

Create a 256x256 game icon for "Artanis's Psi Blades" - an epic weapon from StarCraft.

Visual elements: Twin golden psionic blades extending from wrist gauntlets. Brilliant golden Protoss energy construction. Elegant curved blades like divine light. Khalai geometric patterns within the energy. Hierarch's gauntlets ornate and regal. Golden psionic glow. Leader of the Daelaam's weapons.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FFD700

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 113. **Siege Tank Cannon** (siege_tank_cannon)
Type: weapon | Theme: starcraft | Rarity: epic
Glow: #FF4500
Save to: assets/icons/forged/weapons/siege_tank_cannon.png

Create a 256x256 game icon for "Siege Tank Cannon" - an epic weapon from StarCraft.

Visual elements: Massive 120mm artillery cannon barrel. Heavy industrial Terran military design. Dark grey metal with heat venting. Siege mode hydraulics visible. Orange-red heat glow in the barrel. Shell casings or ammo visible. Orange firepower glow. Pure Terran devastation.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FF4500

FIREARM ORIENTATION: Side profile, barrel pointing RIGHT, stock toward lower-left. Muzzle at upper-right. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 114. **Dark Templar Shroud** (dark_templar_armor)
Type: cape | Theme: starcraft | Rarity: epic
Glow: #2F4F4F
Save to: assets/icons/forged/capes/dark_templar_armor.png

Create a 256x256 game icon for "Dark Templar Shroud" - an epic cape/cloak from StarCraft.

Visual elements: Flowing shadow-woven cloak that seems to consume light. Deep purple-black fabric with void energy at the edges. Nerazim tribal patterns faintly visible. Shoulder clasps in dark metal. Shadow particles dissolving off the hem. Dark teal shadow glow. The shroud of those who walk unseen.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #2F4F4F

CAPE ORIENTATION: Front-facing or slight drape view, centered, symmetrical. Show the design/emblem clearly.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 115. **Zergling Claws** (zergling_claws)
Type: weapon | Theme: starcraft | Rarity: rare
Glow: #9400D3
Save to: assets/icons/forged/weapons/zergling_claws.png

Create a 256x256 game icon for "Zergling Claws" - a rare weapon from StarCraft.

Visual elements: Curved organic claws grown from Zerg chitin. Sharp bone-like talons with purple energy veins. Living tissue connecting the claw segments. Serrated edges for rending. Purple psionic glow from within. Speed and violence made biological weapon.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #9400D3

BLADE ORIENTATION: Side profile, blade tip pointing to upper-right, hilt anchored lower-left. Blade occupies 65-75% of icon. 30-40 degree upward tilt.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 116. **Khala Amulet** (khala_amulet)
Type: amulet | Theme: starcraft | Rarity: rare
Glow: #00CED1
Save to: assets/icons/forged/accessories/khala_amulet.png

Create a 256x256 game icon for "Khala Amulet" - a rare amulet/necklace from StarCraft.

Visual elements: Crystalline Protoss amulet pulsing with psionic energy. Khaydarin crystal core glowing cyan-blue. Elegant geometric Protoss architecture. Gold-teal metal frame holding the crystal. Psionic link visualization around it. Cyan Khala glow. Unity of all Protoss minds.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00CED1

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

================================================================================
# WAVE 1: ARMOR FEET & LEGS (20 items, #117-136)
# Provider Balance: Steam (5), PlayStation (5), Xbox (5), Battle.net (5)
================================================================================

## 117. **Apex Predator Boots** (apex_predator_boots)
Type: armor_feet | Theme: apex_legends | Rarity: epic
Glow: #FF0000
Save to: assets/icons/forged/armor/apex_predator_boots.png

Create a 256x256 game icon for "Apex Predator Boots" - epic boots from Apex Legends.

Visual elements: Sleek futuristic combat boots with angular predatory design. Black and crimson color scheme. Red energy lines running along the sides. Armored toe caps with aggressive styling. Jump kit propulsion vents visible. Red predator glow from energy accents. Top of the food chain footwear.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FF0000

BOOTS ORIENTATION: Front-facing, single boot or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 118. **Portal Longfall Boots** (portal_longfall_boots)
Type: armor_feet | Theme: portal | Rarity: epic
Glow: #FF8C00
Save to: assets/icons/forged/armor/portal_longfall_boots.png

Create a 256x256 game icon for "Portal Longfall Boots" - epic boots from Portal.

Visual elements: White hi-tech boots with distinctive orange springs at the heel. Aperture Science logo visible on the side. Clean laboratory aesthetic. Visible shock absorption mechanisms. Metal and polymer construction. Orange portal energy glow. Land from any height.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FF8C00

BOOTS ORIENTATION: Front-facing, single boot or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 119. **Cuphead's Dancing Shoes** (cuphead_dancing_shoes)
Type: armor_feet | Theme: cuphead | Rarity: legendary
Glow: #DC143C
Save to: assets/icons/forged/armor/cuphead_dancing_shoes.png

Create a 256x256 game icon for "Cuphead's Dancing Shoes" - legendary boots from Cuphead.

Visual elements: Round 1930s cartoon-style shoes with exaggerated curves. Black and white with pie-cut eyes style accents. Rubber-hose animation bounce lines. Slightly oversized proportions. Cartoon motion blur effects. Crimson retro glow. Straight from the inkwell era.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #DC143C

BOOTS ORIENTATION: Front-facing, single boot or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 120. **Mountaineer's Trousers** (mountaineer_trousers)
Type: armor_legs | Theme: celeste | Rarity: epic
Glow: #E85D8C
Save to: assets/icons/forged/armor/mountaineer_trousers.png

Create a 256x256 game icon for "Mountaineer's Trousers" - epic leg armor from Celeste.

Visual elements: Practical hiking pants in blue-grey with strawberry-pink accents. Lightweight technical fabric with reinforced knees. Chalk dust marks from climbing. Small strawberry patch on pocket. Pink determination glow from the accents. Summit-ready, feather-light construction.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #E85D8C

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 121. **Survivor's Pants** (survivor_pants)
Type: armor_legs | Theme: dead_cells | Rarity: legendary
Glow: #00FF00
Save to: assets/icons/forged/armor/survivor_pants.png

Create a 256x256 game icon for "Survivor's Pants" - legendary leg armor from Dead Cells.

Visual elements: Tattered prison pants infused with green cell mutation. Tears and rips showing glowing green flesh beneath. Organic tendrils wrapping around the fabric. Biomechanical patches and repairs. Toxic green mutation glow from within. Death and rebirth woven into cloth.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00FF00

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 122. **Hunter's Boots** (hunter_boots)
Type: armor_feet | Theme: bloodborne | Rarity: epic
Glow: #8B0000
Save to: assets/icons/forged/armor/hunter_boots.png

Create a 256x256 game icon for "Hunter's Boots" - epic boots from Bloodborne.

Visual elements: Victorian-era leather hunting boots worn and blood-stained. Dark brown leather with silver buckles. Dried beast blood splatters across the surface. Worn soles from cobblestone streets. Gothic Yharnam aesthetic. Deep crimson blood glow. A hunter is never alone.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #8B0000

BOOTS ORIENTATION: Front-facing, single boot or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 123. **Aloy's Strider Boots** (aloy_strider_boots)
Type: armor_feet | Theme: horizon | Rarity: rare
Glow: #4169E1
Save to: assets/icons/forged/armor/aloy_strider_boots.png

Create a 256x256 game icon for "Aloy's Strider Boots" - rare boots from Horizon Zero Dawn.

Visual elements: Tribal leather boots with integrated machine components. Nora tribe aesthetic with salvaged tech. Blue machine cables woven through the design. Metal panels from dismantled machines. Handmade meets high-tech fusion. Blue machine glow from components. Where old world meets new.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #4169E1

BOOTS ORIENTATION: Front-facing, single boot or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 124. **Berserker Tassets** (berserker_tassets)
Type: armor_legs | Theme: god_of_war | Rarity: legendary
Glow: #C41E3A
Save to: assets/icons/forged/armor/berserker_tassets.png

Create a 256x256 game icon for "Berserker Tassets" - legendary leg armor from God of War.

Visual elements: Heavy Norse leg armor with Spartan influence. Dark metal with red rune engravings. Rage energy emanating from the seams. Battle scars and dents from gods' fights. Fur trim at the edges. Blood-red rage glow. The Ghost of Sparta's lower armor.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #C41E3A

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 125. **Ghost Hakama** (ghost_hakama)
Type: armor_legs | Theme: ghost_of_tsushima | Rarity: epic
Glow: #1A1A2E
Save to: assets/icons/forged/armor/ghost_hakama.png

Create a 256x256 game icon for "Ghost Hakama" - epic leg armor from Ghost of Tsushima.

Visual elements: Dark flowing hakama pants in samurai style. Deep indigo-black fabric with subtle armor beneath. Ghost mask motif subtly embroidered. Traditional pleating with hidden reinforcement. Moonlit shadow aura. Dark night-blue glow. The path of the Ghost.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #1A1A2E

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 126. **Returnal Scout Greaves** (returnal_scout_greaves)
Type: armor_legs | Theme: returnal | Rarity: rare
Glow: #00CED1
Save to: assets/icons/forged/armor/returnal_scout_greaves.png

Create a 256x256 game icon for "Returnal Scout Greaves" - rare leg armor from Returnal.

Visual elements: Sleek ASTRA suit leg armor with angular alien design. Dark grey with cyan energy conduits. Weathered from countless death cycles. Xeno-tech interface panels visible. Loop distortion particles around it. Cyan alien glow. Countless deaths, one destiny.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00CED1

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 127. **Pirate Legend Boots** (pirate_legend_boots)
Type: armor_feet | Theme: sea_of_thieves | Rarity: epic
Glow: #1E90FF
Save to: assets/icons/forged/armor/pirate_legend_boots.png

Create a 256x256 game icon for "Pirate Legend Boots" - epic boots from Sea of Thieves.

Visual elements: Ornate captain's boots with gold trim and buckles. Deep brown leather weathered by salt and sea. Ghostly blue legendary glow emanating within. Skull and crossbones subtle embossing. Sea-worn but prestigious. Blue legendary pirate glow. A thousand voyages walked.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #1E90FF

BOOTS ORIENTATION: Front-facing, single boot or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 128. **Spartan Greaves** (spartan_greaves)
Type: armor_feet | Theme: halo | Rarity: legendary
Glow: #00FF00
Save to: assets/icons/forged/armor/spartan_greaves.png

Create a 256x256 game icon for "Spartan Greaves" - legendary boots from Halo.

Visual elements: MJOLNIR powered armor boots in olive drab green. Heavy plating with magnetic boot soles. Gold visor accent panels. Military sci-fi utilitarian design. Tech ports and armor joints visible. Green Spartan glow from power systems. Finish the fight.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00FF00

BOOTS ORIENTATION: Front-facing, single boot or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 129. **COG Stompers** (cog_stompers)
Type: armor_legs | Theme: gears | Rarity: epic
Glow: #990000
Save to: assets/icons/forged/armor/cog_stompers.png

Create a 256x256 game icon for "COG Stompers" - epic leg armor from Gears of War.

Visual elements: Chunky military leg armor in COG grey. Heavy armored plates with crimson Omen symbol. Knee reinforcement for curb stomping. Utilitarian, brutal design. Battle damage and Locust blood stains. Crimson COG glow. Built for war, not comfort.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #990000

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 130. **Pilot's Flight Pants** (pilot_flight_pants)
Type: armor_legs | Theme: titanfall | Rarity: rare
Glow: #FF6600
Save to: assets/icons/forged/armor/pilot_flight_pants.png

Create a 256x256 game icon for "Pilot's Flight Pants" - rare leg armor from Titanfall.

Visual elements: Tactical flight suit pants in dark grey with orange accents. Jump kit thruster mounts on thighs. Aerodynamic design for wallrunning. Tech straps and equipment pouches. Burn marks from thruster use. Orange pilot energy glow. Ready for the drop.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FF6600

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 131. **Diamond Leggings** (diamond_leggings)
Type: armor_legs | Theme: minecraft | Rarity: rare
Glow: #00BFFF
Save to: assets/icons/forged/armor/diamond_leggings.png

Create a 256x256 game icon for "Diamond Leggings" - rare leg armor from Minecraft.

Visual elements: Pixelated diamond leg armor in iconic Minecraft blocky style. Bright cyan-blue diamond facets. Clean geometric 8-bit aesthetic. Enchantment shimmer particles (purple sparkles). Crystalline surface catching light. Cyan diamond glow. Every miner's dream armor.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00BFFF

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 132. **Tier Set Sabatons** (tier_set_sabatons)
Type: armor_feet | Theme: wow | Rarity: epic
Glow: #B34DCC
Save to: assets/icons/forged/armor/tier_set_sabatons.png

Create a 256x256 game icon for "Tier Set Sabatons" - epic boots from World of Warcraft.

Visual elements: Ornate plate armor boots with mythic raid detailing. Gold and purple color scheme. Intricate engravings and gem inlays. Arcane purple glow from power runes. Spiky pauldron-style toe caps. Mythic purple glow. Cutting Edge prestige on your feet.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #B34DCC

BOOTS ORIENTATION: Front-facing, single boot or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 133. **Marauder's Treads** (marauder_treads)
Type: armor_feet | Theme: diablo | Rarity: rare
Glow: #8B4513
Save to: assets/icons/forged/armor/marauder_treads.png

Create a 256x256 game icon for "Marauder's Treads" - rare boots from Diablo.

Visual elements: Demon Hunter set boots. Dark leather boots with crossbow bolt holders and demon-hunting aesthetic. No demon escapes.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #8B4513

BOOTS ORIENTATION: Front-facing, single boot or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 134. **Lich King Legplates** (lich_king_legplates)
Type: armor_legs | Theme: wow | Rarity: legendary
Glow: #00BFFF
Save to: assets/icons/forged/armor/lich_king_legplates.png

Create a 256x256 game icon for "Lich King Legplates" - legendary leg armor from World of Warcraft.

Visual elements: Saronite plate leg armor radiating death knight frost. Ice-blue metal with glowing frost runes. Spiked knee plates in Scourge style. Frozen chains and icicles at the edges. Frostmourne energy blue glow. There must always be a Lich King.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00BFFF

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 135. **Tracer's Leggings** (tracer_leggings)
Type: armor_legs | Theme: overwatch | Rarity: rare
Glow: #FF7F00
Save to: assets/icons/forged/armor/tracer_leggings.png

Create a 256x256 game icon for "Tracer's Leggings" - rare leg armor from Overwatch.

Visual elements: Sleek flight suit leggings in orange and brown. Chronal accelerator-compatible design. Time-energy conduits running along sides. Athletic, aerodynamic cut. Orange chronal glow at the accents. Cheers, love!

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FF7F00

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 136. **Zealot Greaves** (zealot_greaves)
Type: armor_legs | Theme: starcraft | Rarity: epic
Glow: #00CED1
Save to: assets/icons/forged/armor/zealot_greaves.png

Create a 256x256 game icon for "Zealot Greaves" - epic leg armor from StarCraft.

Visual elements: Golden Protoss leg armor with elegant alien design. Psionic cyan energy flowing through conduits. Khaydarin crystal accents at the knees. Geometric Protoss architecture. Cyan psionic glow. My life for Aiur!

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #00CED1

LEG ARMOR ORIENTATION: Front-facing, show as pants/greaves, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

================================================================================
# WAVE 2: ARMS, HANDS & SHIELDS (21 items, #137-157)
# Provider Balance: Steam (6), PlayStation (5), Xbox (5), Battle.net (5)
================================================================================

## 137. **Abyss Watcher Vambraces** (abyss_watcher_vambraces)
Type: armor_arms | Theme: dark_souls | Rarity: epic
Glow: #4A6B8A
Save to: assets/icons/forged/armor/abyss_watcher_vambraces.png

Create a 256x256 game icon for "Abyss Watcher Vambraces" - epic arm guards from Dark Souls.

Visual elements: Pointed metal vambraces with wolf emblem engraved. Blue-grey patina from Artorias' legacy. Sharp, aggressive silhouette. Wolf blood aura emanating. Blue-grey wolf blood glow. The Abyss Watchers stand eternal.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #4A6B8A

ARM ARMOR ORIENTATION: Front-facing, single bracer or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 138. **Blacksmith's Gloves** (blacksmith_gloves)
Type: armor_hands | Theme: stardew | Rarity: rare
Glow: #8B4513
Save to: assets/icons/forged/armor/blacksmith_gloves.png

Create a 256x256 game icon for "Blacksmith's Gloves" - rare gloves from Stardew Valley.

Visual elements: Well-worn leather work gloves with forge spark marks. Brown leather darkened by heat and soot. Reinforced palms for hammer work. Warm, cozy, practical design. Brown leather glow from forge warmth. Every item shipped.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #8B4513

GAUNTLET ORIENTATION: Front-facing, single gauntlet or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 139. **Marksman's Gloves** (marksman_gloves)
Type: armor_hands | Theme: counter_strike | Rarity: epic
Glow: #FF4500
Save to: assets/icons/forged/armor/marksman_gloves.png

Create a 256x256 game icon for "Marksman's Gloves" - epic gloves from Counter-Strike.

Visual elements: Tactical fingerless gloves in black with orange accents. Textured grip pads on fingers and palm. StatTrak-style digital counter on wrist. Professional esports aesthetic. Orange StatTrak glow. Pixel-perfect precision.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FF4500

GAUNTLET ORIENTATION: Front-facing, single gauntlet or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 140. **Grass Crest Vambraces** (grass_crest_vambraces)
Type: armor_arms | Theme: dark_souls | Rarity: rare
Glow: #228B22
Save to: assets/icons/forged/armor/grass_crest_vambraces.png

Create a 256x256 game icon for "Grass Crest Vambraces" - rare arm guards from Dark Souls.

Visual elements: Green-tinted metal bracers with grass crest emblem. Leaves and vines subtly engraved on surface. Stamina regeneration aura particles. Forest green metal patina. Green stamina glow emanating. Praise the grass!

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #228B22

ARM ARMOR ORIENTATION: Front-facing, single bracer or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 141. **Aegis of Champions** (aegis_of_champions)
Type: shield | Theme: dota | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/shields/aegis_of_champions.png

Create a 256x256 game icon for "Aegis of Champions" - legendary shield from Dota 2.

Visual elements: Iconic Aegis of the Immortal trophy design. Silver-gold metallic shield with ornate engravings. Championship wings motif. Immortal energy radiating from center. Golden championship glow. The International's greatest prize.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

SHIELD ORIENTATION: Front-facing, centered, symmetrical. Show the face of the shield clearly, emblem/design readable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 142. **Thief's Handwraps** (thief_handwraps)
Type: armor_hands | Theme: skyrim | Rarity: rare
Glow: #2F4F4F
Save to: assets/icons/forged/armor/thief_handwraps.png

Create a 256x256 game icon for "Thief's Handwraps" - rare gloves from Skyrim.

Visual elements: Dark leather handwraps worn thin from use. Stealthy black cloth with reinforced fingertips. Shadow magic aura wisping off. Subtle lockpick pouches visible. Dark shadow glow. Light fingers, heavy pockets.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #2F4F4F

GAUNTLET ORIENTATION: Front-facing, single gauntlet or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 143. **Hunter's Forearm Guards** (hunter_forearm_guards)
Type: armor_arms | Theme: bloodborne | Rarity: epic
Glow: #8B0000
Save to: assets/icons/forged/armor/hunter_forearm_guards.png

Create a 256x256 game icon for "Hunter's Forearm Guards" - epic arm guards from Bloodborne.

Visual elements: Victorian-era leather bracers with dried blood stains. Dark brown with silver buckles. Beast claw marks visible on surface. Gothic Yharnam craftsmanship. Crimson old blood glow. Fear the old blood.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #8B0000

ARM ARMOR ORIENTATION: Front-facing, single bracer or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 144. **Leviathan Vambraces** (leviathan_vambraces)
Type: armor_arms | Theme: god_of_war | Rarity: epic
Glow: #87CEEB
Save to: assets/icons/forged/armor/leviathan_vambraces.png

Create a 256x256 game icon for "Leviathan Vambraces" - epic arm guards from God of War.

Visual elements: Norse-inspired metal bracers infused with Leviathan frost. Ice crystals forming on the surface. Runic engravings glowing blue. Frost particles emanating outward. Icy blue Leviathan glow. The axe remembers.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #87CEEB

ARM ARMOR ORIENTATION: Front-facing, single bracer or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 145. **Guardian Shield** (guardian_shield)
Type: shield | Theme: horizon | Rarity: epic
Glow: #4169E1
Save to: assets/icons/forged/shields/guardian_shield.png

Create a 256x256 game icon for "Guardian Shield" - epic shield from Horizon Zero Dawn.

Visual elements: Tribal shield integrated with machine parts. Blue cables and lenses from salvaged machines. Handcrafted wood and leather base. Machine eye lens as centerpiece. Blue machine glow from tech components. Override protocol engaged.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #4169E1

SHIELD ORIENTATION: Front-facing, centered, symmetrical. Show the face of the shield clearly, emblem/design readable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 146. **Samurai Kote** (samurai_kote)
Type: armor_hands | Theme: ghost_of_tsushima | Rarity: epic
Glow: #1A1A2E
Save to: assets/icons/forged/armor/samurai_kote.png

Create a 256x256 game icon for "Samurai Kote" - epic gloves from Ghost of Tsushima.

Visual elements: Traditional Japanese armored gloves (kote) in dark samurai style. Lacquered plates with silk bindings. Ghost stance shadow energy wisping off. Indigo-black coloring. Dark ghost stance glow. The way of the Ghost.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #1A1A2E

GAUNTLET ORIENTATION: Front-facing, single gauntlet or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 147. **Atropos Bracers** (atropos_bracers)
Type: armor_arms | Theme: returnal | Rarity: rare
Glow: #00CED1
Save to: assets/icons/forged/armor/atropos_bracers.png

Create a 256x256 game icon for "Atropos Bracers" - rare arm guards from Returnal.

Visual elements: Sleek ASTRA suit bracers with alien influence. Dark grey with cyan adrenaline pulse conduits. Loop-worn weathering visible. Xeno-tech interface nodes. Cyan alien energy glow. The cycle continues.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00CED1

ARM ARMOR ORIENTATION: Front-facing, single bracer or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 148. **MJOLNIR Bracers** (mjolnir_bracers)
Type: armor_arms | Theme: halo | Rarity: legendary
Glow: #00FF00
Save to: assets/icons/forged/armor/mjolnir_bracers.png

Create a 256x256 game icon for "MJOLNIR Bracers" - legendary arm guards from Halo.

Visual elements: MJOLNIR powered armor bracers in olive drab green. Heavy plating with gold visor accents. Shield recharge systems glowing. Tech ports and armor seams visible. Green Spartan energy glow. Spartans never die.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00FF00

ARM ARMOR ORIENTATION: Front-facing, single bracer or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 149. **Captain's Buckler** (captain_buckler)
Type: shield | Theme: sea_of_thieves | Rarity: rare
Glow: #1E90FF
Save to: assets/icons/forged/shields/captain_buckler.png

Create a 256x256 game icon for "Captain's Buckler" - rare shield from Sea of Thieves.

Visual elements: Weathered wooden buckler with gold captain's trim. Salt-worn wood with brass rivets. Compass or anchor motif on face. Sea spray particle effects around it. Blue ocean glow. Every captain needs a backup plan.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #1E90FF

SHIELD ORIENTATION: Front-facing, centered, symmetrical. Show the face of the shield clearly, emblem/design readable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 150. **COG Gauntlets** (cog_gauntlets)
Type: armor_hands | Theme: gears | Rarity: epic
Glow: #990000
Save to: assets/icons/forged/armor/cog_gauntlets.png

Create a 256x256 game icon for "COG Gauntlets" - epic gloves from Gears of War.

Visual elements: Bulky metal gauntlets in COG grey with crimson accents. Reinforced knuckles for brutal melee. Chainsaw grip texture on palms. Crimson omen symbol on back. Crimson COG glow. Rev it up.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #990000

GAUNTLET ORIENTATION: Front-facing, single gauntlet or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 151. **Pilot's Bracers** (pilot_bracers)
Type: armor_arms | Theme: titanfall | Rarity: rare
Glow: #FF6600
Save to: assets/icons/forged/armor/pilot_bracers.png

Create a 256x256 game icon for "Pilot's Bracers" - rare arm guards from Titanfall.

Visual elements: Tactical bracers with jump kit arm mounts. Dark grey with orange thruster vents. Pilot boost tech visible. Aerodynamic for wallrunning. Orange pilot energy glow. Protocol 3: Protect the Pilot.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FF6600

ARM ARMOR ORIENTATION: Front-facing, single bracer or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 152. **Netherite Gauntlets** (netherite_gauntlets)
Type: armor_hands | Theme: minecraft | Rarity: rare
Glow: #4A4A4A
Save to: assets/icons/forged/armor/netherite_gauntlets.png

Create a 256x256 game icon for "Netherite Gauntlets" - rare gloves from Minecraft.

Visual elements: Dark grey blocky netherite gauntlets in Minecraft style. Ancient debris texture with fiery undertones. Pixel-art aesthetic. Lava-resistant sheen visible. Dark grey netherite glow. Ancient debris reforged.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #4A4A4A

GAUNTLET ORIENTATION: Front-facing, single gauntlet or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 153. **Paladin's Bulwark** (paladin_bulwark)
Type: shield | Theme: wow | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/shields/paladin_bulwark.png

Create a 256x256 game icon for "Paladin's Bulwark" - legendary shield from World of Warcraft.

Visual elements: Ornate golden tower shield with holy Light emanating. Sacred inscriptions and Light symbols engraved. Divine protection barrier visible. WoW paladin aesthetic with radiant gold trim. Golden holy glow. The Light protects.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

SHIELD ORIENTATION: Front-facing, centered, symmetrical. Show the face of the shield clearly, emblem/design readable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 154. **Crusader Bracers** (crusader_bracers)
Type: armor_arms | Theme: diablo | Rarity: epic
Glow: #FFD700
Save to: assets/icons/forged/armor/crusader_bracers.png

Create a 256x256 game icon for "Crusader Bracers" - epic arm guards from Diablo.

Visual elements: Heavy plate bracers with holy light infusion. Golden metal with divine symbols engraved. Crusader flail motifs visible. Golden holy energy emanating. Akarat's blessing glow. Heaven's champion's armor.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FFD700

ARM ARMOR ORIENTATION: Front-facing, single bracer or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 155. **Reinhardt's Barrier Fragment** (reinhardt_barrier)
Type: shield | Theme: overwatch | Rarity: epic
Glow: #4169E1
Save to: assets/icons/forged/shields/reinhardt_barrier.png

Create a 256x256 game icon for "Reinhardt's Barrier Fragment" - epic shield from Overwatch.

Visual elements: Hexagonal blue energy shield fragment. Translucent barrier shimmer effect visible. Cracked edges where it broke off. Reinhardt's lion emblem faintly visible. Blue barrier energy glow. BARRIER IS HOLDING!

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #4169E1

SHIELD ORIENTATION: Front-facing, centered, symmetrical. Show the face of the shield clearly, emblem/design readable.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 156. **Medic's Gloves** (medic_gloves)
Type: armor_hands | Theme: starcraft | Rarity: rare
Glow: #00FF00
Save to: assets/icons/forged/armor/medic_gloves.png

Create a 256x256 game icon for "Medic's Gloves" - rare gloves from StarCraft.

Visual elements: White and green medical gloves with Terran aesthetic. Healing aura glow emanating. Field medic practical design. Medkit cross symbol visible. Green healing energy glow. Heal your allies.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00FF00

GAUNTLET ORIENTATION: Front-facing, single gauntlet or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 157. **Immortal Bracers** (immortal_bracers)
Type: armor_arms | Theme: wow | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/armor/immortal_bracers.png

Create a 256x256 game icon for "Immortal Bracers" - legendary arm guards from World of Warcraft.

Visual elements: Golden mythic-quality bracers with eternal radiance. Perfect, flawless craftsmanship. Naxxramas skull motif subtly visible. Undying aura emanating. Golden immortal glow. A tribute to perfection.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

ARM ARMOR ORIENTATION: Front-facing, single bracer or matching pair, centered, symmetrical.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

================================================================================
# WAVE 3: RINGS & AMULETS (14 items, #158-171)
# Provider Balance: Steam (4), PlayStation (4), Xbox (3), Battle.net (3)
================================================================================

## 158. **Band of the Scholar** (band_of_scholar)
Type: ring | Theme: hollow_knight | Rarity: rare
Glow: #4A4A6A
Save to: assets/icons/forged/accessories/band_of_scholar.png

Create a 256x256 game icon for "Band of the Scholar" - rare ring from Hollow Knight.

Visual elements: Dark metallic ring with void energy swirling within. Subtle mushroom or grub motifs engraved. Scholar's wisdom runes visible. Void particles drifting off. Dark scholarly glow. The more you know, the more you forget.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #4A4A6A

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 159. **Gravity Ring** (gravity_ring)
Type: ring | Theme: celeste | Rarity: epic
Glow: #E85D8C
Save to: assets/icons/forged/accessories/gravity_ring.png

Create a 256x256 game icon for "Gravity Ring" - epic ring from Celeste.

Visual elements: Pink crystalline ring with gravity distortion warping around it. Space-bending visual effects. Strawberry pink crystal centerpiece. Feather or dash particles floating. Pink gravity glow. Up is a suggestion.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #E85D8C

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 160. **Covenant Ring** (covenant_ring)
Type: ring | Theme: dark_souls | Rarity: legendary
Glow: #FFD700
Save to: assets/icons/forged/accessories/covenant_ring.png

Create a 256x256 game icon for "Covenant Ring" - legendary ring from Dark Souls.

Visual elements: Golden ring with radiant sunlight emblem centerpiece. Warriors of Sunlight aesthetic. Holy sun rays emanating outward. Warm golden divine glow. Solaire's blessing visible. Praise the Sun!

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #FFD700

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 161. **Merchant's Signet** (merchant_signet)
Type: ring | Theme: stardew | Rarity: rare
Glow: #FFD700
Save to: assets/icons/forged/accessories/merchant_signet.png

Create a 256x256 game icon for "Merchant's Signet" - rare ring from Stardew Valley.

Visual elements: Warm golden signet ring with coin emblem centerpiece. Merchant's prosperity sparkle effect. Quality gem setting. Cozy farmhouse wealth aesthetic. Golden prosperity glow. Buy low, sell high.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FFD700

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 162. **Blood Gem Ring** (blood_gem_ring)
Type: ring | Theme: bloodborne | Rarity: epic
Glow: #8B0000
Save to: assets/icons/forged/accessories/blood_gem_ring.png

Create a 256x256 game icon for "Blood Gem Ring" - epic ring from Bloodborne.

Visual elements: Dark iron ring with blood-red gem centerpiece. Crimson blood dripping from the gem. Gothic Yharnam craftsmanship. Old blood corruption visible in the metal. Crimson blood glow. The old blood courses through.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #8B0000

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 163. **Valkyrie's Band** (valkyrie_band)
Type: ring | Theme: god_of_war | Rarity: epic
Glow: #C0C0C0
Save to: assets/icons/forged/accessories/valkyrie_band.png

Create a 256x256 game icon for "Valkyrie's Band" - epic ring from God of War.

Visual elements: Silver ring forged from Valkyrie metal. Delicate wing motifs engraved around band. Ethereal Norse shimmer effect. Odin's blessing visible. Silver ethereal glow. Worthy of Valhalla.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #C0C0C0

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 164. **Focus Lens Amulet** (focus_lens_amulet)
Type: amulet | Theme: horizon | Rarity: epic
Glow: #4169E1
Save to: assets/icons/forged/accessories/focus_lens_amulet.png

Create a 256x256 game icon for "Focus Lens Amulet" - epic amulet from Horizon.

Visual elements: Blue technological medallion with Focus lens as centerpiece. Scanning pulse effect visible. Machine-tech integrated into tribal frame. Blue holographic data streams. Blue machine scan glow. See what others cannot.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #4169E1

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 165. **Astronaut Figurine Charm** (astronaut_charm)
Type: amulet | Theme: returnal | Rarity: rare
Glow: #00CED1
Save to: assets/icons/forged/accessories/astronaut_charm.png

Create a 256x256 game icon for "Astronaut Figurine Charm" - rare amulet from Returnal.

Visual elements: Small astronaut figurine charm on simple chain. Cyan alien energy glowing within the suit. Loop-cycle shimmer effect around it. Helios mission insignia visible. Cyan loop glow. Helios. Returner.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00CED1

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 166. **Legendary Ring** (legendary_ring_halo)
Type: ring | Theme: halo | Rarity: legendary
Glow: #00FF00
Save to: assets/icons/forged/accessories/legendary_ring_halo.png

Create a 256x256 game icon for "Legendary Ring" - legendary ring from Halo.

Visual elements: Green MJOLNIR-style ring with Spartan aesthetic. Energy sword glow effect emanating. Master Chief's visor gold visible. Legendary skull motif subtly present. Green Spartan energy glow. Were it so easy.

Style: Painted game item icon, dark transparent background. Legendary quality item.
Color accent/glow: #00FF00

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 167. **Athena's Favor** (athena_favor)
Type: ring | Theme: hades | Rarity: epic
Glow: #FFD700
Save to: assets/icons/forged/accessories/athena_favor.png

Create a 256x256 game icon for "Athena's Favor" - epic ring from Hades.

Visual elements: Golden ring with owl emblem centerpiece. Aegis shimmer deflection effect visible. Greek geometric patterns engraved. Divine wisdom aura. Golden goddess blessing glow. My aid is given freely.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #FFD700

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 168. **Ancient Core Amulet** (ancient_core_amulet)
Type: amulet | Theme: zelda | Rarity: rare
Glow: #00BFFF
Save to: assets/icons/forged/accessories/ancient_core_amulet.png

Create a 256x256 game icon for "Ancient Core Amulet" - rare amulet from Legend of Zelda.

Visual elements: Blue glowing Sheikah core amulet with eye motif. Ancient technology pulsing with energy. Geometric Sheikah patterns engraved. Guardian-tech aesthetic. Blue Sheikah glow. The Calamity has been sealed.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #00BFFF

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 169. **Sigil of the Mage** (sigil_of_mage)
Type: ring | Theme: wow | Rarity: epic
Glow: #8A2BE2
Save to: assets/icons/forged/accessories/sigil_of_mage.png

Create a 256x256 game icon for "Sigil of the Mage" - epic ring from World of Warcraft.

Visual elements: Silver band inscribed with glowing arcane runes. Purple amethyst centerpiece crackling with arcane energy. Magical sparks and arcane symbols floating around the ring. Deep violet glow emanating from the runes. Mage's scholarly power. Knowledge is power.

Style: Painted game item icon, dark transparent background. Epic quality item.
Color accent/glow: #8A2BE2

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 170. **Horadric Charm** (horadric_charm)
Type: amulet | Theme: diablo | Rarity: rare
Glow: #FFD700
Save to: assets/icons/forged/accessories/horadric_charm.png

Create a 256x256 game icon for "Horadric Charm" - rare amulet from Diablo.

Visual elements: Aged gold medallion with cube-inspired geometric design. Ancient Horadric runes etched into surface, glowing with golden light. Weathered patina showing great age. Small amber gem at center. Warm golden aura. Deckard Cain's blessing. Stay awhile and listen.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #FFD700

AMULET ORIENTATION: Front-facing medallion presentation with centered emblem. Chain minimal and secondary. Vertical symmetry, emblem readable at small sizes.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

## 171. **Xel'Naga Artifact Ring** (xelnaga_ring)
Type: ring | Theme: starcraft | Rarity: rare
Glow: #9400D3
Save to: assets/icons/forged/accessories/xelnaga_ring.png

Create a 256x256 game icon for "Xel'Naga Artifact Ring" - rare ring from StarCraft.

Visual elements: Alien crystalline ring with impossible geometry. Dark purple void energy swirling within. Xel'Naga artifact patterns - angular, ancient, unknowable. Protoss-like golden accents. Deep violet void glow pulsing outward. Cosmic power contained. The cycle must be broken.

Style: Painted game item icon, dark transparent background. Rare quality item.
Color accent/glow: #9400D3

RING ORIENTATION: Top-down or straight-on circle view. Ring opening clearly visible, gem/emblem centered. No tilt, no perspective depth.

Style requirements: Icon-focused design with bold simplified shapes, minimal fine texture, strong silhouette clarity, readable at small sizes. Avoid micro-textures and excessive detail.

Format: 256x256 PNG with transparency, centered with padding. Will be downscaled to 64x64.

--------------------------------------------------------------------------------

