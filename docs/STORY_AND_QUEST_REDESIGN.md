# Story, Quest Progression, and NPC Redesign

> **Status**: Design Proposal
> **Version**: 1.0
> **Created**: December 2024

---

## Executive Summary

### Current Problems

1. **Quests are WAY too rewarding**: 10,600 XP from quests vs 1,675 XP needed to reach L10 (6.3x surplus)
2. **No story/narrative**: Quests are pure mechanical objectives with no character or world-building
3. **Single NPC bottleneck**: Blacksmith does everything (quests, shop, forge) at one location
4. **Blacksmith placement conflict**: He should be at the Forge in Zone 2, not the campfire
5. **No clear "why"**: Players have no compelling reason to progress beyond "get stronger"

### Proposed Solution

1. **New NPC at campfire**: A Wanderer/Survivor who guides early game and has personal stake in the story
2. **Move Blacksmith to Forge**: He becomes the Zone 2 NPC at the Trading Hub forge
3. **Rebalance XP**: Quests provide ~25-30% of leveling XP, grinding is primary source
4. **Add narrative arc**: "The Lich threat is rising, prepare for what's coming"
5. **Questline teaches mechanics**: Each quest introduces a game system organically
6. **Delayed handoff**: Player meets Blacksmith at level 7-8 (after naturally reaching north zone)

---

## Part 1: The Story Framework

### The World Setup

**The Wasteland** was once a prosperous region until the Lich Lord Malachar rose to power. His undead armies swept across the land, leaving only ruins and bone. Now, survivors gather at campfires - small pockets of warmth and light in an endless sea of death.

**The Trading Hub** is an underground refuge - a network of tunnels where traders and warriors gather. The Blacksmith there forges weapons from salvaged materials, preparing fighters for the battles ahead.

**The Cursed Lands** (Zone 2) lie beyond, where Malachar's influence grows stronger. Those who venture there seek to push back the darkness - or find power in it.

### The Player's Journey (Thematic Arc)

| Level | Theme | Player State |
|-------|-------|--------------|
| 1-3 | **Survival** | Lost, weak, learning to stay alive |
| 4-6 | **Growth** | Finding purpose, becoming a threat to the undead |
| 7-8 | **Discovery** | Finding the Trading Hub, meeting the Blacksmith |
| 9-10 | **Preparation** | Building strength for what lies ahead |

### Core Narrative Hooks

1. **The campfire is fading** - Bone Embers keep it burning, but supplies run low
2. **The Wanderer knows something** - He's seen what's coming, hints at larger threat
3. **The Blacksmith needs materials** - To forge weapons that can hurt the Lich's elite
4. **The ruins hold secrets** - Ancient knowledge about defeating the undead

---

## Part 2: NPC Redesign

### New NPC: The Wanderer (Zone 1 - Campfire)

**Name**: Elric the Wanderer (or simply "The Wanderer")

**Role**: Early-mid game quest giver (L1-7), lore source, survival mentor

**Visual**: Weathered traveler with a hooded cloak, visible scars, carries a worn journal

**Personality**:
- Cryptic but not annoyingly so
- Speaks from experience ("I've seen what happens when the fire goes out...")
- Occasionally hints at his past ("I was like you once, full of fight...")
- Grows more urgent as player levels up

**Location**: By the campfire at spawn (Vector2(4000, 0))

**Shop Inventory** (minimal, survival-focused):
- Health Potions (basic)
- Torches
- Basic gathering tools

**Dialog Style**:
```
[First meeting]
"Another survivor. Good. The fire needs tending and there's
too much work for one old wanderer. Take this advice freely:
the undead fear the flame. Keep it burning."

[After First Blood quest]
"You handle yourself well. The skeletons are only the beginning.
I've walked these wastes for years... there are things out there
that make them look like practice dummies."

[At level 5]
"You're getting stronger. Push north when you're ready.
The wasteland gets more dangerous, but also more rewarding.
Ancient ruins lie in that direction... and something else."

[At level 7 - tunnel discovery]
"You found it. The tunnel to the Trading Hub. I knew you would.
There's a blacksmith there - Garrett. Old friend of mine.
Take this letter to him. He'll know what to do with you."
```

