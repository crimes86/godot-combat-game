# Forge Provenance System

Technical specification for blockchain-backed item provenance. The "invisible infrastructure" that gives forged items real, verifiable history.

---

## Design Philosophy

### The Invisible Blockchain

```
USER EXPERIENCE GOAL:
━━━━━━━━━━━━━━━━━━━━
Traditional gamers: "I traded for this cool sword. It shows who made it."
Achievement hunters: "My 2007 Thunderfury has proof it's legit."
Crypto natives: "I can verify the chain if I want."

Everyone gets what they need. Nobody forced into crypto complexity.
```

### What Provenance Provides

1. **Trust** - Items can't be duplicated or counterfeited
2. **History** - Every trade is recorded permanently
3. **Scarcity Proof** - Census of all items is verifiable
4. **Value Foundation** - Real backing creates real value
5. **Optional Exit** - Cash-out path exists because ownership is provable

---

## Data Model

### Forged Item Record

Every forged item has this provenance data:

```json
{
  "item_instance_id": "uuid-v4-unique-per-item",
  "item_definition_id": "hand_of_malenia",

  "provenance": {
    "original_achievement": {
      "provider": "steam",
      "app_id": "1245620",
      "achievement_id": "SHARDBEARER_MALENIA",
      "achievement_name": "Shardbearer Malenia",
      "unlocked_at": "2022-03-15T14:23:45Z",
      "global_unlock_percent": 4.2
    },

    "forge_data": {
      "forged_at": "2024-12-08T10:30:00Z",
      "forged_by_user_id": "user_12345",
      "forged_by_display": "Legolazz",
      "forge_transaction_hash": "0x...",
      "effort_score": 92
    },

    "ownership": {
      "current_owner_id": "user_67890",
      "current_owner_display": "xXSlayerXx",
      "owned_since": "2024-12-10T08:15:00Z"
    },

    "trade_history": {
      "trade_count": 2,
      "trades": [
        {
          "from_user_display": "Legolazz",
          "to_user_display": "DarkKnight99",
          "traded_at": "2024-12-09T16:00:00Z",
          "trade_type": "direct",
          "transaction_hash": "0x..."
        },
        {
          "from_user_display": "DarkKnight99",
          "to_user_display": "xXSlayerXx",
          "traded_at": "2024-12-10T08:15:00Z",
          "trade_type": "marketplace",
          "price_credits": 15000,
          "transaction_hash": "0x..."
        }
      ]
    },

    "chain_data": {
      "token_id": 42069,
      "contract_address": "0x...",
      "network": "polygon",
      "mint_transaction": "0x...",
      "current_owner_wallet": null,
      "is_bridged_out": false
    }
  }
}
```

### Database Schema

```sql
-- Item instances (one per forged item in existence)
CREATE TABLE forged_items (
    instance_id UUID PRIMARY KEY,
    definition_id VARCHAR(100) NOT NULL,

    -- Forge data
    forged_at TIMESTAMP NOT NULL,
    forged_by_user_id UUID NOT NULL,
    achievement_provider VARCHAR(50) NOT NULL,
    achievement_id VARCHAR(200) NOT NULL,
    achievement_unlocked_at TIMESTAMP,
    effort_score INTEGER NOT NULL,

    -- Current state
    current_owner_id UUID NOT NULL,
    owned_since TIMESTAMP NOT NULL,
    trade_count INTEGER DEFAULT 0,

    -- Chain data
    token_id BIGINT UNIQUE,
    mint_transaction_hash VARCHAR(66),
    is_bridged_out BOOLEAN DEFAULT FALSE,

    -- Indexes
    INDEX idx_owner (current_owner_id),
    INDEX idx_definition (definition_id),
    INDEX idx_forger (forged_by_user_id)
);

-- Trade history (append-only log)
CREATE TABLE forged_item_trades (
    trade_id UUID PRIMARY KEY,
    instance_id UUID NOT NULL REFERENCES forged_items,

    from_user_id UUID NOT NULL,
    to_user_id UUID NOT NULL,
    traded_at TIMESTAMP NOT NULL,

    trade_type VARCHAR(20) NOT NULL, -- 'direct', 'marketplace', 'gift'
    price_gold BIGINT,
    price_credits INTEGER,

    transaction_hash VARCHAR(66),

    INDEX idx_instance (instance_id),
    INDEX idx_traded_at (traded_at)
);

-- Item census (aggregated view)
CREATE VIEW item_census AS
SELECT
    definition_id,
    COUNT(*) as total_forged,
    COUNT(*) FILTER (WHERE is_bridged_out = FALSE) as in_game,
    MIN(forged_at) as first_forged,
    MAX(forged_at) as last_forged
FROM forged_items
GROUP BY definition_id;
```

