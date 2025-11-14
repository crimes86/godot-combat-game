# LPC Sprite Guide for Rhythm RPG

## How to Create Custom Characters Using LPC Generator

### 🔗 Generator URL
https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/#

### 📁 Local Repository
Full LPC repository extracted to: `C:\Fraps\Universal-LPC-Spritesheet-Character-Generator-master (1)\Universal-LPC-Spritesheet-Character-Generator-master\`

---

## 📦 Assets Already Copied to Game

### ⚔️ Armor (4 Zones - 20 pieces total)

**Zone 1: The Wasteland** (Brown Leather - 41 defense)
- Location: `assets/armor/zone1/`
- Chest: Brown leather armor
- Hands: Leather gloves
- Legs: Leather leggings
- Feet: Brown boots
- Head: Bronze nasal helmet

**Zone 2: The Cursed Lands** (Iron/Chainmail - 70 defense)
- Location: `assets/armor/zone2/`
- Chest: Gray chainmail
- Hands: Iron bracers
- Legs: Iron plate greaves
- Feet: Iron plate boots
- Head: Iron barbuta helmet

**Zone 3: The Shadow Realm** (Silver Plate - 100 defense)
- Location: `assets/armor/zone3/`
- Chest: Silver plate armor
- Hands: Silver plate gauntlets
- Legs: Silver plate greaves
- Feet: Silver plate boots
- Head: Silver close helmet (full-face)

**Zone 4: The Abyss** (Dark Gleaming Endgame - EPIC/LEGENDARY)
- Location: `assets/armor/zone4/`
- Chest: Dark legion armor (gunmetal/dark base color)
- Hands: Dark iron plate gauntlets
- Legs: Dark iron plate greaves
- Feet: Dark iron plate boots
- Head: Dark flattop great helmet

### 🗡️ Weapons (9 total)
- Location: `assets/weapons/`
- Club (`club.png`)
- Dagger (`dagger.png`)
- Longsword (`longsword.png`)
- Mace (`mace.png`)
- Spear (`spear.png` - bronze)
- Rapier (`rapier.png`)
- Warhammer (`warhammer.png` - uses waraxe sprite)
- **Glowsword Blue** (`glowsword_blue.png` - legendary drop)
- **Glowsword Red** (`glowsword_red.png` - legendary drop)

### 👾 Enemies (2 types)
- Location: `assets/enemies/`
- **Skeleton** (`skeleton.png`) - Zone 1 enemy
- **Zombie** (`zombie.png`) - Zone 2 enemy type

### 🧙 NPCs (4 sprites)
- Location: `assets/npcs/`
- **Male body** (`male_body.png` - light skin)
- **Female body** (`female_body.png` - light skin)
- **Male vest** (`male_vest.png` - brown merchant clothing)
- **Female robe** (`female_robe.png` - dark brown merchant clothing)

### 🛡️ Shields (4 variants)
- Location: `assets/shields/`
- **Bronze shield** (`shield_bronze.png`) - Zone 1
- **Silver shield** (`shield_silver.png`) - Zone 2/3
- **Gold shield** (`shield_gold.png`) - Zone 3
- **Crusader shield** (`shield_crusader.png`) - Zone 4 endgame

---

## 🎨 Available But Not Yet Copied

These assets exist in the LPC generator and can be added in the future:

### Body Types (Not Yet Used)
- **Muscular** - For elite enemies or bosses
- **Child** - For village NPCs (non-combat)
- **Teen** - For younger NPCs
- **Pregnant** - For NPC variety
- **Fur variants** - For beast-like characters (black, brown, copper, gold, grey, tan, white)

### Clothing & Accessories (Massive Selection)
**Torso/Chest:**
- Blouses (regular, long sleeve)
- Corsets
- Long sleeve shirts (multiple variants)
- Short sleeve shirts
- Sleeveless shirts
- Tunics (multiple styles including "Sara" variant)
- Vests (regular and open)
- Jackets (collared, frock, iverness, pockets, santa, tabard, trench)
- Aprons (full, half, overalls, suspenders)
- Bandages

**Legs:**
- Cuffed pants
- Formal pants (plain and striped)
- Fur leggings
- Hose
- Leggings (2 variants)
- Pantaloons
- Regular pants (2 variants)
- Shorts
- Skirts

**Head/Hair:**
- Beards (5 o'clock shadow, basic, full, muttonchops, goatees, etc.)
- Hair (massive variety - long, short, styled, etc.)
- Hats (formal, headbands, holiday, magic, pirate, visors)
- Helmets (already used most combat types, but decorative variants remain)

### Accessories
- **Backpacks** - Could add inventory visual
- **Bauldrons** - Shoulder armor
- **Capes** - Legendary cosmetic items (solid colors, patterns)
- **Tools** - Rod, whip, smash, thrust (could be weapons or props)
- **Quivers** - For archers
- **Wrists** - Wrist armor/accessories
- **Shoulders** - Shoulder pads/armor

### Additional Weapon Types
**Magical Weapons:**
- Diamond staff (thrust/spellcast animations - dark, light, colored variants)
- Diamond off-hand variant
- Other magical implements

**Melee Weapons:**
- Katana
- Saber
- Scimitar
- Arming sword variants
- Flail
- Halberd
- Longspear
- Dragonspear
- Scythe
- Trident
- Cane

**Ranged Weapons:**
- Bows (various styles)
- Crossbows

### Shield Variants (Not Yet Copied)
- Heater shields
- Kite shields
- Plus shields
- Scutum (Roman style - regular and trim variants)
- Spartan shields
- Two engrailed (regular and trim variants)
- Round shields (black, green, yellow variants not copied)
- Colored variants for all shield types

### Special Features
- **Shadow sprites** - Character shadows for depth
- **Body prosthetics** - Hook hands, peg legs, wheelchairs
- **Wings** - Bat wings, bird wings, etc.
- **Tails** - Animal tails for beast characters
- **Wounds** - Injury overlays

### Enemy/Creature Skins (Body Colors)
Already have skeleton and zombie, but also available:
- Zombie variants (green, different skin tones)
- Alien/fantasy skin colors (blue, green, lavender, pale green)
- Fur textures (for werewolf/beast characters)

---

## 📋 Simple NPCs (Vendors, Quest Givers, etc.)

For non-combat NPCs, you only need **walk animations**. See `Vendor.gd` for an example of how to load a simple 4-frame walk cycle.

**Example:** The Blacksmith uses `blacksmith_walk.png` (256x64 = 4 frames of 64x64)

---

## ⚔️ Complex NPCs (Enemies, Companions, etc.)

For NPCs that need combat animations, use the `LPCCharacter` class which supports walk, slash, and hurt animations with multiple layers.

---

## 🛠️ Creating the Blacksmith Character

### Step 1: Access the Generator
1. Go to the URL above
2. You'll see a character preview with tons of customization options on the left

### Step 2: Configure Blacksmith Appearance

**Body:**
- Select: Male Body
- Skin tone: Your choice (maybe tan/muscular)

**Facial Hair:**
- Select: Beard (any style - maybe "Fullbeard" or "Muttonchops")
- Color: Brown/Black/Grey

**Clothing:**
- **Torso**: Look for "Apron" or "Leather vest"
- **Legs**: Simple brown pants or work trousers
- **Feet**: Brown boots

**Optional:**
- **Arms**: Rolled-up sleeves or bare arms (blacksmith heat!)
- **Head**: Bald, short hair, or bandana

### Step 3: Export the Sprites

**IMPORTANT:** You need THREE sprite sheets for each character:

1. **WALK animations** (9 frames per direction)
   - In generator: Click "Walk" tab
   - Click "Download PNG"
   - Save as: `body_male_walk.png`

2. **SLASH animations** (6 frames per direction - for attacks)
   - In generator: Click "Slash" tab
   - Click "Download PNG"
   - Save as: `body_male_slash.png`

3. **HURT animations** (6 frames)
   - In generator: Click "Hurt" tab
   - Click "Download PNG"
   - Save as: `body_male_hurt.png`

### Step 4: Individual Layer Exports (Advanced)

For maximum flexibility, export layers separately:

**If you want a beard:**
- Customize ONLY the beard (uncheck everything else)
- Export walk/slash/hurt for beard
- Save as: `beard_male_walk.png`, `beard_male_slash.png`, `beard_male_hurt.png`

**If you want an apron:**
- Customize ONLY the torso/apron (uncheck everything else)
- Export walk/slash/hurt
- Save as: `apron_walk.png`, `apron_slash.png`, `apron_hurt.png`

### Step 5: File Organization

Place files in:
```
rhythmrpg/assets/characters/lpc/blacksmith/
├── body_male_walk.png
├── body_male_slash.png
├── body_male_hurt.png
├── beard_male_walk.png
├── beard_male_slash.png
├── beard_male_hurt.png
├── apron_walk.png
├── apron_slash.png
└── apron_hurt.png
```

---

## 🚀 Quick Start (Composite Export)

**Fastest method** if you don't need separate layers:

1. Design full blacksmith in generator (body + beard + clothes all at once)
2. Export all three animation types (walk, slash, hurt)
3. Save as:
   - `blacksmith_walk.png`
   - `blacksmith_slash.png`
   - `blacksmith_hurt.png`
4. Place in: `rhythmrpg/assets/characters/lpc/blacksmith/`

Then in `BlacksmithNPC.gd`, change to:
```gdscript
lpc_character.set_layer("body",
    "res://assets/characters/lpc/blacksmith/blacksmith_walk.png",
    "res://assets/characters/lpc/blacksmith/blacksmith_slash.png",
    "res://assets/characters/lpc/blacksmith/blacksmith_hurt.png"
)
# Remove beard and apron layers if using composite
```

---

## 📐 LPC Sprite Format Reference

All LPC sprites follow this structure:

### Walk Animation (576 x 256 pixels)
- **9 frames per row**
- **4 rows**: UP, LEFT, DOWN, RIGHT
- Frame size: 64x64 pixels

### Slash Animation (384 x 256 pixels)
- **6 frames per row**
- **4 rows**: UP, LEFT, DOWN, RIGHT
- Frame size: 64x64 pixels

### Hurt Animation (384 x 64 pixels)
- **6 frames** in a single row
- Frame size: 64x64 pixels

---

## 📜 License & Attribution

LPC sprites are licensed under multiple licenses:
- GPL 3.0
- CC-BY-SA 3.0
- CC-BY 3.0
- OGA-BY 3.0

**Required attribution:**
Create `CREDITS.txt` in your project root with:

```
Liberated Pixel Cup (LPC) Sprites
- Universal LPC Spritesheet Character Generator
- https://github.com/sanderfrenken/Universal-LPC-Spritesheet-Character-Generator
- Multiple contributors (see repository for full list)
- Licenses: GPL 3.0, CC-BY-SA 3.0, CC-BY 3.0, OGA-BY 3.0
```

---

## 💡 Tips for Creating More NPCs

Once you have the blacksmith working, you can easily create:
- **Guards**: Metal armor, helmet, sword (use Zone 2/3 armor as reference)
- **Merchants**: Fancy robes, hat (use female_robe.png as reference)
- **Farmers**: Simple clothes, straw hat
- **Mages**: Robes, staff (check magical weapon variants)
- **Innkeeper**: Apron, casual clothes (use male_vest.png as reference)
- **Zombies**: Use zombie body type from `assets/enemies/zombie.png`
- **Skeletons**: Use skeleton body from `assets/enemies/skeleton.png`

Just repeat the export process and create new NPC scripts using `LPCCharacter` class!

---

## 🔍 Finding Specific Assets in Local Repository

The local repository is organized by body part:
```
C:\Fraps\Universal-LPC-Spritesheet-Character-Generator-master (1)\
└── Universal-LPC-Spritesheet-Character-Generator-master\
    └── spritesheets\
        ├── arms\          # Arm armor, gloves, bracers
        ├── body\          # Body types, tails, wings, wounds
        ├── dress\         # Dresses and bodices
        ├── feet\          # Boots, shoes, armor
        ├── hair\          # Hair styles
        ├── hat\           # Hats and helmets
        ├── head\          # Head accessories
        ├── legs\          # Pants, leggings, skirts, armor
        ├── shield\        # All shield types
        ├── torso\         # Shirts, armor, jackets, robes
        └── weapon\        # All weapon types
```

Each category is further organized by:
- Gender (male/female/adult)
- Animation type (slash/walk/hurt/thrust/shoot/spellcast)
- Color variants

---

## ❓ Need Help?

If sprites aren't loading:
1. Check file paths in your NPC script
2. Verify files are exactly 576x256 (walk), 384x256 (slash), or 384x64 (hurt)
3. Check console for error messages from `LPCCharacter`
4. Use the local repository to find the exact sprite you need
