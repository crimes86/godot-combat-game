# 🗺️ WASTELAND PATH MAP (TOP-DOWN VIEW)

```
Legend:
🏕️  = Campfire (Safe Zone)
🏰 = Castle Door (Boss Zone)
═══ = Main cleared path
║   = Fork path (dead-end)
▓▓▓ = Dense props (obstacles)
💀 = Enemy spawn
💎 = Edge reward (special skull)

                    NORTH (+500y)
         💎         💎         💎         💎         💎
    ═════════════════════════════════════════════════════
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓                                                   ▓
    ▓   🏕️                                             ▓
    ▓    ╲                                             ▓
    ▓     ═══💀              ║                         ▓
    ▓         ╲              ║💀                       ▓
    ▓          ═══💀         ║ (Fork 1)                ▓
    ▓              ╲                                   ▓
    ▓               ═══💀                              ▓
    ▓                   ╲                              ▓
    ▓                    ═══💀                         ▓
    ▓                        ╲                         ▓
    ▓                         ═══💀                    ▓
    ▓                             ╲         ║          ▓
    ▓                              ═══💀    ║          ▓
    ▓                                  ╲    ║💀        ▓
CENTER ▓                                   ═══💀       ▓ CENTER
(0,0)  ▓                                       ╲       ▓ (0,0)
    ▓                                          ═══💀   ▓
    ▓                                 ║            ╲   ▓
    ▓                                 ║💀            ═══▓💀
    ▓                                 ║ (Fork 2)        ▓
    ▓                                                   ▓
    ▓                                         ║         ▓
    ▓                                         ║💀       ▓
    ▓                                         ║ (Fork 3)▓
    ▓                                                  🏰
    ▓                                                   ▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ═════════════════════════════════════════════════════
              💎         💎         💎         💎
                    SOUTH (-500y)

    WEST                                             EAST
   (-1600x)                                        (+1650x)
```

## Path Analysis:

### Main Path Journey:
1. **Start:** Campfire at (-1500, 0)
2. **Curve South:** First waypoint at (-1200, -100)
3. **Curve North:** Swing up to (-900, 80)
4. **Curve South:** Drop to (-600, -120)
5. **Curve North:** Rise to (-300, 50)
6. **Center:** Pass through (0, -80)
7. **Curve North:** Swing to (300, 100)
8. **Gentle Curve:** Level at (600, -50)
9. **Curve North:** Rise to (900, 80)
10. **Curve South:** Drop to (1200, -80)
11. **End:** Castle at (1500, 0)

### Fork Paths:

**Fork 1 (North - Easy Zone):**
- Branches from main path at (-800, 100)
- Extends north to (-700, 250)
- Dead ends at (-600, 350)
- Purpose: Safe exploration, lower enemy density

**Fork 2 (South - Medium Zone):**
- Branches from main path at (0, -80)
- Extends south to (100, -250)
- Dead ends at (200, -350)
- Purpose: Risky exploration, medium difficulty

**Fork 3 (North - Hard Zone):**
- Branches from main path at (700, -50)
- Extends north to (800, 150)
- Dead ends at (900, 280)
- Purpose: High-risk exploration, tough enemies

### Visual Flow:

```
                EXPLORATION ZONES

    [NORTH EDGE - Rewards for curious players]
              ↑
         [FULL HEIGHT]
         Dense props scattered everywhere
         Players can roam freely
              ↑
    [CLEARED WINDING PATH - Suggested route]
         Main path with S-curve
         3 fork paths branch off
              ↑
         [FULL HEIGHT]
         Dense props scattered everywhere
         Risk/reward exploration
              ↓
    [SOUTH EDGE - Rewards for brave players]
```

## Player Movement Patterns:

### Cautious Player:
```
Campfire → Stay on main path → Castle
- Follows cleared path
- Fights enemies along route
- Fast but misses exploration
```

### Curious Player:
```
Campfire → Main path → Fork 1 (north) → Back to main → Continue
- Explores dead ends
- Finds edge rewards
- More fights but more discovery
```

### Completionist Player:
```
Campfire → Explore ALL edges → All forks → Castle
- Visits north and south extremes
- Clears every prop area
- Maximum exploration
```

### Speedrunner:
```
Campfire → Diagonal to Castle (ignore path)
- Cuts through dense props
- High risk, fast route
- Dodges most enemies
```

---

## Enemy Encounter Design:

### Path Encounters (9 spawns):
- Placed along main cleared path
- Unavoidable for path-followers
- Progressive difficulty LEFT→RIGHT

### Fork Encounters (6 spawns):
- Placed in fork paths
- Reward exploration with XP
- Optional but valuable

### Roaming Encounters:
- Can spawn anywhere in prop areas
- Surprise attacks off-path
- Punish careless exploration

---

## Design Intent:

### The Path Says:
"This way is safe... ish. Stick to me and you'll reach the castle."

### The Props Say:
"But what's hidden in all these obstacles? Maybe something worth finding?"

### The Forks Say:
"I'm a detour, but I might be worth it. Do you dare?"

### The Edge Rewards Say:
"Look how far I am from the path! Only the bravest find me!"

---

**Result: A wasteland that rewards both caution AND curiosity!** 🗺️✨
