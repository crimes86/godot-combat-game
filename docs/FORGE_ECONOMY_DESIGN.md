# Forge Economy Design

Complete specification for the Dreadland forge item economy: trading, monetization, and market dynamics.

---

## Design Principles

### Traditional Gamers First

```
TARGET AUDIENCE PRIORITY:
━━━━━━━━━━━━━━━━━━━━━━━
1. Traditional MMO players who want to trade items for gold
2. Achievement collectors who want their history recognized
3. Casual players who see cool items and wonder "how do I get that?"
4. (Distant 4th) Crypto natives who care about on-chain proof

The crypto scene is in shambles. We're building for gamers.
Blockchain is infrastructure, not marketing.
```

### The Invisible Blockchain

Users should NEVER:
- See a wallet popup
- Pay visible gas fees
- Need to understand crypto terminology
- Feel like they're using a "crypto game"

Users SHOULD:
- Trade items like any MMO
- See item history and provenance
- Know their items have "real" backing (if they care)
- Be able to cash out (if they want)

### Sustainable Monetization

```
THE BUSINESS MODEL:
━━━━━━━━━━━━━━━━━━
"With enough participation, the project founders do fine"
NOT
"Quick money grab scam that extracts maximum value"

Revenue comes from:
├── Volume of engaged players
├── Small fees on meaningful actions
├── Optional premium features
└── Long-term ecosystem health

NOT from:
├── Forcing crypto on users
├── Artificial scarcity manipulation
├── Pay-to-win mechanics
└── Aggressive monetization dark patterns
```

---

## Currency Systems

### In-Game Gold

The primary trading currency. Earned through gameplay.

```
GOLD ECONOMY:
━━━━━━━━━━━━
Sources:
├── Enemy drops
├── Quest rewards
├── Dungeon completion
├── Selling items to NPCs
└── Player-to-player trade

Sinks:
├── NPC item purchases
├── Repair costs
├── Consumables
├── Trade tax (5% on forged items)
├── Crafting materials
└── Fast travel / convenience features
```

### Credits (Premium Currency)

Optional currency that bridges in-game and real-world value.

```
CREDIT SYSTEM:
━━━━━━━━━━━━━━
Purchase: $1 = 100 Credits
Earn: Limited amounts from events, achievements

Uses:
├── Premium cosmetics (NOT forged items)
├── Character slots
├── Stash space
├── Convenience features
└── Cash-out conversion (see below)

NOT usable for:
├── Buying forged items directly
├── Bypassing forge requirements
├── Power advantages
└── Gambling/lootboxes
```

### The Cash-Out Path

For players who want real-world value from their forged items:

```
CASH-OUT FLOW:
━━━━━━━━━━━━━━
1. Player has valuable forged item
2. Lists on marketplace for Credits
3. Buyer pays Credits
4. Seller receives Credits (minus 5% marketplace fee)
5. Seller can withdraw Credits to real money (minus 10% withdrawal fee)

Example:
├── Thunderfury listed for 50,000 Credits ($500 value)
├── Buyer pays 50,000 Credits
├── Seller receives 47,500 Credits (5% fee)
├── Seller withdraws: $427.50 (10% withdrawal fee)
├── Total platform take: $72.50 (14.5% effective)

This is OPTIONAL. Most players will trade for gold and never cash out.
```

---

## Trading System

### Design Philosophy: Live Trading

Trading in Dreadland is **social and physical** - you must be in the virtual presence of another player to trade. No anonymous auction house. This creates:
- Social hubs where traders congregate
- Reputation matters (scammers get known)
- Negotiation and haggling
- The classic MMO "WTS in chat" experience

```
WHY LIVE TRADING:
━━━━━━━━━━━━━━━━
✓ Creates natural gathering spots (trade at campfire)
✓ Builds community and reputation
✓ Enables negotiation and social interaction
✓ Prevents bot-driven market manipulation
✓ Feels like classic MMO trading (EQ, early WoW)

✗ No anonymous listings
✗ No AFK selling
✗ Must be online and present to trade
```

### In-Game Trade Windows

Standard MMO-style trading between nearby players:

```
DIRECT TRADE FLOW:
━━━━━━━━━━━━━━━━━
1. Player A right-clicks Player B → "Trade" (must be within 5 tiles)
2. Trade window opens (both sides visible)
3. Each player adds items/gold
4. Both click "Ready"
5. Both click "Accept"
6. Items exchange hands

For Forged Items:
├── Same flow, feels identical
├── 5% gold tax applied to receiving gold
├── Behind the scenes: provenance updated
├── Trade history recorded on chain (invisible to users)
```

### Chat Auction System

Players advertise items via chat, which populates a "Recently Advertised" list:

```
CHAT AUCTION FLOW:
━━━━━━━━━━━━━━━━━
1. Player types: "/sell Hand of Malenia 50000g" or "WTS Hand of Malenia 50k"
2. Message appears in Trade chat channel
3. Backend parses message, extracts item + price
4. Entry added to "Recently Advertised" list (visible to all in zone)
5. Interested buyer clicks entry → "Whisper Seller" or "Find Seller"
6. Buyer travels to seller's location
7. Trade window opened when in proximity

RECENTLY ADVERTISED UI:
┌──────────────────────────────────────────────────────────────┐
│ 🔔 RECENTLY ADVERTISED                          [Trade Chat] │
├──────────────────────────────────────────────────────────────┤
│ ⚔️ Hand of Malenia    50,000g    Legolazz    2m ago  [📍][💬] │
│ 🛡️ Great Tortoise     12,000g    DarkKnight  5m ago  [📍][💬] │
│ 💎 Void Heart         85,000g    xXSlayerXx  8m ago  [📍][💬] │
│ ⚔️ Moonlight GS       35,000g    Patches     12m ago [📍][💬] │
└──────────────────────────────────────────────────────────────┘
[📍] = Show on map    [💬] = Whisper seller
```

### Auction Commands

```
CHAT COMMANDS:
━━━━━━━━━━━━━━
/sell <item> <price>     - Advertise item for sale
/buy <item> <price>      - Post wanted ad (looking to buy)
/cancel                  - Remove your active listing

SHORTHAND (also parsed):
"WTS Hand of Malenia 50k"    → Parsed as sell listing
"WTB any legendary 100k+"    → Parsed as buy request
"selling malenia sword 50000" → Fuzzy matched to item

LISTING RULES:
├── One active listing per item
├── Listings expire after 30 minutes (re-advertise to refresh)
├── Must have item in inventory to list
├── Price shown in listing is starting point (negotiable)
```

### Trade Cooldowns

Prevent rapid flipping:

```
COOLDOWN RULES:
━━━━━━━━━━━━━━
After acquiring any forged item:
├── 24 hours before can trade again
├── Timer visible on item tooltip
├── Item shows "Recently Acquired" badge

Exceptions:
├── Original forge has no cooldown (can trade immediately)
├── Gifting to guild members (reduced cooldown)
```

---

## Monetization Model

### Revenue Streams

```
REVENUE BREAKDOWN (Target Mix):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
40% - Premium Cosmetics & Convenience
      ├── Character slots
      ├── Stash tabs
      ├── Name changes
      ├── Premium visual effects (NOT power)
      └── Convenience features

30% - Trade Fees
      ├── 5% gold tax on forged item trades
      ├── 5% marketplace fee on credit sales
      └── 10% cash-out withdrawal fee

20% - Forge Fees
      ├── $1-3 per forge operation
      └── Covers minting + processing

10% - Optional Subscriptions
      ├── Cosmetic perks (auras, titles)
      ├── Convenience (auto-loot, extra stash)
      └── NO gameplay advantages
```

### Forge Fee Structure

```
FORGE PRICING:
━━━━━━━━━━━━━
Base Forge Fee: $2.00 (or 200 Credits)

Modifiers:
├── Legendary item: +$1.00
├── First forge of the day: -50%
├── Bulk forge (3+ items): -25%

Example Day 1:
├── Forge Hand of Malenia (legendary): $2.00 (first forge discount)
├── Forge Moonlight Greatsword (legendary): $3.00
├── Forge Chaos Blade (epic): $2.00
└── Total: $7.00 for 3 prestigious items

This is a ONE-TIME fee. No recurring costs to own items.
```

### What We DON'T Do

```
ANTI-PATTERNS WE AVOID:
━━━━━━━━━━━━━━━━━━━━━━
❌ Loot boxes / gambling mechanics
❌ Pay-to-win power advantages
❌ Artificial scarcity manipulation
❌ FOMO-driven limited sales
❌ Aggressive notification spam
❌ Hiding prices until checkout
❌ Currency confusion (17 different currencies)
❌ Subscription required to play
❌ Energy systems / play gates
❌ Ads of any kind
```

---

## Market Dynamics

### Price Discovery

Organic price formation based on real scarcity:

```
WHAT DETERMINES PRICE:
━━━━━━━━━━━━━━━━━━━━━
1. Achievement Rarity
   └── Only ~1000 people have "Embrace the Void"
   └── Only those who link + forge create supply

2. Combat Utility
   └── Items with strong effects command premium
   └── Meta-relevant items more valuable

3. Visual Appeal
   └── Cooler looking items worth more
   └── Famous/iconic items have recognition premium

4. Provenance
   └── Original forgers can charge premium
   └── Low trade count = "fresh" item
   └── Ancient achievement dates add value
```

### Supply Dynamics

```
SUPPLY CALCULATION:
━━━━━━━━━━━━━━━━━━
Maximum possible supply = Players with achievement × Forge rate

Example - Thunderfury:
├── WoW players with achievement: ~50,000
├── Players who will play Dreadland: ~5% = 2,500
├── Players who will forge: ~50% = 1,250
├── Maximum Thunderfuries in Dreadland: ~1,250

Actual supply is likely MUCH lower:
├── Many won't discover Dreadland
├── Many won't bother to forge
├── Some accounts are inactive
└── Realistic supply: ~200-400

This is REAL scarcity, not artificial.
```

### Market Visibility

Making the economy feel alive:

```
VISIBILITY FEATURES:
━━━━━━━━━━━━━━━━━━━
Server Announcements:
├── "[Player] has forged [Legendary Item]!" (opt-out available)
├── "[Legendary Item] sold for [X] gold!" (large trades only)

Marketplace Data:
├── Recent sales history (anonymized)
├── Price trends over time
├── Item census (total in existence)

Item Inspect:
├── Provenance details
├── "Only X of these exist"
├── Trade history count
```

---

## Anti-Exploit Measures

### Trade Manipulation Prevention

```
ANTI-MANIPULATION RULES:
━━━━━━━━━━━━━━━━━━━━━━━
1. Trade Cooldowns
   └── 24h after acquisition before re-trade
   └── Prevents rapid flipping schemes

2. Proximity Requirement
   └── Must be within 5 tiles to trade
   └── Prevents automated/bot trading

3. Velocity Limits
   └── Max 10 trades per day per account
   └── Prevents bot activity

4. Listing Spam Prevention
   └── Max 1 active listing per item
   └── 30-second cooldown between /sell commands
   └── Listings expire after 30 minutes
```

### Gold Seller Prevention

```
GOLD FARMING MITIGATION:
━━━━━━━━━━━━━━━━━━━━━━━
1. Gold is NOT directly purchasable
2. Credits cannot convert to gold
3. Trade tax removes gold from economy
4. Large gold transfers flagged for review
5. New accounts have trade limits (7 day ramp)
```

### Account Security

```
SECURITY MEASURES:
━━━━━━━━━━━━━━━━━━
- 2FA required for cash-out
- Email confirmation for trades >10k gold
- Trade lock on password change (48h)
- Item recovery for verified compromises
- Provenance chain makes theft traceable
```

---

## Economy Health Metrics

### Tracking Indicators

```
HEALTHY ECONOMY SIGNS:
━━━━━━━━━━━━━━━━━━━━━
✓ Active listings in all price ranges
✓ Regular trades occurring (not stagnant)
✓ Price stability (not volatile swings)
✓ New forges happening regularly
✓ Low cash-out rate (<5% of trades)
✓ Players discussing item values organically

UNHEALTHY SIGNS:
✗ Only high-price items moving
✗ No new forges for days
✗ Rampant price manipulation reports
✗ Mass cash-outs
✗ Bot activity detected
✗ Player complaints about economy
```

### Intervention Triggers

```
WHEN TO ACT:
━━━━━━━━━━━━
If gold inflation >20%/month:
└── Increase gold sinks, reduce drops

If trading volume drops >50%:
└── Review fees, add trade incentives

If cash-out rate >10%:
└── Investigate cause, may indicate game health issue

If manipulation detected:
└── Temp-ban accounts, rollback suspicious trades
```

---

## Implementation Phases

### Phase 1: Core Trading (MVP)

```
LAUNCH FEATURES:
├── Direct player-to-player trade (proximity required)
├── 5% gold tax on forged items
├── Basic trade history on items
├── Forge fee ($2 flat)
├── Trade cooldown system (24h)
└── Provenance tracking
```

### Phase 2: Chat Auction System

```
CHAT AUCTIONS:
├── /sell and /buy commands
├── Trade chat channel
├── "Recently Advertised" UI panel
├── WTS/WTB message parsing
├── Whisper seller button
├── Show on map button
└── Listing expiration (30 min)
```

### Phase 3: Premium Currency

```
CREDIT SYSTEM:
├── Credit purchase
├── Premium cosmetics shop
├── Cash-out functionality
└── Credits as alternative trade currency
```

### Phase 4: Advanced Features

```
POLISH:
├── Server-wide legendary trade announcements
├── Advanced provenance display
├── Trade reputation system
├── Price history (from completed trades)
└── Item census display
```

---

## FAQ

**Q: Can I buy forged items with real money directly?**
A: No. You must find a player in-game and trade for gold (or negotiate a Credits trade).

**Q: Why is there no auction house?**
A: Live trading creates community. You'll meet other players, negotiate prices, and build reputation. It's the classic MMO experience.

**Q: What happens if I get scammed in a trade?**
A: Use the trade window system - it shows both sides and requires confirmation. We don't recover "bad deals" you agreed to.

**Q: Can items be stolen?**
A: Provenance tracking makes theft traceable. Enable 2FA. We can recover items from verified account compromises.

**Q: Why can't I trade my new item?**
A: 24-hour cooldown after acquisition. This prevents rapid flipping.

**Q: How do I find buyers/sellers?**
A: Use the Trade chat channel (/sell, /buy, or just "WTS/WTB"). Check the "Recently Advertised" panel to see active listings and contact sellers.

**Q: What if nobody wants to buy my item?**
A: Lower your price, advertise in chat, or wait for the right buyer. Rare achievements will always have demand - patience pays off.

---

## Related Documents

- `FORGE_ITEM_PHILOSOPHY.md` - Core design principles
- `FORGE_PROVENANCE_SYSTEM.md` - Blockchain backing details
- `FORGE_ITEM_EFFECTS.md` - Item power specifications
- `ACHIEVEMENT_ITEM_CREATION_PROCESS.md` - Adding new items

---

## Version History

- v1.0 (2024-12) - Initial economy design document
