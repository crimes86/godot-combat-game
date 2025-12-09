# Dreadland Golden Rules

> **Status**: Immutable
> **Last Updated**: December 2024

These principles are **non-negotiable** and apply forever. Any feature, system, or decision that violates these rules must be rejected.

---

## Rule 1: No Pay-to-Win

**Statement**: Real money cannot buy gameplay advantages.

**What this means**:
- No purchasable stat boosts
- No purchasable weapons or armor with superior stats
- No XP boosters for sale
- No premium currency that affects combat
- No loot boxes with gameplay items

**What IS allowed**:
- Cosmetics (visual only, no stats)
- Convenience features (extra storage, fast travel with limitations)
- Supporter tiers that unlock no gameplay advantages

**Why**: Games that sell power alienate their core players and create hollow experiences. Skill and time investment should be the only paths to power.

---

## Rule 2: No Bots

**Statement**: Automated play is not allowed.

**What this means**:
- No scripted farming
- No auto-combat
- No achievement unlocking services
- No account sharing for achievement farming
- No third-party tools that play the game for you

**Enforcement**:
- Behavioral analysis for suspicious patterns
- Rate limiting on actions
- Human verification for high-value activities
- Account bans for confirmed botting

**Why**: Bots devalue legitimate player effort and destroy economies. If achievements can be botted, the entire Forge system loses meaning.

---

## Rule 3: Native Gear = Forged Gear

**Statement**: In-game earned equipment and Forge-created items are balanced equally.

**What this means**:
- A sword dropped from a boss should be comparable to a forged sword of similar tier
- Neither source is inherently "better" - they're different paths to similar power
- Forged items have unique visual identity and provenance, not superior stats
- Balancing is ongoing; neither should ever become clearly dominant

**What Forged items offer (that native doesn't)**:
- Achievement provenance (proof of accomplishment)
- Unique visual effects tied to the achievement source
- Tradeable status with ownership history
- Collectible value from limited availability

**What Native items offer (that forged doesn't)**:
- Earned through Dreadland gameplay specifically
- No external requirements
- Accessible to all players regardless of achievement history
- Craftable and upgradeable through in-game systems

**Why**: If forged items are strictly better, non-achievement players feel excluded. If native items are strictly better, the Forge system becomes pointless. Balance creates two valid, parallel progression paths.

---

## Rule 4: Achievements Are Sacred

**Statement**: Achievement verification must be legitimate and tamper-proof.

**What this means**:
- All achievements verified through official platform APIs (Steam, Xbox, PlayStation, etc.)
- No self-reported achievements
- No purchased achievement accounts
- One-time claim per achievement per account (no unlink/relink exploits)
- `is_original_claim` tracking prevents duplicate credits

**Technical safeguards**:
- OAuth verification with platform providers
- Achievement timestamp validation
- Provider user ID tracking across account links
- Effort scoring based on achievement rarity

**Why**: The entire Forge system's value depends on achievements being real. Fake achievements devalue everyone's legitimate accomplishments.

---

## Rule 5: Your Items Are Yours

**Statement**: Once you own an item, it cannot be taken from you arbitrarily.

**What this means**:
- No admin seizure of items without documented rule violation
- No "rebalancing" that removes items from inventories
- No expiring items (except explicitly temporary buffs)
- Blockchain provenance provides ownership proof independent of our servers
- If Dreadland shuts down, your forged items still exist on-chain

**Exceptions** (with full transparency):
- Items obtained through exploits may be removed
- Banned accounts lose access (items remain on-chain but locked)
- Bug fixes that affect item stats (not removal)

**Why**: Player trust requires ownership certainty. MMOs that arbitrarily remove items lose their playerbase.

---

## Rule 6: Blockchain Is Invisible

**Statement**: Crypto complexity is never exposed to players who don't want it.

**What this means**:
- No wallet setup required to play
- No gas fees for players
- No blockchain terminology in normal gameplay
- No "connect wallet" prompts during regular play
- Trading works like any MMO - gold and items, simple windows

**For crypto-interested players**:
- Optional: Export items to personal wallet
- Optional: View provenance on block explorer
- Optional: Trade on external marketplaces
- All of this is opt-in, never required

**Why**: Traditional gamers don't care about blockchain. Crypto enthusiasts can find the features they want. Neither group should be forced into the other's experience.

---

## Rule 7: Server Authority

**Statement**: The server is always the source of truth for gameplay.

**What this means**:
- All combat calculations happen server-side
- Client sends inputs, server validates and executes
- No client-side damage calculation
- No client-trusted inventory operations
- Anti-cheat is server-enforced, not client-dependent

**Why**: Client-authoritative games are trivially hackable. Every competitive action must be validated by the server.

---

## Applying These Rules

When evaluating any new feature, ask:

1. Does this let players buy power? → **Reject**
2. Can this be automated? → **Add safeguards**
3. Does this favor forged over native (or vice versa)? → **Rebalance**
4. Can achievements be faked? → **Strengthen verification**
5. Does this threaten item ownership? → **Reconsider**
6. Does this expose blockchain to casual players? → **Hide it**
7. Does this trust the client? → **Move to server**

---

## Version History

| Date | Change |
|------|--------|
| Dec 2024 | Initial document created |

---

*These rules exist because Dreadland is built for players, not profit extraction. Violating them would betray the community we're building.*