---

## User-Facing Display

### In-Game Item Inspection

When a player inspects a forged item:

```
┌─────────────────────────────────────────────────────────────┐
│ ⚔️ HAND OF MALENIA                                          │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ Legendary Weapon • Katana                                    │
│                                                              │
│ "Let yourستures be my grave"                                │
│                                                              │
│ ┌─ EFFECTS ─────────────────────────────────────────────┐   │
│ │ ⚡ Waterfowl Dance (Active) - 12-hit flurry            │   │
│ │ ❤️ Scarlet Rot Lifesteal - Heal 5% of damage           │   │
│ └───────────────────────────────────────────────────────┘   │
│                                                              │
│ ┌─ PROVENANCE ──────────────────────────────────────────┐   │
│ │ Achievement: "Shardbearer Malenia" (4.2% of players)   │   │
│ │ Original Unlock: March 15, 2022                        │   │
│ │                                                        │   │
│ │ Forged by: Legolazz                                    │   │
│ │ Forge Date: December 8, 2024                           │   │
│ │                                                        │   │
│ │ Times Traded: 2                                        │   │
│ │ Current Owner: xXSlayerXx                              │   │
│ │                                                        │   │
│ │ 📊 Only 847 of these exist in Dreadland               │   │
│ └───────────────────────────────────────────────────────┘   │
│                                                              │
│ [View Trade History]    [View Certificate] (optional)        │
└─────────────────────────────────────────────────────────────┘
```

### Trade History View

Expanded trade history panel:

```
┌─ TRADE HISTORY ─────────────────────────────────────────────┐
│                                                              │
│  #1  Legolazz → DarkKnight99                                 │
│      Direct Trade • Dec 9, 2024                              │
│                                                              │
│  #2  DarkKnight99 → xXSlayerXx                               │
│      Marketplace • Dec 10, 2024 • 15,000 Credits             │
│                                                              │
│  ─────────────────────────────────────────────────────────   │
│  This item has been traded 2 times since forging.            │
│  Original forger retains recognition in perpetuity.          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Certificate View (Optional)

For users who want blockchain proof:

```
┌─ BLOCKCHAIN CERTIFICATE ────────────────────────────────────┐
│                                                              │
│  Token ID: #42069                                            │
│  Contract: 0x1234...5678 (Polygon)                           │
│                                                              │
│  Mint Transaction:                                           │
│  0xabcd...ef01                                               │
│  [View on PolygonScan ↗]                                     │
│                                                              │
│  Current Transactions:                                       │
│  Trade #1: 0x1111...2222                                     │
│  Trade #2: 0x3333...4444                                     │
│                                                              │
│  ─────────────────────────────────────────────────────────   │
│  This certificate proves authenticity on the blockchain.     │
│  Most players never need this - the game handles it.         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Chain Integration Architecture

### Why Polygon?

```
CHAIN SELECTION RATIONALE:
━━━━━━━━━━━━━━━━━━━━━━━━━
Polygon (chosen):
✓ Sub-cent transaction costs
✓ Fast finality (2 seconds)
✓ EVM compatible (standard tooling)
✓ Established, not likely to disappear
✓ Easy bridging to Ethereum if needed

Rejected alternatives:
✗ Ethereum mainnet - Too expensive for per-trade updates
✗ Solana - Different tooling, less stable history
✗ Custom L2 - Unnecessary complexity
✗ No chain - Loses verifiability and cash-out path
```

### Minting Flow

```
FORGE → MINT SEQUENCE:
━━━━━━━━━━━━━━━━━━━━━
1. User clicks "Forge" on achievement
2. Backend verifies achievement ownership (is_original_claim)
3. Backend creates forged_items DB record
4. Backend queues mint transaction
5. Relayer service submits to Polygon (gasless for user)
6. Transaction confirms (~2 seconds)
7. token_id written back to DB record
8. Item appears in user's inventory

User sees: "Forging... Done! ⚔️ Hand of Malenia added to inventory"
User doesn't see: Blockchain, transactions, gas, wallets
```

