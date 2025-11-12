# LPC Sprite Guide for Rhythm RPG

## How to Create Custom Characters Using LPC Generator

### 🔗 Generator URL
https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/#

---

## Simple NPCs (Vendors, Quest Givers, etc.)

For non-combat NPCs, you only need **walk animations**. See `Vendor.gd` for an example of how to load a simple 4-frame walk cycle.

**Example:** The Blacksmith uses `blacksmith_walk.png` (256x64 = 4 frames of 64x64)

---

## Complex NPCs (Enemies, Companions, etc.)

For NPCs that need combat animations, use the `LPCCharacter` class which supports walk, slash, and hurt animations with multiple layers.

---

## Creating the Blacksmith Character

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

## Quick Start (Composite Export)

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

## LPC Sprite Format Reference

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

## License & Attribution

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

## Tips for Creating More NPCs

Once you have the blacksmith working, you can easily create:
- **Guards**: Metal armor, helmet, sword
- **Merchants**: Fancy robes, hat
- **Farmers**: Simple clothes, straw hat
- **Mages**: Robes, staff
- **Innkeeper**: Apron, casual clothes

Just repeat the export process and create new NPC scripts using `LPCCharacter` class!

---

## Need Help?

If sprites aren't loading:
1. Check file paths in `BlacksmithNPC.gd`
2. Verify files are exactly 576x256 (walk), 384x256 (slash), or 384x64 (hurt)
3. Check console for error messages from `LPCCharacter`