**Quest Indicator**: Same as current (! for available, ? for turn-in)

### Relocated NPC: The Blacksmith (Zone 2 - Trading Hub Forge)

**Name**: Garrett Ironforge (or keep "Blacksmith" as title)

**Role**: Late-game quest giver (L8-10), forge master, advanced equipment vendor

**Visual**: Keep current LPC blacksmith sprite, add forge hammer in idle animation

**Personality**:
- Gruff, practical, focused on work
- Respects strength and determination
- Knows metallurgy and ancient forging secrets
- Has connection to the Wanderer (old acquaintances)

**Location**: At the Forge in Trading Hub

**Shop Inventory** (upgraded from current):
- Zone 2 preparation items
- Advanced weapons
- Armor upgrades
- Forge materials

**Dialog Style**:
```
[First meeting - player arrives with Elric's letter]
"This seal... Elric? That old survivor is still kicking?
Thought the wasteland would've claimed him by now.

So you're the one he's been training. Let's see what
you're made of. The Cursed Lands don't suffer the weak."

[Forge introduction]
"See that forge? Ancient. Built before the Lich rose.
Some say the weapons made here can hurt even his
lieutenants. Bring me the right materials and I'll
prove it."

[At level 10]
"You've done well. Better than most. The Cursed Lands
await through the north passage. Whatever you find
there... don't let it change you."
```

### NPC Relationship Web

```
    THE WANDERER (Zone 1)                    THE BLACKSMITH (Zone 2)
    Levels 1-7 Quests                        Levels 8-10 Quests
    ├── Knows the wasteland                  ├── Knows crafting/forging
    ├── Survived the Lich's rise             ├── Supplied the old resistance
    ├── Guides new survivors                 ├── Equips warriors for battle
    │                                        │
    └─────────── OLD ACQUAINTANCES ──────────┘
                       │
                       ▼
              [Shared history]
         Both fought in the original
         war against Malachar. Both
         lost. Both are preparing for
         another chance.
```

---

## Part 3: Quest Redesign

### XP Rebalancing Goals

**Target Distribution**:
- **Grinding XP**: 70-75% of total leveling XP
- **Quest XP**: 25-30% of total leveling XP (bonus, not primary)

**Current Problem**:
- XP to L10: 1,675
- Current quest XP: 10,600 (6.3x too much!)

### Recommended: Adjusted Leveling Curve

| Level | Current XP Req | New XP Req | Cumulative |
|-------|----------------|------------|------------|
| 2 | 100 | 200 | 200 |
| 3 | 114 | 280 | 480 |
| 4 | 132 | 380 | 860 |
| 5 | 152 | 500 | 1,360 |
| 6 | 174 | 650 | 2,010 |
| 7 | 201 | 850 | 2,860 |
| 8 | 231 | 1,100 | 3,960 |
| 9 | 266 | 1,400 | 5,360 |
| 10 | 305 | 1,800 | 7,160 |
| **Total** | **1,675** | **7,160** | - |

With 7,160 XP to reach L10:
- Quest total: ~2,000 XP (~28% of leveling)
- Grinding: ~5,160 XP (~72% of leveling)
- Estimated time: 2-3 hours to L10 (good session length)

---

### New Quest Structure

#### The Wanderer's Quests (Zone 1, Levels 1-7)

**TIER 1: Survival Basics (Levels 1-2)**

| Quest ID | Name | Objectives | XP | Gold | Prereq |
|----------|------|------------|----|----|--------|
| survival_101 | Survival 101 | Kill 5 skeletons | 50 | 15 | None |
| kindle_the_flame | Kindle the Flame | Collect 5 Bone Embers | 50 | 15 | None |
| warmth_of_hope | Warmth of Hope | Add fuel to campfire 5x | 75 | 20 | kindle_the_flame |

