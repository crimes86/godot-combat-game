# Rhythm RPG - Pioneer Edition Update

## 🎮 New Features for Playtest

### 1. Player Damage Numbers ✅
- **Red numbers** now appear when the player takes damage
- **Green numbers** appear when the player heals
- Damage numbers float upward with distinctive animations
- Helps track combat feedback and health changes

### 2. Campfire Healing System 🔥
- **Campfire** placed at position (-200, 0) near spawn
- **Warmth Radius**: 150 units - provides healing aura
- **Healing Rate**: 5 HP every 0.5 seconds while in warmth
- **Visual Indicators**: 
  - Animated flickering flames (stick-style art)
  - Warm glow circle shows healing radius
  - Logs arranged in campfire pattern

### 3. Enemy Deterrent System 🛡️
- Enemies approaching the campfire will **hesitate at the edge**
- They contemplate crossing but turn back due to warmth
- Provides strategic safe zone for player
- Enemies in combat near fire will slowly retreat
- 5% chance per frame at edge to fully disengage and return to patrol

### 4. Pioneer/Revenant Art Style 🎨
**Player Character:**
- Stick figure design with pioneer aesthetic
- Dark brown leather/worn clothing
- Simple frontier hat
- Earthy, rugged color palette
- Weapon indicator (stick/club)

**Enemy Characters:**
- Hostile stick figures with aggressive pose
- Dark red/crimson color scheme
- Wide threatening stance
- Armed with spears/clubs
- Angry eyes (X-shaped)
- Larger and more menacing than player

**Campfire:**
- Simple stick-log arrangement
- Animated flame triangles (flickering)
- Warm orange glow effect
- Minimalist wilderness aesthetic

## 🎯 Playtest Focus Areas

1. **Damage Feedback**: Check if red/green numbers are clear and helpful
2. **Healing Balance**: Test if campfire healing rate feels right
3. **Enemy Behavior**: Watch enemies approach campfire and retreat
4. **Art Style**: Get feedback on stick figure aesthetic and pioneer theme
5. **Strategic Gameplay**: Does campfire create interesting tactical decisions?

## 🐛 Known Behaviors

- Enemies will path around campfire rather than through it
- Player can "kite" enemies to campfire for safety
- Healing only occurs when player is inside warmth radius
- Enemies already in combat near fire will gradually disengage

## 🔧 Technical Details

**New Files Created:**
- `/scripts/systems/Campfire.gd` - Main campfire logic
- `/scenes/world/campfire.tscn` - Campfire scene
- `/scripts/ui/CombatText.gd` - Updated with DAMAGE and HEAL types

**Modified Files:**
- `/scripts/player/Player.gd` - Added heal() method, damage numbers, stick figure art
- `/scripts/enemies/Enemy.gd` - Updated to stick figure art
- `/main.tscn` - Added campfire instance

## 🎨 Art Direction Notes

The stick figure style with pioneer theme captures:
- Early survival gameplay feel
- "The Revenant" movie atmosphere
- Hostile wilderness setting
- Minimal but expressive characters
- Easy to iterate and expand

Future art could add:
- Weather effects (snow, rain)
- More environmental hazards
- Different enemy types (wildlife, etc.)
- Pioneer equipment and tools
- Settlement structures

## 🚀 Next Steps

Based on playtest feedback, consider:
1. Multiple campfire locations
2. Campfire fuel/duration mechanics
3. Enemies that can extinguish fires
4. Upgraded campfire tiers
5. More pioneer-themed items/weapons
