# Dynamic NPC Behavior System Specification

## Vision

Rather than duplicating bosses across instances or creating artificial scarcity through camping, Ashbane creates a **living world** where NPCs have their own schedules, behaviors, and agency. This solves the "one mob in one place" problem by making the world feel alive rather than static.

**Core Principle**: The world happens with or without players. You can't be everywhere, and that's okay - it creates natural FOMO and genuine discovery.

## The Problem We're Solving

### Traditional MMO Design (What We're Avoiding)
```
Static Boss Design:
- Boss X spawns at location Y every 4 hours
- Players camp spawn point 24/7
- First guild to pull gets kill
- Creates degenerate gameplay patterns
- Feels artificial and gamey
```

### Our Approach
```
Living World Design:
- Chief Grimjaw has a LIFE - patrol routes, meal times, meetings
- Sometimes he's in his throne room, sometimes hunting
- Players must scout, gather intel, plan raids
- World feels alive, not like a respawn timer
- Discovery and planning are rewarded
```

## Core Concepts

### 1. NPC Schedules

Every significant NPC operates on a schedule system:

```
Example: Orc Chieftain "Grimjaw"

06:00 - 08:00  | Sleeping in chieftain's quarters (vulnerable, alone)
08:00 - 10:00  | War council with lieutenants (protected, indoors)
10:00 - 14:00  | Throne room - receiving tribute (public, guards)
14:00 - 16:00  | Inspecting camp perimeter (patrol route)
16:00 - 18:00  | Training grounds - sparring (distracted)
18:00 - 20:00  | Feast hall - eating with clan (social, loud)
20:00 - 22:00  | Private chambers - planning (limited guards)
22:00 - 06:00  | Night patrol OR sleeping (varies by day)
```

**Gameplay Implications:**
- Raid at 6 AM game time = stealth assassination opportunity
- Raid at 2 PM = full throne room battle
- Players learn patterns through observation
- Schedule can be disrupted by world events

### 2. NPC Behaviors / States

NPCs respond dynamically to world state:

```
Behavior States:
├── ROUTINE        - Following normal schedule
├── ALERTED        - Recent attack, heightened security
├── HUNTING        - Actively pursuing threat/prey
├── GATHERING      - Resource collection (camps, lairs)
├── MIGRATING      - Seasonal/event movement
├── WAR_FOOTING    - Guild conflict, mobilized
├── WOUNDED        - Recovering from previous encounter
└── RITUAL         - Special events (full moon, etc.)
```

**State Transitions:**
- Failed raid attempt → Chieftain enters ALERTED for 24h
- Full moon → Certain NPCs enter RITUAL state
- Season change → Migration patterns activate
- Player faction reputation → NPCs may be HOSTILE vs NEUTRAL

### 3. Zone Events (World Happens Without You)

Events occur on timers that players cannot directly control:

```
Event Examples:

"The Hunt Begins"
- Every 3-5 days (randomized)
- Chieftain leads hunting party into nearby forest
- Lair is lightly defended during this time
- Party returns with bonus loot/buffs

"Trade Caravan Arrival"
- Merchants arrive at major settlements
- NPCs congregate at market areas
- Opportunity for ambushes OR trade

"Territorial Dispute"
- Two enemy factions fight over border
- Weakens both groups temporarily
- Creates rare drop opportunities

"The Ritual"
- Full moon triggers special behaviors
- Some enemies become stronger
- Some become vulnerable
- Time-limited opportunities
```

### 4. Information Systems

Players discover NPC patterns through gameplay, not wikis:

```
Scout Reports:
├── Direct observation (watching patrol routes)
├── Captured intel (dropped orders, letters)
├── NPC informants (faction reputation rewards)
├── Ranger tracking (reading signs, footprints)
└── Social networks (other players, rumors)

"Scout the Grimjaw Encampment"
- Quest rewards: Rough schedule info
- Repeatable for updated intel
- Info degrades over time (schedules shift)
```

**Anti-Wiki Design:**
- Schedules have randomized variance (+-30 min)
- Weekly schedule rotation (different patterns)
- World events disrupt normal behavior
- Information shared in-game feels valuable

## Boss Design Patterns

### Pattern A: The Wanderer

Boss has multiple locations and moves between them:

```
Dragon "Ashwing" Design:
- Primary Lair: Volcanic caldera (most loot)
- Hunting Grounds: Forest valley (appears 2x/week)
- Nest: Mountain peak (protecting eggs - enraged)
- Territory Patrol: Flies circuit every 4 hours

Players must:
1. Track dragon's current location
2. Choose engagement point (each has tradeoffs)
3. Time their raid to dragon's schedule
4. Accept they might miss the "optimal" window
```

### Pattern B: The Reactive Boss

Boss behavior changes based on player actions:

```
Lich King Design:
- Default: Entombed in crypt center
- After server-first kill: Roams as ghost for 48h
- After 3 kills in a week: Summons additional guards
- After month without kill: Power increases

"Revenge Mechanic":
- Lich remembers guilds that killed him
- Sends undead raids to those guilds' trees
- Creates ongoing rivalry narrative
```