### Trade Recording Flow

```
TRADE → CHAIN UPDATE:
━━━━━━━━━━━━━━━━━━━━
1. Trade completes in-game (items/gold exchanged)
2. Backend updates forged_items.current_owner_id
3. Backend inserts forged_item_trades record
4. Backend queues chain update (batched, every 5 min)
5. Relayer submits batch transaction to Polygon
6. On-chain ownership matches database

The chain is EVENTUALLY CONSISTENT with the database.
Database is source of truth for gameplay.
Chain is source of truth for external verification.
```

### Gasless Transactions

Users never pay gas. We use meta-transactions:

```
RELAYER ARCHITECTURE:
━━━━━━━━━━━━━━━━━━━━
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Backend    │────▶│   Relayer    │────▶│   Polygon    │
│   (queues)   │     │   (pays gas) │     │   (records)  │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                     Funded by platform
                     (part of operating cost)

Gas costs (~$0.001 per tx) are covered by:
├── Forge fees ($2/forge)
├── Trade fees (5%)
└── Platform operating budget
```

---

## Smart Contract Design

### ForgedItems Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ForgedItems is ERC721, Ownable {
    struct ItemProvenance {
        string definitionId;      // "hand_of_malenia"
        string achievementId;     // "steam:1245620:SHARDBEARER_MALENIA"
        uint256 forgedAt;         // Unix timestamp
        address originalForger;   // Wallet that forged (can be platform wallet)
        uint256 tradeCount;       // Number of trades
    }

    mapping(uint256 => ItemProvenance) public provenance;
    uint256 private _nextTokenId;

    // Platform relayer address (can mint/transfer on behalf of users)
    address public relayer;

    constructor() ERC721("Dreadland Forged Items", "FORGE") {
        relayer = msg.sender;
    }

    modifier onlyRelayer() {
        require(msg.sender == relayer, "Only relayer");
        _;
    }

    function mint(
        address to,
        string memory definitionId,
        string memory achievementId
    ) external onlyRelayer returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);

        provenance[tokenId] = ItemProvenance({
            definitionId: definitionId,
            achievementId: achievementId,
            forgedAt: block.timestamp,
            originalForger: to,
            tradeCount: 0
        });

        return tokenId;
    }

    function recordTrade(
        uint256 tokenId,
        address newOwner
    ) external onlyRelayer {
        require(_exists(tokenId), "Token doesn't exist");

        address currentOwner = ownerOf(tokenId);
        _transfer(currentOwner, newOwner, tokenId);
        provenance[tokenId].tradeCount++;
    }

    // Users can also transfer directly if they bridge out
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        super.transferFrom(from, to, tokenId);
        provenance[tokenId].tradeCount++;
    }

    // View functions for verification
    function getProvenance(uint256 tokenId) external view returns (ItemProvenance memory) {
        require(_exists(tokenId), "Token doesn't exist");
        return provenance[tokenId];
    }

    function getItemCount(string memory definitionId) external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < _nextTokenId; i++) {
            if (keccak256(bytes(provenance[i].definitionId)) == keccak256(bytes(definitionId))) {
                count++;
            }
        }
        return count;
    }
}
```

### Platform Wallet Architecture

```
WALLET STRUCTURE:
━━━━━━━━━━━━━━━━
Platform Master Wallet
├── Holds all items for users who haven't bridged out
├── Relayer can transfer between users (in-game trades)
└── Funded with MATIC for gas

User Personal Wallets (optional)
├── Created only if user requests bridge-out
├── User controls private key
├── Can trade on external marketplaces (OpenSea, etc.)
└── Can bridge back in to game

Most users will NEVER have their own wallet.
Items "live" in platform wallet but are tracked per-user in DB.
```

---

## Bridge System

### Bridge Out (Game → External Wallet)

For users who want to trade on external marketplaces:

```
BRIDGE OUT FLOW:
━━━━━━━━━━━━━━━
1. User requests bridge-out from settings
2. User creates/connects external wallet
3. User selects items to bridge
4. Backend transfers tokens from platform wallet to user wallet
5. Items removed from in-game inventory
6. User now controls items externally

