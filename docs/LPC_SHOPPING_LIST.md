# LPC Generator Shopping List

Base assets to download from: https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/

After downloading each full spritesheet, run:
```
python tools/lpc_spritesheet_splitter.py split <downloaded.png> <output_dir> --type weapon
```

---

## WEAPONS - Priority Order

### Swords (Different Silhouettes)

| Base Weapon | Save To | Used For |
|-------------|---------|----------|
| Longsword | `assets/equipment/weapons/longsword/` | Grafted Blade, Witcher Silver, Coiled Sword, Farron GS |
| Greatsword | `assets/equipment/weapons/greatsword/` | Starscourge/Radahn's Greatswords |
| Katana | `assets/equipment/weapons/katana/` | Hand of Malenia, Mortal Blade |
| Rapier | `assets/equipment/weapons/rapier/` | Pure Nail (Hollow Knight) |
| Saber/Curved | `assets/equipment/weapons/saber/` | Stygian Blade (Hades) |
| Scimitar | `assets/equipment/weapons/scimitar/` | Future curved sword items |

### Polearms

| Base Weapon | Save To | Used For |
|-------------|---------|----------|
| Spear (basic) | `assets/equipment/weapons/spear/` | Gyoubu's Spear ✓ (have this) |
| Halberd/Ornate Spear | `assets/equipment/weapons/halberd/` | Dragonslayer Swordspear |
| Pike (long spear) | `assets/equipment/weapons/pike/` | Future spear items |

### Other Weapons

| Base Weapon | Save To | Used For |
|-------------|---------|----------|
| Crossbow | `assets/equipment/weapons/crossbow/` | Adamant Rail (Hades) |
| Flail | `assets/equipment/weapons/flail/` | Future items |
| Waraxe | `assets/equipment/weapons/waraxe/` | Future items |
| Staff | `assets/equipment/weapons/staff/` | ✓ (have this) |

---

## ARMOR - Head

| Item | LPC Category | Save To |
|------|--------------|---------|
| Straw Hat | Head → Hats → Straw/Farmer | `assets/equipment/armor/head/straw_hat/` |
| Crown (ornate) | Head → Crowns | `assets/equipment/armor/head/crown_ornate/` |
| Crown (simple) | Head → Crowns | `assets/equipment/armor/head/crown_simple/` |
| Tiara | Head → Tiaras | `assets/equipment/armor/head/tiara/` |
| Laurel Wreath | Head → Crowns/Wreaths | `assets/equipment/armor/head/laurel/` |

---

## ARMOR - Body

| Item | LPC Category | Save To |
|------|--------------|---------|
| Plate Armor (ornate) | Torso → Plate | `assets/equipment/armor/chest/plate_ornate/` |
| Leather Armor (studded) | Torso → Leather | `assets/equipment/armor/chest/leather_studded/` |

---

## CAPES/CLOAKS

| Item | LPC Category | Save To |
|------|--------------|---------|
| Flowing Cloak (black) | Back → Capes | `assets/equipment/capes/cloak_black/` |
| Cape (general) | Back → Capes | `assets/equipment/capes/cape/` |

---

## TOOLS

| Item | LPC Category | Save To |
|------|--------------|---------|
| Hoe | Tools/Weapons → Axes/Hoes | `assets/equipment/tools/hoe/` |

---

## DOWNLOAD CHECKLIST

### Batch 1 - Most Needed
- [ ] Katana
- [ ] Greatsword
- [ ] Rapier
- [ ] Saber/Curved Sword
- [ ] Straw Hat
- [ ] Crown (ornate)
- [ ] Halberd

### Batch 2 - Secondary
- [ ] Crossbow
- [ ] Laurel Wreath
- [ ] Plate Armor (ornate)
- [ ] Leather Armor (studded)
- [ ] Flowing Cloak

### Batch 3 - Nice to Have
- [ ] Flail
- [ ] Waraxe
- [ ] Pike
- [ ] Scimitar
- [ ] Hoe

---

## Quick Commands After Download

```bash
# Split a weapon spritesheet
python tools/lpc_spritesheet_splitter.py split downloads/katana.png assets/equipment/weapons/katana/ --type weapon

# Split armor spritesheet
python tools/lpc_spritesheet_splitter.py split downloads/crown.png assets/equipment/armor/head/crown_ornate/ --type armor

# Create icon from walk sprite
python tools/lpc_sprite_tinter.py icon assets/equipment/weapons/katana/walk.png assets/icons/weapons/katana.png --frame 0,0
```

---

## Notes

- **Weapons**: Download ONLY the weapon layer (clear character body first)
- **Armor**: Can include body for reference, but ideally just the armor layer
- **Colors**: Weapons don't have color options - we tint them with the Python tool
- **Armor colors**: Use LPC generator color options when available