### Pattern C: The Summoned Boss

Boss only appears under specific conditions:

```
Sea Serpent "Typhon" Design:
- Does not exist until summoned
- Summoning requires:
  1. Storm weather (random, every few days)
  2. Sacrifice at sea altar (player action)
  3. Fleet of ships present (multiplayer)
- Appears, must be defeated before storm ends
- Rewards scale with difficulty

No camping possible - requires coordination
```

### Pattern D: The Scheduled Event

Boss appears at announced times, creating natural congregation:

```
World Boss "The Ashbane" Design:
- Server-wide announcement 1 hour before spawn
- Appears at Origin Tree every Sunday
- All factions can participate
- Damage contribution = loot rolls
- Creates scheduled social events

Healthy for community:
- Players can plan real-life around it
- Guaranteed participation window
- Social coordination opportunity
```

## Loot Philosophy

### Encounter-Based, Not Boss-Based

Loot tables consider HOW you killed the boss:

```
Chieftain Kill Scenarios:

Throne Room Battle (Standard):
- Full guard complement
- Fair fight
- Standard loot table

Dawn Assassination (Stealth):
- Fewer guards, sleeping target
- Requires specific timing
- DIFFERENT loot table (rogue-favored)

During Hunt (Ambush):
- Boss at reduced health
- Mobile fight in forest
- Hunter/tracker loot bonuses

After Weakening Event:
- Territorial dispute wounded boss
- Easier fight
- Reduced loot quality

Loot quality reflects DIFFICULTY of your approach
```

### Rare Drop Distribution

For prestige items (like FBSS-equivalent):

```
Tiered Drop System:

Common (30%): Lesser Girdle of Speed
- Moderate stat boost
- Crafting material

Uncommon (10%): Girdle of Swiftness
- Good stats
- Tradeable (BoE)

Rare (2%): Chieftain's War Belt
- Excellent stats
- Bind on Pickup

Legendary (0.5%): [Unique - only 1 exists]
- Server-first bonus
- Name recorded in world history
- If owner quits, returns to loot table

Everyone gets SOMETHING useful
Prestige items remain prestigious
```

## Player Distribution & Territory Control

### The Core Problem

In a single-world MMO, if one boss drops the "best" item, all players concentrate there. This creates:
- Degenerate camping behavior
- Empty zones elsewhere
- Poor player experience

### Camping as Contestable Territory

Rather than preventing camping, we make it **contestable content**:

```
Guild A controls Orc Camp region
   └── They "own" access to Chieftain Grimjaw
   └── They farm him on their schedule
   └── This is valuable territory

Guild B wants Grimjaw's loot
   └── Option 1: Bane Guild A, take the territory
   └── Option 2: Raid during Guild A's off-hours
   └── Option 3: Attack Guild A while they're fighting Grimjaw
   └── Option 4: Trade/negotiate for the drops
```

The camp **becomes content**. It's not "first to tag wins" - it's "control this area or fight for it."

### Guild Territory as Natural Distribution

```
Your guild controls Western Highlands
   └── You farm YOUR bosses, develop YOUR land
   └── Enemy guild controls Ashfall Crater
   └── They farm THEIR bosses
   └── Natural geographic distribution
```

The Shadowbane model - territory ownership spreads guilds out because you can't all own the same spot. Each guild has their own "home" content.

### Horizontal Itemization (Not Vertical)

Avoid creating a single "best" item that concentrates all players:

```
Instead of:
   Chieftain drops THE speed belt (everyone farms him)

Do:
   Orc Chieftain  → War Belt of Swiftness (+speed, +strength)
   Spider Queen   → Silken Speed Sash (+speed, +evasion)
   Frost Giant    → Glacier Striders (+speed, +cold resist)

All roughly equal power, different flavor/builds.
Players distribute based on build preferences and territory.
```

### Crafting Dependencies

Force multi-zone activity through crafting chains:

```
Best speed belt requires:
   - Chieftain's Buckle (Orc Camp)
   - Spider Silk Thread (Cave network)
   - Enchanted Clasp (Haunted Ruins)

You NEED multiple zones. Can't just camp one spot forever.
```

### Resource Geography

Different regions provide different resources:

```
Iron Ore       → Mountains (north)
Rare Herbs     → Swamp (south)
Ancient Wood   → Deep Forest (east)
Arcane Dust    → Ruins (scattered)

Crafters must travel. Guilds trade or control supply lines.
Resource control becomes strategic territory.
```

### Personal Lockouts

Prevent individuals from monopolizing content:

```
Killed the Chieftain?
   → 72-hour lockout for YOU
   → Go do something else
   → Guildmates get their turn
   → Encourages roster rotation
```

### Kill Credit by Contribution

Eliminate "first tag wins" frustration:

```
Damage dealt to boss = loot roll chance
   → Everyone who participates gets a roll
   → Larger groups = more total loot
   → No incentive to grief other players' pulls
   → Encourages cooperation or open warfare (not tagging games)
```