RESTRICTIONS:
├── 48-hour cooldown after request
├── Items cannot be used in-game while bridged
├── User pays gas for external transactions
└── Can bridge back in at any time (free)
```

### Bridge In (External Wallet → Game)

```
BRIDGE IN FLOW:
━━━━━━━━━━━━━━
1. User connects external wallet to account
2. Backend scans wallet for ForgedItems tokens
3. User selects items to bridge in
4. User approves transfer back to platform wallet
5. Items appear in in-game inventory
6. Full functionality restored

This allows:
├── Items bought on OpenSea to be used in-game
├── Items from other games (if we expand) to enter
└── Recovered items from compromised accounts
```

---

## Census & Statistics

### Public Item Census

Anyone can query total item counts:

```
CENSUS API:
━━━━━━━━━━━
GET /api/census/items

Response:
{
  "items": [
    {
      "definition_id": "hand_of_malenia",
      "total_forged": 847,
      "in_game": 823,
      "bridged_out": 24,
      "first_forged": "2024-12-08T10:30:00Z",
      "last_forged": "2024-12-15T22:45:00Z"
    },
    {
      "definition_id": "moonlight_greatsword",
      "total_forged": 1203,
      ...
    }
  ],
  "total_items": 15847,
  "last_updated": "2024-12-15T23:00:00Z"
}
```

### Provenance Verification

External verification endpoint:

```
GET /api/verify/{token_id}

Response:
{
  "valid": true,
  "item": {
    "definition_id": "hand_of_malenia",
    "name": "Hand of Malenia",
    "rarity": "legendary"
  },
  "provenance": {
    "achievement": "Shardbearer Malenia (Elden Ring)",
    "forged_at": "2024-12-08T10:30:00Z",
    "forged_by": "Legolazz",
    "trade_count": 2
  },
  "chain": {
    "token_id": 42069,
    "contract": "0x...",
    "network": "polygon"
  }
}
```

---

## Security Considerations

### Achievement Verification

```
ANTI-SPOOF MEASURES:
━━━━━━━━━━━━━━━━━━━
1. is_original_claim check (see ACHIEVEMENT_VERIFICATION.md)
2. Achievement timestamp validation (not forged before earned)
3. Provider API verification at forge time
4. Rate limiting on forge operations
5. Manual review for suspicious patterns
```

### Chain Security

```
CONTRACT SECURITY:
━━━━━━━━━━━━━━━━━
1. Relayer is only address that can mint/trade
2. Relayer key stored in HSM
3. Daily transaction limits on relayer
4. Multi-sig for contract upgrades
5. Audit before mainnet deployment
```

### Recovery Procedures

```
ITEM RECOVERY (for compromised accounts):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. User reports account compromise
2. Support verifies identity (2FA backup, email, etc.)
3. Account locked immediately
4. Items transferred to holding wallet
5. New account created, items transferred back
6. All trades from compromise period reversed
7. Chain updated to reflect recovery

Provenance shows: "Recovered from compromise on [date]"
Trade count does NOT increment for recovery transfers.
```

---

## Performance Considerations

### Database Optimization

```
QUERY PATTERNS:
━━━━━━━━━━━━━━
Hot paths (indexed):
├── Get user's inventory (current_owner_id)
├── Get item by instance_id
├── Get census by definition_id
├── Get recent trades (traded_at)

Cold paths (okay to be slower):
├── Full trade history for item
├── All items by original forger
├── Historical price analysis
```

### Chain Batching

```
BATCH STRATEGY:
━━━━━━━━━━━━━━
Trade Recording:
├── Queue trades as they happen
├── Batch submit every 5 minutes
├── Up to 100 trades per batch transaction
├── If queue >500, process immediately

This keeps gas costs low while maintaining reasonable finality.
For $0.001/tx and 100 trades/batch = $0.00001 per trade.
```

---

## Related Documents

- `FORGE_ECONOMY_DESIGN.md` - Trading and monetization
- `FORGE_ITEM_PHILOSOPHY.md` - Core design principles
- `FORGE_ITEM_EFFECTS.md` - Item power specifications
- `ACHIEVEMENT_VERIFICATION.md` - Anti-exploit measures

---

## Version History

- v1.0 (2024-12) - Initial provenance system specification
