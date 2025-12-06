# DREADLAND - itch.io Release Guide

Last Updated: 2025-12-04

---

## Overall Status: **Ready for Alpha/Demo Release**

---

## 1. Core Features Status

| Feature | Status | Notes |
|---------|--------|-------|
| Combat System | Ready | Click-to-attack, crit windows, chain multipliers |
| Multiplayer | Ready | Host/Join, authentication, persistence |
| Inventory | Ready | Drag-drop, equipment slots, loot drops |
| Quest System | Ready | Tutorial + progression quests |
| Character Progression | Ready | Levels 1-30, stats, gear upgrades |
| Death/Corpse System | Ready | EverQuest-style corpse runs, loot recovery |
| PvP Duels | Ready | Consensual `/duel` system |
| Vendors/Economy | Ready | Blacksmith, gold, item shop |
| World | Ready | 24,000x8,000 world, 3 chunks, baked background |
| Group/Party System | Ready | Up to 40 players, shared XP |
| Wolf Enemies | Ready | Pack behavior, howling mechanics |
| Resource Gathering | Ready | Harvestable trees and rocks |

---

## 2. Build Configuration

### Export Presets (export_presets.cfg)

| Export Preset | Platform | Output Path | Status |
|---------------|----------|-------------|--------|
| Windows Desktop | Windows x64 | `../builds/windows/Dreadland.exe` | Configured |
| Linux Server | Linux x64 | `../builds/linux/dreadland_server.x86_64` | Configured |
| Web (HTML5) | Browser | `../builds/web/index.html` | Configured |

### Project Settings
- **Resolution**: 1280x720 default
- **Renderer**: Forward Plus
- **Touch Support**: Enabled (mobile-ready)
- **Godot Version**: 4.5

### How to Export
1. Open project in Godot 4.5+
2. Project → Export
3. Select preset (Windows Desktop recommended for itch.io)
4. Click "Export Project"
5. Test the exported build before uploading

---

## 3. Pre-Release Checklist

### Critical (Must Complete)

- [ ] **Create game icon**
  - File: `icon.svg` or `icon.png` in project root
  - Size: 256x256 minimum (512x512 recommended)
  - Currently missing - project references `res://icon.svg`

- [ ] **Replace placeholder text**
  - `LICENSE`: Replace `[Your Name/Company]`
  - `README.md`: Replace `[Add GitHub URL]`, `[Add Discord invite]`, `[Add contact email]`
  - `CREDITS.md`: Replace `[Your Name]`, `[Your Email]`, `[Credit sound sources]`

- [ ] **Update TODO.md**
  - Mark "Player Corpse System" as completed (currently says NOT YET IMPLEMENTED)

- [ ] **Test Windows export build**
  - Export and run on a clean machine if possible
  - Verify multiplayer host/join works
  - Check all UI elements display correctly

### itch.io Assets Needed

- [ ] **Cover Image**: 630x500 pixels minimum (315x250 displayed)
- [ ] **Screenshots**: 3-5 gameplay images showing:
  - Combat with weakpoints
  - Inventory/character sheet
  - Multiplayer (multiple players)
  - Death screen/corpse
  - Main menu
- [ ] **Game Icon**: 512x512 PNG for itch.io listing
- [ ] **GIF/Trailer**: Optional but recommended

---

## 4. itch.io Page Setup

### Basic Information

**Title**: DREADLAND

**Short Description** (200 chars max):
```
Multiplayer action RPG with click-based combat, critical hit windows, and EverQuest-style corpse runs. Fight skeletons, build chain multipliers, and survive with friends.
```

**Classification**: Game

**Kind of Project**: Downloadable (+ optional HTML5)

**Release Status**: In Development / Prototype

**Pricing**: Free / Name Your Price / Paid (your choice)

### Tags (Recommended)
- Multiplayer
- Action RPG
- Pixel Art
- Co-op
- PvP
- Survival
- Retro
- Top-Down
- Godot

