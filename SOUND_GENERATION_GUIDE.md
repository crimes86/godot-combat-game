# Combat Sound Generation Guide

This document lists all sounds needed for the combat system with AI-optimized prompts.

## Recommended AI Tools
1. **ElevenLabs Sound Effects** - https://elevenlabs.io/sound-effects (Best quality)
2. **Suno Bark** - https://github.com/suno-ai/bark (Open source)
3. **Audiobox by Meta** - https://audiobox.metademolab.com/ (Free)

---

## Priority 1: Core Combat Sounds (NEEDED NOW)

### Weakpoint Hit Sounds ⭐ HIGHEST PRIORITY
**File naming:** `weakpoint_hit_1.wav`, `weakpoint_hit_2.wav`

**Prompt 1:**
```
A satisfying bone shattering impact sound, crisp and crunchy like breaking thick ice or ceramic,
short duration (0.3 seconds), high pitched crack followed by lower frequency crumbling,
medieval fantasy combat, 8-bit retro gaming style but modern quality
```

**Prompt 2:**
```
Critical hit bone breaking sound effect, sharp snap like breaking a large stick combined with
glass shattering, satisfying and impactful, short and punchy (0.2 seconds),
retro game style critical hit sound
```

**Usage:** Play when player successfully hits a weakpoint during crit window

---

### Regular Hit Sounds (Player Weapon → Enemy)
**File naming:** `hit_skeleton_1.wav`, `hit_skeleton_2.wav`, `hit_skeleton_3.wav`

**Prompt 1:**
```
Metal sword hitting dry bone sound, dull thunk with slight rattle,
short and snappy (0.2 seconds), medieval combat,
like hitting a wooden stick with a metal bat
```

**Prompt 2:**
```
Mace or hammer hitting skeletal bone, heavy dull impact with bone crack,
deeper tone than sword hit, short duration (0.25 seconds),
chunky and satisfying medieval weapon impact
```

**Prompt 3:**
```
Blade striking bone with a sharp clack sound, clean impact,
mix of metal ping and wood knock, quick and tight (0.15 seconds),
retro RPG combat sound
```

**Usage:** Play randomly when player's weapon connects with enemy

---

### Skeleton Hit Reaction Sounds
**File naming:** `skeleton_hurt_1.wav`, `skeleton_hurt_2.wav`

**Prompt 1:**
```
Skeleton taking damage sound, bones rattling and clacking together,
brief shake like bag of wooden dice, dry and hollow (0.3 seconds),
cartoonish skeleton hurt sound
```

**Prompt 2:**
```
Bone impact reaction, quick rattle with slight crack,
like bamboo sticks knocked together, hollow and percussive (0.2 seconds),
skeleton enemy damage sound effect
```

**Usage:** Play when skeleton enemy takes damage

---

### Skeleton Death Sound
**File naming:** `skeleton_death_1.wav`, `skeleton_death_2.wav`

**Prompt 1:**
```
Skeleton collapsing and falling apart, cascade of bones clattering on stone floor,
multiple bone pieces falling in sequence, descending pitch (0.6 seconds),
satisfying enemy defeat sound, medieval dungeon
```

**Prompt 2:**
```
Undead skeleton destruction, bones breaking and scattering,
like wooden xylophone bars falling down stairs, hollow percussion (0.5 seconds),
fantasy RPG enemy death
```

**Usage:** Play when skeleton enemy dies

---

## Priority 2: Enhanced Combat Feedback

### Critical Hit Sound (Non-weakpoint)
**File naming:** `critical_hit.wav`

**Prompt:**
```
Powerful critical hit impact, deep bass thump with sharp high-frequency crack overlay,
satisfying punch sound with slight reverb (0.4 seconds),
video game critical damage sound effect
```

**Usage:** Play on random critical hits from normal attacks

---

### Miss/Whiff Sound
**File naming:** `attack_miss_1.wav`, `attack_miss_2.wav`