**TIER 2: Growing Stronger (Levels 3-4)**

| Quest ID | Name | Objectives | XP | Gold | Prereq |
|----------|------|------------|----|----|--------|
| proving_ground | Proving Ground | Kill 15 skeletons | 100 | 30 | survival_101 |
| the_pack_hunts | The Pack Hunts | Kill 5 wolves | 100 | 30 | survival_101 |
| scavengers_fortune | Scavenger's Fortune | Collect 15 Bone Embers | 100 | 25 | kindle_the_flame |

**TIER 3: Venturing North (Levels 4-5)**

| Quest ID | Name | Objectives | XP | Gold | Prereq |
|----------|------|------------|----|----|--------|
| fire_and_ash | Fire and Ash | Discover a lava pool | 125 | 40 | proving_ground |
| veteran_hunter | Veteran Hunter | Kill 10 level 5+ skeletons | 150 | 50 | proving_ground |

**TIER 4: The Ruins (Levels 5-6)**

| Quest ID | Name | Objectives | XP | Gold | Prereq |
|----------|------|------------|----|----|--------|
| rumors_of_ruins | Rumors of Ruins | Discover the ancient ruins | 150 | 50 | fire_and_ash |
| guardian_encounter | Guardian Encounter | Kill 3 guardian skeletons | 175 | 60 | rumors_of_ruins |

**TIER 5: The Handoff (Level 7)**

| Quest ID | Name | Objectives | XP | Gold | Prereq |
|----------|------|------------|----|----|--------|
| seek_the_hub | Seek the Trading Hub | Find the tunnel entrance | 175 | 60 | veteran_hunter |
| elrics_letter | Elric's Letter | Speak to the Blacksmith | 0 | 100 | seek_the_hub |

**Wanderer Quest Totals**: 1,250 XP, 495 gold

---

#### The Blacksmith's Quests (Trading Hub, Levels 8-10)

**TIER 6: Proving Your Worth (Level 8)**

| Quest ID | Name | Objectives | XP | Gold | Prereq |
|----------|------|------------|----|----|--------|
| forge_materials | Forge Materials | Collect 5 Iron Ore | 125 | 50 | elrics_letter |
| reclaim_the_ruins | Reclaim the Ruins | Convert ruins to campfire | 175 | 75 | elrics_letter |

**TIER 7: The Lich's Shadow (Levels 9-10)**

| Quest ID | Name | Objectives | XP | Gold | Prereq |
|----------|------|------------|----|----|--------|
| guardians_bane | Guardian's Bane | Kill 10 guardian skeletons | 200 | 100 | forge_materials |
| ancient_secret | Ancient Secret | Collect Lich's Finger Bone | 250 | 150 | guardians_bane |

**TIER 8: Zone 2 Transition (Level 10)**

| Quest ID | Name | Objectives | XP | Gold | Prereq |
|----------|------|------------|----|----|--------|
| into_darkness | Into the Darkness | Enter the Cursed Lands | 0 | 200 | ancient_secret |

**Blacksmith Quest Totals**: 750 XP, 575 gold

---

### Complete Quest Flow Diagram

