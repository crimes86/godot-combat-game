# World Tree Documentation Archive

This directory contains **historical documentation** for the World Tree system. These docs are preserved for reference but are **no longer the active specification**.

## Active Documentation

For current World Tree v2.1 implementation, see:

- **Main Reference**: [`docs/WORLD_TREE_V2.1.md`](../../WORLD_TREE_V2.1.md)
- **Design Specification**: [`docs/WORLD_TREE_FINAL_DESIGN_V2.1.md`](../../WORLD_TREE_FINAL_DESIGN_V2.1.md)
- **Blockchain Integration**: [`docs/WORLD_TREE_BLOCKCHAIN_INTEGRATION.md`](../../WORLD_TREE_BLOCKCHAIN_INTEGRATION.md)

---

## Archived Documents

### Original Design (v1.x)
- `WORLD_TREE_SYSTEM.md` - Original v1.1 design specification (never implemented)
- `WORLD_TREE_FINAL_DESIGN.md` - v2.0 design (superseded by v2.1)
- `WORLD_TREE_COMPETITION.md` - Original competition mechanics (revised in v2.1)
- `WORLD_TREE_SETUP.md` - Early setup guide
- `WORLD_TREE_SYSTEM_MERGE.md` - Merge notes from consolidation

### Implementation Docs (v2.1)
- `WORLD_TREE_V2_1_IMPLEMENTATION_STATUS.md` - Implementation roadmap (completed Dec 14, 2024)
- `WORLD_TREE_V2_1_COMPLETE.md` - Implementation completion summary
- `WORLD_TREE_V2_1_UI_GUIDE.md` - UI guide (integrated into main doc)

---

## What Changed in v2.1

The v2.1 design addressed **12 critical flaws** from earlier versions:

1. **Dual Ownership** - Permanent original owner + transferable guild association
2. **Champion Tree Duplication** - Winner duplicated to origin, not moved
3. **Extended Decay** - 90 days for dynamic chunks (was 30 days)
4. **Neutral Factions** - 5 auto-assigned factions with 1.5x multiplier
5. **Universal Bane** - Any tree can be sieged (not just champion)
6. **Warehouse Safe Storage** - 50k gold, 5k resources protected
7. **Active Mine Collection** - 30min cooldown, diminishing returns
8. **Tree Ranks** - 0-7 progression (was 1-5)
9. **All-Time Leaderboard** - Seasonal rankings table
10. **Scheduled Bane** - Defender-chosen 1-hour windows
11. **Boss Kill Tracking** - Separate from regular kills (20pts each)
12. **Logarithmic Costs** - Chunks ±1-3 exponential, ±4+ linear

---

## Implementation Status

**v2.1 Status**: ✅ **COMPLETE** (December 14, 2024)

- ✅ Database schema migrated
- ✅ Backend models and API routes implemented
- ✅ Godot game logic updated (ChunkExpansionManager.gd)
- ✅ UI system created (WorldTreeUI with 7 tabs)
- ✅ Seed plot integration complete

**Next Phase**: Testing and polish

---

## Why These Docs Were Archived

1. **Outdated Design**: v1.x docs described a system that was never implemented
2. **Superseded Specs**: v2.0 design was revised to v2.1 with critical fixes
3. **Implementation Complete**: Implementation tracking docs served their purpose
4. **Consolidation**: All relevant content integrated into `WORLD_TREE_V2.1.md`

These docs remain available for historical reference and to understand the evolution of the World Tree system design.

---

**Archive Date**: December 14, 2024
**Active Version**: World Tree v2.1.0