**Prompt 1:**
```
Sword swing missing target, quick whoosh of air with no impact,
slight downward pitch bend, short (0.15 seconds),
game combat miss sound
```

**Prompt 2:**
```
Weapon whiff sound, swoosh of air without connection,
quick whooshing sound fading out, disappointed feeling (0.2 seconds),
video game attack miss
```

**Usage:** Play when player attacks but hits no enemies

---

## Priority 3: UI/System Sounds

### Chain System Sounds
**File naming:** `chain_increase.wav`, `chain_break.wav`, `overdrive_activate.wav`

**Chain Increase Prompt:**
```
Chain combo counter increasing, light metallic clink with subtle ascending chime,
positive and encouraging (0.2 seconds), game UI combo sound
```

**Chain Break Prompt:**
```
Combo chain breaking, descending tone like glass crack or chain snap,
disappointing but not harsh (0.3 seconds), game UI failure sound
```

**Overdrive Activate Prompt:**
```
Power-up activation sound, ascending electronic chime into bright burst,
triumphant and energetic (0.5 seconds), game special mode activation
```

---

## Priority 4: Optional Polish Sounds

### Weapon Swing Variations
**File naming:** `swing_1.wav`, `swing_2.wav`, `swing_3.wav`

**Note:** Already have swing sound, but variations prevent repetition

**Prompt:**
```
Sword or weapon swinging through air, quick whoosh,
sharp and clean (0.2 seconds), different pitch from existing swing sound,
medieval weapon slash sound effect
```

---

## Technical Specifications

### Required Format:
- **Format:** `.wav` (uncompressed)
- **Sample Rate:** 44100 Hz
- **Bit Depth:** 16-bit
- **Channels:** Mono (preferred) or Stereo
- **Duration:** As specified per sound (0.2-0.6 seconds)
- **Volume:** Normalized to -3dB to -6dB (leave headroom)

### File Organization:
```
assets/sounds/combat/
├── hits/
│   ├── hit_skeleton_1.wav
│   ├── hit_skeleton_2.wav
│   ├── hit_skeleton_3.wav
│   ├── weakpoint_hit_1.wav
│   └── weakpoint_hit_2.wav
├── reactions/
│   ├── skeleton_hurt_1.wav
│   ├── skeleton_hurt_2.wav
│   ├── skeleton_death_1.wav
│   └── skeleton_death_2.wav
├── player/
│   ├── attack_miss_1.wav
│   ├── critical_hit.wav
│   └── swing_1-3.wav (optional)
└── ui/
    ├── chain_increase.wav
    ├── chain_break.wav
    └── overdrive_activate.wav
```

---

## Generation Tips

1. **Keep sounds short** - Combat sounds should be punchy (0.2-0.5s)
2. **Leave headroom** - Don't generate at max volume, normalize to -6dB
3. **Generate multiple takes** - Pick the best of 3-5 variations
4. **Test in-game** - Some sounds that work in isolation don't work in gameplay
5. **Avoid reverb** - Dry sounds are better (add reverb in-engine if needed)

---

## Implementation Checklist

Once sounds are generated:
- [ ] Add files to `assets/sounds/combat/` directory
- [ ] Update SoundManager.gd with new sound types
- [ ] Hook up weakpoint hit sounds to Enemy.gd
- [ ] Hook up regular hit sounds to Player.gd attack functions
- [ ] Hook up skeleton hurt/death sounds to Enemy.gd
- [ ] Add sound randomization (pick random variant each play)
- [ ] Test volume balance in combat
- [ ] Add slight pitch randomization (±10%) for variety

---

## Quick Start (Minimum Viable)

If you want to start with just the essentials:
1. Generate: `weakpoint_hit_1.wav` and `weakpoint_hit_2.wav`
2. Generate: `hit_skeleton_1.wav`
3. Generate: `skeleton_hurt_1.wav`
4. Generate: `skeleton_death_1.wav`

These 5 sounds will make combat feel 10x better immediately.