```
                    THE WANDERER (Zone 1, L1-7)
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               │
    [Survival 101]   [Kindle the          │
     Kill 5 skel      Flame]              │
     L1, 50 XP        L1, 50 XP           │
           │               │               │
           │               ▼               │
           │        [Warmth of Hope]       │
           │         Fuel fire 5x          │
           │         L2, 75 XP             │
           │               │               │
           ▼               ▼               │
    [Proving Ground] [Scavenger's         │
     Kill 15 skel     Fortune]            │
     L3, 100 XP       L3, 100 XP          │
           │                               │
           ├───────────────┐               │
           │               │               │
           ▼               ▼               │
    [The Pack Hunts] [Fire and Ash]       │
     Kill 5 wolves    Find lava           │
     L3, 100 XP       L4, 125 XP          │
           │               │               │
           │               ▼               │
           │        [Rumors of Ruins]      │
           │         Find ruins            │
           │         L5, 150 XP            │
           │               │               │
           ▼               ▼               │
    [Veteran Hunter] [Guardian Encounter]  │
     10 L5+ skel      Kill 3 guardians    │
     L5, 150 XP       L6, 175 XP          │
           │               │               │
           └───────┬───────┘               │
                   │                       │
                   ▼                       │
           [Seek the Trading Hub]          │
            Find tunnel entrance           │
            L7, 175 XP                     │
                   │                       │
                   ▼                       │
            [Elric's Letter]               │
             Speak to Blacksmith           │
             L7, 0 XP + 100g ◄─────────────┘
                   │
    ═══════════════╧═══════════════════════════
                   │
                   ▼
            THE BLACKSMITH (Trading Hub, L8-10)
                   │
           ┌───────┴───────┐
           │               │
           ▼               ▼
    [Forge Materials] [Reclaim the Ruins]
     5 Iron Ore        Convert ruins
     L8, 125 XP        L8, 175 XP
           │               │
           └───────┬───────┘
                   │
                   ▼
          [Guardian's Bane]
           Kill 10 guardians
           L9, 200 XP
                   │
                   ▼
          [Ancient Secret]
           Lich's Finger Bone
           L9, 250 XP
                   │
                   ▼
          [Into the Darkness]
           Enter Zone 2
           L10, 0 XP + 200g
```

---

### New Quest XP Totals

| Source | XP | % of L10 XP (7,160) |
|--------|----|--------------------|
| Wanderer Quests (L1-7) | 1,250 | 17.5% |
| Blacksmith Quests (L8-10) | 750 | 10.5% |
| **Total Quest XP** | **2,000** | **28%** |
| Grinding Required | 5,160 | 72% |

This achieves our goal: quests are a nice supplement (~28%) but grinding is the primary progression path (~72%).

---

## Part 4: Quest Narrative & Dialog

### Wanderer Quest Dialog

#### Survival 101
```
[Accept]
"The wasteland teaches harsh lessons. The undead don't
rest, don't tire, don't stop. But they can be put down -
if you know how to fight.

Show me you can handle yourself. Put five of those
bone-walkers back in the ground."

[Turn-in]
"Good. You're still breathing. That's more than most
manage on their first day. The skeletons are endless,
but every one you destroy is one less threat to the
living."
```

#### Kindle the Flame
```
[Accept]
"See that fire? It's the only thing keeping the darkness
at bay. Without it, we're all dead by morning.

The skeletons carry Bone Embers - fragments of whatever
cursed energy animates them. Turns out, that energy burns
well. Collect some. Keep the fire fed."

[Turn-in]
"These will burn bright. Every ember you bring back
extends our lives another night. Don't forget - the
fire is life out here."
```

#### The Pack Hunts
```
[Accept]
"The wolves have returned. Not natural wolves - the
Lich's curse touched them too. They hunt in packs now,
fearless and hungry.

Cull their numbers before they grow bold enough to
strike the camp."

[Turn-in]
"The pack is weakened. They'll think twice before
approaching the fire's light. For now."
```

#### Seek the Trading Hub
```
[Accept]
"You've pushed far into the wasteland. Survived things
that would've killed most. You're ready to know.

There's a tunnel at the northern edge - hidden in the
fog. It leads to the Trading Hub. Survivors gather
there. A blacksmith forges weapons that can hurt things
stronger than these bone-walkers.

Find that tunnel."

[Turn-in]
"You found it. I knew you would. Now take this letter
to Garrett - the blacksmith. Tell him Elric is still
alive, still fighting. He'll know what to do with you."
```

---

### Blacksmith Quest Dialog

