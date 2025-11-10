# 🗺️ EXPLORATION-FOCUSED WASTELAND LAYOUT

## 🎯 Design Philosophy

**"Oh there's a dead tree over there, let's check it out!"**

This layout encourages exploration by:
1. **Scattering props across the ENTIRE playable area** (not just a narrow path)
2. **Creating a cleared winding path** through the wasteland
3. **Adding dead-end forks** that reward curious players
4. **Placing "reward props"** at map edges to pull exploration

---

## 🗺️ The Cleared Path System

### Main Path (11 Waypoints):
A winding trail that loosely weaves through the center, connecting campfire to castle:

```
Campfire (-1500, 0)
    ↓
 (-1200, -100) ← curves south
    ↓
 (-900, 80)    ← curves north
    ↓
 (-600, -120)  ← curves south
    ↓
 (-300, 50)    ← curves north
    ↓
 (0, -80)      ← center, curves south
    ↓
 (300, 100)    ← curves north
    ↓
 (600, -50)    ← gentle curve
    ↓
 (900, 80)     ← curves north
    ↓
 (1200, -80)   ← curves south
    ↓
Castle (1500, 0)
```

**Path Width:** 120-150 pixel radius (cleared of props)

---

## 🔀 Dead-End Fork Paths

### Fork 1: North Exploration (Easy Zone)
```
Main path at (-800, 100)
    ↑
 (-700, 250)
    ↑
 (-600, 350) ← DEAD END
```
**Reward:** Less enemy density, safer exploration

### Fork 2: South Exploration (Medium Zone)
```
Main path at (0, -80)
    ↓
 (100, -250)
    ↓
 (200, -350) ← DEAD END
```
**Reward:** Could place special loot or hidden campfire

### Fork 3: North Exploration (Hard Zone)
```
Main path at (700, -50)
    ↑
 (800, 150)
    ↑
 (900, 280) ← DEAD END
```
**Reward:** High-risk exploration in dangerous zone

---

## 📐 Zone Coverage (FULL WIDTH & HEIGHT)

### Old System (Too Narrow):
- Zones: y range of -200 to 200 (only 400 pixels tall)
- Props clustered in narrow corridor
- No reason to explore edges

### New System (FULL EXPLORATION):

| Zone | X Range | Y Range | Coverage |
|------|---------|---------|----------|
| **Safe Zone** | -1600 to -1000 | **-400 to 400** | 800px tall! |
| **Easy Zone** | -1100 to -300 | **-500 to 500** | 1000px tall! |
| **Medium Zone** | -400 to 400 | **-500 to 500** | 1000px tall! |
| **Hard Zone** | 300 to 1200 | **-500 to 500** | 1000px tall! |
| **Boss Zone** | 1100 to 1650 | **-400 to 400** | 800px tall! |

**Result:** Props scattered across the ENTIRE screen, not just the middle!

---

## 🎁 Edge Rewards

Special props placed at map edges to encourage exploration:

### North Edge Rewards (y ≈ 470):
- 5 skull clusters at x: -1000, -400, 200, 800, 1300
- Scaled 1.3x (bigger and more visible)
- "Something special up here!"

### South Edge Rewards (y ≈ -470):
- 4 skull clusters at x: -800, -200, 400, 1000
- Scaled 1.3x
- "Let's check the southern edge!"

**Purpose:** Pull players to explore corners and edges

---

## 📊 Prop Distribution (312 Total Props!)

### By Zone:

| Zone | Props | Density | Distribution |
|------|-------|---------|--------------|
| **Safe Zone** | 15 | Light | Sparse feel, room to breathe |
| **Easy Zone** | 40 | Moderate | Scattered, inviting exploration |
| **Medium Zone** | 67 | Heavy | Dense but navigable |
| **Hard Zone** | 95 | Very Heavy | Threatening, but still explorable |
| **Boss Zone** | 86 | Extreme | Maximum density |
| **Edge Rewards** | 9 | Special | Lure for explorers |
| **TOTAL** | **312** | — | — |

---

## 🎮 Player Experience Flow

### Starting at Campfire (Safe Zone):
- Player sees cleared path ahead (obvious route)
- But also sees dead trees scattered in all directions
- "What's over there?" curiosity triggered

### Easy Zone Exploration:
- Main path is clear and safe
- Fork path branches north - "Should I explore?"
- Props scattered throughout - "Let's check the edges"
- Skulls visible at north edge - "Ooh, what's that?"

