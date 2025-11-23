# Enemy Spawn Tools

## 🎯 Active Tools (Use These)

### 1. `manual_enemy_spawn.gd`
**What:** Visual editor tool for manually placing enemy spawns
**When:** Use when creating new spawn markers in the editor
**How:**
- Add as a script to Marker2D nodes
- Shows colored circles in editor (green=L1-3, yellow=L4-7, etc.)
- Set enemy_level, aggro_range in Inspector

---

### 2. `extend_radial_pattern.gd` ⭐
**What:** Analyzes your L1-3 ring pattern and generates L4-10
**When:** After you've placed your L1-3 enemies in expanding rings
**How:**
- Open this script
- File > Run (Ctrl+Shift+X)
- Generates L4-10 following your pattern
- Respects world boundaries

**Important Settings (top of file):**
```gdscript
const WORLD_MIN_X = -2500.0  # Western edge
const WORLD_MAX_X = 1500.0   # Eastern edge
const WORLD_MIN_Y = -2500.0  # Northern edge
const WORLD_MAX_Y = 2500.0   # Southern edge
```

---

### 3. `delete_generated_spawns.gd`
**What:** Deletes all L4-10 spawns, keeps your manual L1-3
**When:** If you need to undo the radial pattern generation
**How:**
- Open this script
- File > Run (Ctrl+Shift+X)
- All L4+ spawns deleted
- L1-3 kept safe

---

### 4. `rename_spawns_only.gd`
**What:** Renames spawns with proper naming (doesn't move them!)
**When:** To organize your spawn names
**How:**
- Open this script
- File > Run (Ctrl+Shift+X)
- Names become: L1_Patrol_East_1, L2_Patrol_North_3, etc.

---

## 🧹 One-Time Cleanup

### `CLEANUP_OLD_TOOLS.gd`
**What:** Deletes obsolete/broken tool scripts
**When:** Run once to clean up your tools folder
**How:**
- File > Run (Ctrl+Shift+X)
- Waits 3 seconds, then deletes old scripts
- Delete this script after running

---

## 📋 Typical Workflow

1. **Place L1-3 manually** in expanding rings around campfire
2. **Run** `extend_radial_pattern.gd` to generate L4-10
3. **Test in game** to see if you like the pattern
4. If not happy: **Run** `delete_generated_spawns.gd` to undo
5. Adjust your L1-3 placements and try again
6. Once happy: **Save scene** and you're done!

---

## ⚠️ Don't Use These (Obsolete)

- `cleanup_spawns_editor.gd` - Broke positions, archived
- `extend_spawn_pattern_editor.gd` - Old approach, archived
- `delete_out_of_bounds_spawns.gd` - One-time fix, archived
- `UNDO_cleanup_spawns.gd` - Just instructions, archived

Run `CLEANUP_OLD_TOOLS.gd` to delete these automatically.