#### First Meeting (Elric's Letter turn-in)
```
"This seal... Elric? That stubborn old wanderer is
still breathing?

*reads letter*

He says you've got potential. Says you survived the
wasteland longer than most. That you're ready for
what comes next.

We'll see about that. The Cursed Lands don't care
about potential - only results. Prove yourself to me,
and I'll forge you weapons that can hurt even the
Lich's lieutenants."
```

#### Guardian's Bane
```
[Accept]
"You've bloodied the guardians. Good. But three kills
doesn't make you a threat. Ten does.

The guardians at the ruins are the Lich's elite. Break
their defense. Make them fear YOU for once."

[Turn-in]
"Ten guardians. You're not just surviving anymore -
you're hunting. The Lich will notice you now. That's
either very good or very bad."
```

#### Ancient Secret
```
[Accept]
"There's one artifact that might tell us what the Lich
is planning. His Finger Bone - a relic from when he
was still human. Still mortal.

The guardians protect it. They've protected it for
centuries. Take it from them."

[Turn-in]
"You actually found it. The Lich's own bone...

*examines it*

Dark magic. Old magic. This thing pulses with power.
Whatever he's building in the Cursed Lands, this
bone is connected to it.

You're ready. The Cursed Lands await through the
north passage. Don't let what you find there break you."
```

---

## Part 5: What Players Do (Activity Variety)

### Zone 1 Activities Summary

| Activity | Level Range | Teaching Purpose |
|----------|-------------|-----------------|
| **Kill skeletons** | 1-10 | Core combat, weakpoints |
| **Kill wolves** | 3-6 | Pack behavior, different patterns |
| **Kill guardians** | 6-10 | Elite enemies, tougher fights |
| **Gather Bone Embers** | 1-4 | Loot basics, inventory |
| **Fuel campfire** | 2-4 | Community mechanic |
| **Explore lava pools** | 4-5 | Environmental hazards |
| **Explore ruins** | 5-6 | POI discovery |
| **Find tunnel** | 7 | Zone transition |
| **Gather Iron Ore** | 8 | Advanced materials |
| **Convert ruins** | 8 | Territory expansion |
| **Find Lich's Bone** | 9 | Rare drops, boss prep |

### Progression Feel by Level Range

**Levels 1-3: "I'm just trying to survive"**
- Stick close to campfire
- Fight weak skeletons
- Gather embers to help the group
- Learn basic combat mechanics

**Levels 4-6: "I'm getting stronger"**
- Venture further from camp
- Hunt wolves and tougher skeletons
- Discover lava pools (environmental danger)
- Find the ancient ruins
- First guardian encounters

**Levels 7-8: "I'm part of something bigger"**
- Discover the Trading Hub
- Meet the Blacksmith
- Learn about the larger threat
- Take on harder challenges for better gear

**Levels 9-10: "I'm ready for what's next"**
- Master guardian combat
- Complete the final preparations
- Uncover the Lich's secrets
- Enter the Cursed Lands

---

## Part 6: Implementation Plan

### Phase 1: NPC Split (Priority: High)

1. **Create Wanderer NPC**
   - New script: `scripts/npcs/Wanderer.gd` (based on Vendor.gd)
   - New scene: `scenes/npcs/wanderer.tscn`
   - New sprite: hooded traveler (can use LPC assets)
   - Position at campfire (Vector2(4000, 0) area)
   - Assign Tier 1-5 quests (giver: "wanderer")

2. **Update Blacksmith**
   - Remove from Zone 1 campfire
   - Place in Trading Hub at forge position
   - Assign Tier 6-8 quests (giver: "blacksmith")
   - Keep existing shop functionality

3. **Update Quest Data**
   - Rewrite `data/quests.json` with new quest structure
   - Update `giver` field for each quest
   - Add dialog fields for narrative

### Phase 2: Quest System Updates (Priority: High)

1. **QuestManager Updates**
   - Support multiple quest givers
   - Add `speak_to_npc` objective type
   - Add `enter_zone` objective type
   - Filter quests by giver in `get_available_quests()`

