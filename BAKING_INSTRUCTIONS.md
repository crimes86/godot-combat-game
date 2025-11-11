# World Baking Instructions

Your game world has been set up to use a pre-baked background texture for instant loading!

## Step 1: Generate the World Texture (ONE TIME ONLY)

1. **Open Godot**
2. **Navigate to** `bake_world_offline.tscn` in the FileSystem
3. **Double-click** to open it (or set it as the main scene temporarily)
4. **Press F5** (or click Play Scene button) to run it
5. **Wait** for it to complete (it will freeze - this is normal and expected!)
6. When done, you'll see: "✨ BAKING COMPLETE!" in the console
7. The scene will automatically close after 3 seconds

## Step 2: Check the Output

The baker will create: `res://assets/environment/baked_world_background.png`

If you don't see this file, check the console output for errors.

## Step 3: Run Your Game

1. **Close** the baker scene
2. **Run main.tscn** (your normal game)
3. The world should now load **instantly** with no freezing!

## What Changed?

**Before:** Generated 267,000 ColorRect nodes at runtime → Caused freezing
**After:** Loads a single pre-baked PNG → Instant loading, zero lag

## Screenshot Mode

Press **F12** during gameplay to toggle screenshot mode:
- **ON**: Hides player, enemies, UI, campfire (shows only static background + trees)
- **OFF**: Shows everything normally

## Troubleshooting

**Q: The baker freezes!**
A: This is **normal and expected** during baking. Let it run - it will finish eventually (may take 1-5 minutes). The console will show progress messages.

**Q: Game says "Pre-baked world texture not found!"**
A: You need to run Step 1 first to generate the texture.

**Q: I want to change the world appearance**
A: Modify `bake_world_offline.gd`, then run Step 1 again to regenerate the texture.

## Technical Details

- **World Size**: 12000x5000 pixels
- **World Bounds**: X: -3000 to 9000, Y: -2500 to 2500
- **Format**: PNG (lossless, supports transparency)
- **File Size**: ~8-15 MB (varies based on detail)
- **Load Time**: <100ms (instant)

Enjoy your lag-free game world!
