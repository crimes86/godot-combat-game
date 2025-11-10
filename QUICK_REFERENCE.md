# Quick Reference - Pioneer Edition Features

## 🎮 What's New

### Player Damage Display
```
Player takes hit → Red "-10" floats up
Player heals → Green "+5" floats up
```

### Campfire Mechanics
```
Campfire Warmth Radius: 150 units
┌─────────────────────────┐
│    Warm Orange Glow     │
│                         │
│       🔥 Campfire       │
│    Healing: 5 HP/0.5s   │
│                         │
│   Enemy Deterrent Zone  │
└─────────────────────────┘
```

### Enemy AI Behavior
```
Normal State: Patrol → Player Attacks → Combat

At Campfire Edge:
Combat → Approach Fire → Hesitate → Turn Back → Disengage
```

### Art Style Changes
```
OLD: Capsule shapes
    ⬭  (Simple geometric)
    
NEW: Stick figures  
    👤  (Pioneer aesthetic)
```

## 🎯 Testing Tips

1. **Test Damage Numbers**: 
   - Let enemy hit you - see red numbers
   - Walk to campfire - see green numbers

2. **Test Campfire Healing**:
   - Take damage from enemy
   - Walk into orange glow
   - Watch health bar increase
   - Green numbers appear every 0.5s

3. **Test Enemy Deterrent**:
   - Engage enemy in combat
   - Lead enemy toward campfire
   - Watch enemy approach warmth edge
   - Enemy should turn and retreat

4. **Test Art Style**:
   - Player: Brown stick figure with hat
   - Enemy: Red stick figure, aggressive pose
   - Campfire: Animated flames with logs

## 🔧 Controls (Unchanged)

- **WASD**: Move
- **Mouse**: Aim
- **Left Click**: Attack
- **F3**: Debug mode (toggle)
- **F4**: Add 1 level
- **F5**: Add 5 levels

## 📍 Campfire Location

The campfire is at position **(-200, 0)** - to the left of spawn.
Walk left from starting position to find it!

## ⚠️ Important Notes

- Healing only works INSIDE the orange glow
- Enemies won't cross into warmth during combat
- If enemy disengages, it returns to patrol
- Campfire provides strategic safe haven