2. **XP Curve Adjustment**
   - Update `constants.gd` with new leveling formula
   - `BASE_XP_REQUIREMENT = 200`
   - `XP_SCALING_FACTOR = 1.25`

3. **New Objective Tracking**
   - Track NPC interactions for handoff quests
   - Track zone transitions for capstone quest

### Phase 3: UI Updates (Priority: Medium)

1. **Wanderer Shop UI**
   - Simpler shop (just survival items)
   - Quest tab with Wanderer's quests only

2. **Blacksmith Shop UI**
   - Full shop (weapons, armor, forge)
   - Quest tab with Blacksmith's quests only

3. **Quest Tracker**
   - Show quest giver name in tracker
   - Different colors for different givers (optional)

### Phase 4: Polish (Priority: Low)

1. **NPC Visuals**
   - Wanderer sprite and animations
   - Wanderer idle behavior (tends fire, writes in journal)

2. **Dialog System**
   - Display accept/turn-in dialog
   - Level-based ambient dialog

---

## Part 7: New quests.json

```json
{
  "quests": [
    {
      "id": "survival_101",
      "name": "Survival 101",
      "description": "The wasteland teaches harsh lessons. Show the Wanderer you can handle yourself.",
      "tier": 1,
      "level_req": 1,
      "giver": "wanderer",
      "objectives": [
        {"type": "kill", "target": "skeleton", "count": 5, "desc": "Kill skeletons"}
      ],
      "xp_reward": 50,
      "gold_reward": 15,
      "prereq": null
    },
    {
      "id": "kindle_the_flame",
      "name": "Kindle the Flame",
      "description": "The campfire needs fuel. Collect Bone Embers from skeleton corpses.",
      "tier": 1,
      "level_req": 1,
      "giver": "wanderer",
      "objectives": [
        {"type": "collect", "target": "Bone Ember", "count": 5, "desc": "Collect Bone Embers"}
      ],
      "xp_reward": 50,
      "gold_reward": 15,
      "prereq": null
    },
    {
      "id": "warmth_of_hope",
      "name": "Warmth of Hope",
      "description": "Keep the campfire burning strong. Add fuel to stoke the flames.",
      "tier": 1,
      "level_req": 2,
      "giver": "wanderer",
      "objectives": [
        {"type": "fuel_campfire", "target": "", "count": 5, "desc": "Add fuel to campfire"}
      ],
      "xp_reward": 75,
      "gold_reward": 20,
      "prereq": "kindle_the_flame"
    },
    {
      "id": "proving_ground",
      "name": "Proving Ground",
      "description": "The undead hordes are endless. Prove your worth by destroying more.",
      "tier": 2,
      "level_req": 3,
      "giver": "wanderer",
      "objectives": [
        {"type": "kill", "target": "skeleton", "count": 15, "desc": "Kill skeletons"}
      ],
      "xp_reward": 100,
      "gold_reward": 30,
      "prereq": "survival_101"
    },
    {
      "id": "the_pack_hunts",
      "name": "The Pack Hunts",
      "description": "Cursed wolves hunt in packs. Cull their numbers before they strike the camp.",
      "tier": 2,
      "level_req": 3,
      "giver": "wanderer",
      "objectives": [
        {"type": "kill", "target": "wolf", "count": 5, "desc": "Kill wolves"}
      ],
      "xp_reward": 100,
      "gold_reward": 30,
      "prereq": "survival_101"
    },
    {
      "id": "scavengers_fortune",
      "name": "Scavenger's Fortune",
      "description": "A true survivor never passes up useful materials. Stockpile Bone Embers.",
      "tier": 2,
      "level_req": 3,
      "giver": "wanderer",
      "objectives": [
        {"type": "collect", "target": "Bone Ember", "count": 15, "desc": "Collect Bone Embers"}
      ],
      "xp_reward": 100,
      "gold_reward": 25,
      "prereq": "kindle_the_flame"
    },
    {
      "id": "fire_and_ash",
      "name": "Fire and Ash",
      "description": "Venture beyond the campfire. Seek out the lava pools that dot the wasteland.",
      "tier": 3,
      "level_req": 4,
      "giver": "wanderer",
      "objectives": [
        {"type": "explore", "target": "lava_pool", "count": 1, "desc": "Discover a lava pool"}
      ],
      "xp_reward": 125,
      "gold_reward": 40,
      "prereq": "proving_ground"
    },
    {
      "id": "veteran_hunter",
      "name": "Veteran Hunter",
      "description": "The skeletons grow stronger further from camp. Hunt the veterans.",
      "tier": 3,
      "level_req": 5,
      "giver": "wanderer",
      "objectives": [
        {"type": "kill", "target": "skeleton", "count": 10, "min_level": 5, "desc": "Kill level 5+ skeletons"}
      ],
      "xp_reward": 150,
      "gold_reward": 50,
      "prereq": "proving_ground"
    },
    {
      "id": "rumors_of_ruins",
      "name": "Rumors of Ruins",
      "description": "Ancient ruins lie at the edge of the wasteland. Find them.",
      "tier": 4,
      "level_req": 5,
      "giver": "wanderer",
      "objectives": [
        {"type": "explore", "target": "ruins", "count": 1, "desc": "Discover the ancient ruins"}
      ],
      "xp_reward": 150,
      "gold_reward": 50,
      "prereq": "fire_and_ash"
    },
    {
      "id": "guardian_encounter",
      "name": "Guardian Encounter",
      "description": "The ruins are protected by guardian skeletons - the Lich's elite. Test yourself.",
      "tier": 4,
      "level_req": 6,
      "giver": "wanderer",
      "objectives": [
        {"type": "kill", "target": "skeleton", "count": 3, "is_guardian": true, "desc": "Kill guardian skeletons"}
      ],
      "xp_reward": 175,
      "gold_reward": 60,
      "prereq": "rumors_of_ruins"
    },
    {
      "id": "seek_the_hub",
      "name": "Seek the Trading Hub",
      "description": "A tunnel at the northern edge leads to the Trading Hub. Find it.",
      "tier": 5,
      "level_req": 7,
      "giver": "wanderer",
      "objectives": [
        {"type": "explore", "target": "tunnel_entrance", "count": 1, "desc": "Find the tunnel entrance"}
      ],
      "xp_reward": 175,
      "gold_reward": 60,
      "prereq": "veteran_hunter"
    },
    {
      "id": "elrics_letter",
      "name": "Elric's Letter",
      "description": "Deliver the Wanderer's letter to the Blacksmith in the Trading Hub.",
      "tier": 5,
      "level_req": 7,
      "giver": "wanderer",
      "objectives": [
        {"type": "speak_to_npc", "target": "blacksmith", "count": 1, "desc": "Speak to the Blacksmith"}
      ],
      "xp_reward": 0,
      "gold_reward": 100,
      "prereq": "seek_the_hub"
    },
    {
      "id": "forge_materials",
      "name": "Forge Materials",
      "description": "The Blacksmith needs quality materials. Find Iron Ore in the wasteland.",
      "tier": 6,
      "level_req": 8,
      "giver": "blacksmith",
      "objectives": [
        {"type": "collect", "target": "Iron Ore", "count": 5, "desc": "Collect Iron Ore"}
      ],
      "xp_reward": 125,
      "gold_reward": 50,
      "prereq": "elrics_letter"
    },
    {
      "id": "reclaim_the_ruins",
      "name": "Reclaim the Ruins",
      "description": "The ruins have an ancient hearth. Convert it to a campfire for survivors.",
      "tier": 6,
      "level_req": 8,
      "giver": "blacksmith",
      "objectives": [
        {"type": "convert_ruins", "target": "", "count": 1, "desc": "Convert ruins to campfire"}
      ],
      "xp_reward": 175,
      "gold_reward": 75,
      "prereq": "elrics_letter"
    },
    {
      "id": "guardians_bane",
      "name": "Guardian's Bane",
      "description": "Become the terror of the ruins. Break the guardian defense.",
      "tier": 7,
      "level_req": 9,
      "giver": "blacksmith",
      "objectives": [
        {"type": "kill", "target": "skeleton", "count": 10, "is_guardian": true, "desc": "Kill guardian skeletons"}
      ],
      "xp_reward": 200,
      "gold_reward": 100,
      "prereq": "forge_materials"
    },
    {
      "id": "ancient_secret",
      "name": "Ancient Secret",
      "description": "The Lich's Finger Bone holds secrets. The guardians protect it. Take it.",
      "tier": 7,
      "level_req": 9,
      "giver": "blacksmith",
      "objectives": [
        {"type": "collect", "target": "Lich's Finger Bone", "count": 1, "desc": "Find the Lich's Finger Bone"}
      ],
      "xp_reward": 250,
      "gold_reward": 150,
      "prereq": "guardians_bane"
    },
    {
      "id": "into_darkness",
      "name": "Into the Darkness",
      "description": "You are ready. Enter the Cursed Lands through the north passage.",
      "tier": 8,
      "level_req": 10,
      "giver": "blacksmith",
      "objectives": [
        {"type": "enter_zone", "target": "zone2", "count": 1, "desc": "Enter the Cursed Lands"}
      ],
      "xp_reward": 0,
      "gold_reward": 200,
      "prereq": "ancient_secret"
    }
  ]
}
```