### Distribution Mechanics Summary

| Mechanic | Distribution Effect |
|----------|---------------------|
| Guild territory | Geographic spread by faction |
| Horizontal loot | No single "best" farm spot |
| Crafting chains | Forces multi-zone activity |
| Resource geography | Spreads gatherers across world |
| Personal lockouts | Rotates individuals through content |
| Contribution credit | Removes first-tag racing |

### Territory Control Loop

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Guild claims territory (plants tree)                     │
│ 2. Territory contains valuable content (bosses, resources)  │
│ 3. Guild farms their territory, grows stronger              │
│ 4. Other guilds contest via bane system or raids            │
│ 5. Territory changes hands OR defenders hold                │
│ 6. Losing guild seeks new territory elsewhere               │
│ 7. World remains distributed, not concentrated              │
└─────────────────────────────────────────────────────────────┘
```

The key insight: **Camping IS the gameplay** when territory matters. The question isn't "how do we stop camping" but "how do we make territorial control meaningful and contestable."

## Technical Implementation Notes

### Schedule System Architecture

```
NPCScheduleManager
├── TimeOfDay tracking (synced with TimeManager)
├── DayOfWeek tracking (7-day cycles)
├── Schedule definitions (data-driven, JSON/Resource)
├── Variance injection (randomness)
└── Override system (for events, player actions)

Each significant NPC has:
- ScheduleResource defining weekly pattern
- BehaviorStateMachine for current state
- AlertLevel affecting schedule adherence
- LastInteraction tracking player encounters
```

### Data Structure (Conceptual)

```gdscript
class_name NPCSchedule
extends Resource

@export var npc_id: String
@export var base_schedule: Dictionary  # hour -> location/activity
@export var weekly_variations: Array[Dictionary]  # per-day overrides
@export var event_overrides: Dictionary  # event_id -> schedule changes
@export var variance_minutes: int = 30  # randomization window

func get_current_activity(time: int, day: int) -> NPCActivity:
    # Returns what NPC should be doing right now
    pass

func get_next_transition(time: int, day: int) -> Dictionary:
    # Returns when NPC will change activity
    pass
```

### Zone Event System

```
ZoneEventManager
├── Event definitions (weighted random pool)
├── Cooldown tracking (no duplicate events)
├── Trigger conditions (weather, time, player count)
├── Active event tracking
└── NPC notification system (updates their schedules)

Events can:
- Add temporary NPCs
- Remove/relocate existing NPCs
- Modify NPC stats/behavior
- Create time-limited opportunities
- Broadcast to nearby players
```

## World Messaging

How players learn about opportunities:

```
Passive Discovery:
- Visual cues (smoke from camp = hunt returned)
- Audio cues (war drums = alert state)
- Environmental (fresh tracks = recent passage)

Active Discovery:
- Ranger skill: "Read the Signs"
- Scout skill: "Observe Patterns"
- Faction quests for intel

Social Discovery:
- Zone chat: "Grimjaw just left for the hunt!"
- Guild intel sharing
- Marketplace rumors from NPCs

System Messages (Rare):
- World boss announcements
- Major events only
- Preserves discovery for regular content
```

## Design Principles

### 1. Reward Preparation Over Reaction
Players who scout and plan have advantages over those who just show up.

### 2. Multiple Valid Approaches
There's no single "optimal" strategy - different timing/methods yield different results.

### 3. Accept Imperfect Information
Players won't always know exactly where bosses are - that's intentional.

### 4. Natural Scarcity Through Time
You can't be everywhere at once. Missing opportunities is part of the game.

### 5. Stories Emerge From Systems
When the dragon burned that guild's tree because they killed it last week - that's a story.

### 6. Respect Player Time
Scheduled events give players ability to plan. Random events reward those online.

## Integration With Battle System

This system complements (doesn't replace) the battle scaling:

```
Scenario: Guild War at Orc Camp

1. Defending guild has learned Chieftain's schedule
2. They time their defense for when Chief is present
3. Attacking guild scouts, knows schedule too
4. They attack during hunt (fewer defenders)
5. Chief returns mid-battle (dynamic reinforcement!)
6. Battle scales per DynamicTickRateManager
7. Chief's post-battle behavior changes (ALERTED)
```

The living world creates CONTEXT for battles, not replacement for battle tech.

## File Reference

| Component | Proposed File |
|-----------|---------------|
| Schedule Manager | `scripts/systems/NPCScheduleManager.gd` |
| Behavior State Machine | `scripts/ai/NPCBehaviorStateMachine.gd` |
| Zone Event Manager | `scripts/systems/ZoneEventManager.gd` |
| Schedule Resource | `scripts/resources/NPCSchedule.gd` |
| Event Definitions | `data/zone_events/` |
| Boss Configurations | `data/bosses/` |

## Related Documentation

- `LIMITLESS_BATTLE_ARCHITECTURE.md` - Battle scaling system
- `docs/guilds/` - Guild warfare mechanics
- `docs/loot/` - Loot distribution details

---

*This is a specification document. Implementation should be phased based on priority.*
