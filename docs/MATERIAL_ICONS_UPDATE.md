# Material & Consumable Icons Update

**Date**: 2025-12-14
**Status**: ✅ Complete - All Icons Replaced with Assets

---

## 📋 OVERVIEW

Replaced procedurally generated icons for materials and consumables with hand-crafted asset icons from `readyicon/materials/`. This provides a more polished and professional appearance for inventory items.

---

## 🎨 MATERIAL ICONS (10/10 Complete)

All material items now use dedicated PNG icons instead of procedural generation.

| Item Name | Filename | Source File | Status |
|-----------|----------|-------------|--------|
| Bone Ember | `bone_ember.png` | boneember.png | ✅ Replaced |
| Old Bones | `old_bones.png` | bonestack.png | ✅ Replaced |
| Broken Sword | `broken_sword.png` | broken_sword.png | ✅ Replaced |
| Cursed Femur | `cursed_femur.png` | cursedfemur.png | ✅ Replaced |
| Dry Log | `dry_log.png` | drylog.png | ✅ Replaced |
| Lich's Finger Bone | `lichs_finger_bone.png` | lichfinger.png | ✅ Replaced |
| Dusty Gem | `dusty_gem.png` | redgem.png | ✅ Replaced |
| Tarnished Ring | `tarnished_ring.png` | ring.png | ✅ Replaced |
| Ancient Skull | `ancient_skull.png` | skull.png | ✅ Replaced |
| Ancient Coin | `ancient_coin.png` | ancientcoin.png | ✅ Replaced |

**Location**: `assets/icons/materials/`

---

## 🧪 CONSUMABLE ICONS (2/3 Complete)

Consumable items now load from dedicated icon directory.

| Item Name | Consumable Type | Filename | Source File | Status |
|-----------|----------------|----------|-------------|--------|
| Empty Vial | `empty_vial` | `empty_vial.png` | greenvial.png | ✅ Added |
| Purified Water | `purified_water` | `purified_water.png` | greenvial.png | ✅ Added |
| World Tree Seed | `world_tree_seed` | `world_tree_seed.png` | N/A | ❌ **NEEDS ICON** |

**Location**: `assets/icons/consumables/`

---

## 🏕️ PLACEABLE ICONS

| Item Name | Placeable Type | Status |
|-----------|---------------|--------|
| Campfire Kit | `campfire` | ⚠️ Still uses procedural icon |

**Note**: Campfire Kit continues to use the procedural campfire icon (logs + flames) from `ItemIconGenerator._draw_campfire_kit()`. Add `assets/ui/icons/campfire_kit.png` to replace it with an asset.

---

## 🔧 TECHNICAL CHANGES

### **Files Modified**

#### `scripts/systems/ItemIconGenerator.gd`
**Added consumable icon support** (lines 101-110, 692-715):
- New `_get_consumable_icon()` function
- Checks `assets/icons/consumables/{consumable_type}.png`
- Falls back to enhanced icons if available (`assets/icons/enhanced/consumables/`)
- Returns null if no icon found (prevents procedural fallback)

**Material icon priority** (existing, lines 370-389):
1. Enhanced icons: `assets/icons/enhanced/materials/{filename}.png` (256x256)
2. Standard icons: `assets/icons/materials/{filename}.png` (64x64)
3. Procedural generation (fallback)

### **New Directories Created**
- `assets/icons/materials/` - Material item icons (10 files)
- `assets/icons/consumables/` - Consumable item icons (2 files)

### **Files Deleted**
- `readyicon/materials/graychest.png` - Unused asset

---

## 📊 ICON LOADING PRIORITY

The icon system now follows this priority order:

1. **Forged Items**: `assets/icons/forged/{category}/{item_name}.png`
2. **Materials**: `assets/icons/materials/{item_name}.png` → procedural fallback
3. **Consumables**: `assets/icons/consumables/{consumable_type}.png` → null if missing
4. **Placeables**: `assets/ui/icons/{placeable_type}.png` → procedural fallback
5. **Equipment**: Extracted from LPC sprite sheets automatically

---

## 🧪 TESTING CHECKLIST

### Material Icons
- [ ] Open inventory and verify all material items show proper icons
- [ ] Check skeleton corpse loot (Bone Ember, Ancient Skull, Cursed Femur, Lich's Finger Bone)
- [ ] Check treasure chest loot (Old Bones, Broken Sword, Tarnished Ring, Dusty Gem, Ancient Coin)
- [ ] Verify Dry Log icon appears when harvesting trees
- [ ] All icons should be crisp and centered (not pixelated)

### Consumable Icons
- [ ] Buy Empty Vial from vendor (50g) - check icon shows green vial
- [ ] Fill Empty Vial at cleansed lava pool - check Purified Water shows green vial
- [ ] Buy World Tree Seed from vendor (1000g) - currently has NO ICON (expected)

### Placeable Icons
- [ ] Buy Campfire Kit from vendor - still shows procedural campfire icon (logs + flames)

### No Regressions
- [ ] Forged item icons still load correctly
- [ ] Weapon/armor icons still extract from LPC sprites
- [ ] Tool icons (axe, pickaxe) still work

---

## 📝 FUTURE IMPROVEMENTS

1. **World Tree Seed Icon** - Create and add to `assets/icons/consumables/world_tree_seed.png`
2. **Campfire Kit Icon** - Add to `assets/ui/icons/campfire_kit.png` to replace procedural version
3. **Enhanced Icons** - Upscale all material/consumable icons to 256x256 and place in:
   - `assets/icons/enhanced/materials/`
   - `assets/icons/enhanced/consumables/`

---

## 🎮 USER-FACING CHANGES

**Before**: All materials showed generic procedurally-generated icons (colored diamonds, simple shapes)
**After**: All materials show unique, hand-crafted pixel art icons

**Impact**: Much more polished inventory experience with distinct, recognizable item icons.

---

## 💾 BACKUP

Original procedural icon generation code remains in `ItemIconGenerator.gd` as fallback:
- `_draw_bone_ember()` (lines 412-440)
- `_draw_log()` (lines 442-464)
- `_draw_skull()` (lines 466-488)
- `_draw_bone()` (lines 490-505)
- `_draw_finger_bone()` (lines 507-528)
- `_draw_broken_sword()` (lines 530-554)
- `_draw_ring()` (lines 556-580)
- `_draw_gem()` (lines 582-605)
- `_draw_coin()` (lines 607-625)
- `_draw_campfire_kit()` (lines 722-778)

If an icon file is missing or fails to load, the system automatically falls back to procedural generation.

---

## ⚠️ ICON FORMAT FIX (2025-12-14 02:30 AM)

**Problem Found**: All source icons were 1024x1024 RGB (no alpha channel):
- Caused Bone Ember to render huge in loot UI
- Caused Ancient Coin to have white background
- File sizes were 1.2MB each

**Solution**: Created `tools/fix_material_icons.py` to:
1. Resize all icons from 1024x1024 → 64x64
2. Convert from RGB → RGBA (add transparency)
3. Make white backgrounds transparent (threshold: RGB > 240)

**After Fix**:
- All material icons: 64x64 RGBA (~5-11KB each)
- All consumable icons: 64x64 RGBA
- White backgrounds removed (transparent)
- Proper size for inventory display

**Files Fixed**: 10 material icons + 2 consumable icons

---

**Ready for testing in Godot!** 🎮