---

## Part 8: New Objective Types Needed

### speak_to_npc
```gdscript
# Triggered when player interacts with target NPC
func on_npc_interaction(npc_id: String):
    for quest_id in active_quests:
        var quest = quests[quest_id]
        for i in range(quest.objectives.size()):
            var obj = quest.objectives[i]
            if obj.type == "speak_to_npc" and obj.target == npc_id:
                update_objective_progress(quest_id, i, 1)
```

### enter_zone
```gdscript
# Triggered when player transitions to target zone
func on_zone_entered(zone_id: String):
    for quest_id in active_quests:
        var quest = quests[quest_id]
        for i in range(quest.objectives.size()):
            var obj = quest.objectives[i]
            if obj.type == "enter_zone" and obj.target == zone_id:
                update_objective_progress(quest_id, i, 1)
```

---

## Appendix A: XP Comparison

### Old vs New Totals

| Metric | Old System | New System |
|--------|------------|------------|
| XP to L10 | 1,675 | 7,160 |
| Quest XP Total | 10,600 | 2,000 |
| Quest % of Leveling | 632% (!) | 28% |
| Grinding Required | Optional | 72% |
| Est. Time to L10 | ~20 min | 2-3 hours |

### Grinding Time Estimates (New System)

| Level Range | XP Needed | Avg Kills | Time |
|-------------|-----------|-----------|------|
| 1→5 | 1,360 | ~95 | ~8 min |
| 5→7 | 1,500 | ~85 | ~7 min |
| 7→10 | 4,300 | ~175 | ~15 min |
| **Total** | **7,160** | **~355** | **~30 min** |

With quests adding ~40-60 min of objective/travel time, total time to L10 is **2-3 hours**.

---

## Appendix B: Zone Geography Reference

```
Y = -4000 (NORTH) ─── TUNNEL ENTRANCES (Level 7+ content)
         │
         │  Guardian territory (Level 6-10)
         │  Ancient ruins location
         │
Y = -2000 ─── Lava pools (Level 4-6)
         │  Higher level skeletons
         │  Wolf pack territory
         │
Y = 0    ─── CAMPFIRE (Level 1-3)
         │  Wanderer NPC
         │  New player spawn
         │
Y = +2000 ─── (Edge of starting area)
         │
Y = +4000 (SOUTH) ─── Southern boundary
```

This geography naturally guides players:
1. Start at campfire (center)
2. Push north as they level
3. Find tunnel when they're ready (L7+)

---

*Document version 1.0 - December 2024*