### Medium Zone Exploration:
- Path gets more winding
- Fork branches south - new direction to explore
- Denser props make exploration riskier but rewarding
- Dead trees create natural landmarks

### Hard Zone Exploration:
- Path curves dramatically
- North fork tempts brave players
- Very dense props = high risk, high reward feel
- "Can I make it to that skull pile?"

### Boss Zone Approach:
- Path narrows
- Props create natural arena boundaries
- No more forks - this is the final stretch
- Dense skulls warn "point of no return"

---

## 🎯 Enemy Spawn Placement Strategy

Enemies are placed along BOTH the main path AND fork paths:

### Main Path Encounters (9 spawns):
- Forces players to fight while traveling
- Natural progression difficulty

### Fork Path Encounters (6 spawns):
- Rewards exploration with combat
- Optional but rewarding

### Distribution:
```
Easy Zone:
- Main path: 3 spawns (-1000, -850, -650)
- Fork path: 2 spawns (-700, -500) [north fork]

Medium Zone:
- Main path: 3 spawns (-200, 50, 250)
- Fork path: 2 spawns (150, 350) [south fork]

Hard Zone:
- Main path: 3 spawns (550, 750, 950)
- Fork path: 2 spawns (850, 1150) [north fork]
```

---

## 🎨 Visual Language

### Cleared Path = Safety:
- Open space = player can see dangers
- Easier to dodge attacks
- Natural "suggested route"

### Dense Props = Danger:
- Harder to see enemies
- Obstacles block movement
- Risk vs reward for exploration

### Fork Paths = Choice:
- "Do I stay on safe path or explore?"
- Dead ends create tension
- Reward curiosity

### Edge Props = Lure:
- Visible from center path
- "What's over there?"
- Creates sense of world beyond the path

---

## 📏 Technical Implementation

### Prop Placement Algorithm:

```python
1. Define cleared path waypoints with radius
2. Define fork path waypoints
3. For each prop to place:
   a. Generate random position in zone
   b. Check if position is in ANY cleared area
   c. If YES: discard and try again
   d. If NO: place prop with random rotation/scale/flip
4. Place edge rewards at map boundaries
```

### Key Parameters:
- **Main path radius:** 120-150 pixels (wide enough to navigate)
- **Fork path radius:** 80-100 pixels (narrower, riskier)
- **Max placement attempts:** 50 per prop (ensures coverage)
- **Edge reward scale:** 1.3x (more visible)

---

## 🗺️ Map Mental Model

```
     NORTH EDGE (+500y)
         ↑
    [Edge Rewards]
         |
    Dense Props scattered across FULL HEIGHT
         |
    [Winding Cleared Path with Forks]
         |
    Dense Props scattered across FULL HEIGHT
         |
    [Edge Rewards]
         ↓
     SOUTH EDGE (-500y)

CAMPFIRE (-1500x) ←→ CASTLE (1500x)
```

---

## ✅ Success Criteria

### Player Should Feel:
- ✅ **Curiosity:** "What's over there?"
- ✅ **Choice:** "Which way should I go?"
- ✅ **Discovery:** "Cool, I found something!"
- ✅ **Risk/Reward:** "Is it safe to explore?"

### Visual Design Should:
- ✅ Props cover ENTIRE playable area
- ✅ Cleared path is obvious but not mandatory
- ✅ Dead-end forks create exploration incentive
- ✅ Edge rewards visible and tempting
- ✅ Density gradient still flows LEFT→RIGHT

---

## 🎮 Playtesting Goals

Watch for:
1. **Do players explore off the main path?**
2. **Do fork paths feel rewarding or frustrating?**
3. **Are edge rewards noticed and pursued?**
4. **Does the cleared path feel natural?**
5. **Is prop density still readable (not too cluttered)?**

---

## 🔧 Easy Adjustments

### If players never explore:
- Make fork paths wider (increase radius to 120)
- Add more edge rewards
- Place visible items/loot at dead ends

### If players get lost:
- Make main path wider (increase radius to 180)
- Add more visual distinction (torches along path?)
- Reduce prop density slightly

### If too cluttered:
- Reduce prop counts by 20% per zone
- Increase cleared path radius
- Remove some edge rewards

---

**Result: A wasteland that BEGS to be explored!** 🗺️💀🔥