### Full Description Template
```markdown
# DREADLAND

A multiplayer action RPG featuring a unique critical hit weakpoint system and chain multipliers.

## Features

**Combat**
- Click-based combat with satisfying hit feedback
- Critical hit windows with clickable weakpoints
- Chain multiplier system - build up to 10x damage!
- Dodge roll with invincibility frames

**Death & Recovery**
- EverQuest-inspired corpse system
- Die? Your body stays where you fell with all your gear
- Race back to recover your equipment before it's too late

**Multiplayer**
- Host your own server or join friends
- Party system supporting up to 40 players
- Consensual PvP duels with /duel command
- Persistent characters with account system

**Progression**
- Level 1-30 character progression
- 6-slot equipment system (head, chest, arms, hands, legs, feet)
- Vendors sell weapons and armor
- Quest system with tutorial and progression quests

**World**
- Massive 24,000x8,000 pixel world
- Multiple enemy types: Skeletons, Wolves (pack behavior)
- Harvestable resources: Trees, Rocks
- Environmental hazards: Lava pools

## Controls

| Key | Action |
|-----|--------|
| WASD | Move |
| Left Click | Attack |
| Space | Dodge Roll |
| I / B | Inventory |
| C | Character Sheet |
| F | Interact / Loot |
| Enter | Chat |
| ESC | Menu |

## System Requirements

- **OS**: Windows 10+ / Linux
- **Processor**: Any modern CPU
- **Memory**: 4 GB RAM
- **Graphics**: OpenGL 3.3 compatible
- **Storage**: 200 MB

## Credits

Made with Godot Engine 4.5
Character sprites from LPC (Liberated Pixel Cup) community
See CREDITS.md for full attribution
```

---

## 5. Known Limitations (Alpha)

Document these in your itch.io description:

- Single world zone (3 chunks) - more zones planned
- Boss fight not yet implemented
- Base building system planned for future
- Mobile controls in development

---

## 6. Post-Upload Checklist

- [ ] Test download and run from itch.io
- [ ] Verify all screenshots display correctly
- [ ] Check game runs on different Windows versions
- [ ] Set up community/comments if desired
- [ ] Create devlog post for launch
- [ ] Share on social media / Discord

---

## 7. File Structure for Upload

```
builds/
└── windows/
    ├── Dreadland.exe        <- Main executable
    ├── Dreadland.pck        <- Game data (if not embedded)
    └── README.txt           <- Optional: quick start guide
```

**Recommended**: Zip the entire windows folder for upload.

---

## 8. Version Numbering

Current: **v0.4 Alpha**

Suggested format: `v{major}.{minor}.{patch}`
- Major: Significant feature additions
- Minor: New content, balance changes
- Patch: Bug fixes

Update version in:
- `scenes/ui/MainMenu.tscn` → VersionLabel
- itch.io page
- Any release notes

---

## 9. Recommended Release Notes (v0.4)

```markdown
# DREADLAND Alpha v0.4

## What's New
- EverQuest-style player corpse system
- Death screen with coordinates and respawn timer
- Corpse loot UI with equipment display
- Player hidden and untargetable during death
- Enemies properly deaggro on player death

## Features
- Click-based combat with critical hit windows
- Chain multiplier system (up to 10x damage!)
- Multiplayer co-op and PvP duels
- Quest system with tutorial
- Party/group system (up to 40 players)
- Persistent characters with authentication
- Wolf enemies with pack behavior

## Known Issues
- Boss fight not yet available
- Some mobile controls still in development

## Controls
WASD - Move | Click - Attack | Space - Dodge
I - Inventory | C - Character | F - Interact
```

---

## 10. Support Links

Add these to your itch.io page:

- **Bug Reports**: [GitHub Issues URL]
- **Discord**: [Discord Invite]
- **Email**: [Contact Email]

---

## Quick Reference: Export Commands

**From Godot Editor:**
```
Project → Export → Windows Desktop → Export Project
```

**From Command Line (if needed):**
```bash
godot --headless --export-release "Windows Desktop" builds/windows/Dreadland.exe
```

---

## Document History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-04 | 1.0 | Initial release guide created |
