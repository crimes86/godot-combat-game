# WORLD BAKING SYSTEM - SETUP GUIDE

## THE PROBLEM:
Generating 80,000+ spots + props every game launch = SLOW

## THE SOLUTION:
Generate once → Bake to PNG → Load instantly

---

## STEP 1: GENERATE THE WORLD (Run Once)

1. Create a new scene in Godot: `world_generation.tscn`
2. Add a Node2D as root
3. Attach `world_generator.gd` to it
4. Make sure you have:
   - `prop_placements.json` in your project
   - All texture files in `res://assets/environment/wasteland/`
5. Run the scene
6. It will create `world_map.png` in your project root
7. Close the scene

---

## STEP 2: USE IT IN YOUR GAME (Every Time)

In your main game scene:

**OLD WAY (SLOW):**
```
GameWorld (with game_world.gd)
├─ generates spots
├─ loads props
└─ creates path
```

**NEW WAY (FAST):**
```
WorldLoader (with world_loader.gd)
└─ loads world_map.png
```

Replace your GameWorld node with a Node2D that has `world_loader.gd` attached.

---

## WHEN TO REGENERATE:

Regenerate `world_map.png` when you change:
- Dark spot density
- Prop placements (run generate_varied_props.gd first)
- Path layout
- Campfire clearing
- Ground colors

**Just run world_generation.tscn again!**

---

## FILE STRUCTURE:

### Generation (run once):
- `world_generator.gd` - Creates everything, bakes to PNG
- `generate_varied_props.gd` - Creates prop_placements.json

### Runtime (every game):
- `world_loader.gd` - Loads the baked PNG
- `world_map.png` - The baked world (18000x6000px)

---

## BENEFITS:
✅ Load time: ~10ms instead of 2000ms
✅ Memory: Single texture instead of 80k+ nodes
✅ Simple: One sprite
✅ Flexible: Regenerate anytime
