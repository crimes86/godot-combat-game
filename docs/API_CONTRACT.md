# Ashbane API Contract

> **This document defines the API contract between the Ashbane backend and Godot game client.**
> Both the backend Claude and game Claude should reference this file.

## Server Info

- **Development**: `http://localhost:8000`
- **Production**: `https://your-domain.com` (TBD)

---

## Authentication Flow

### 1. Start Device Auth
```
GET /api/auth/device
```

**Response:**
```json
{
  "device_code": "abc123...",
  "auth_url": "http://localhost:8000/login?device_code=abc123...",
  "poll_url": "http://localhost:8000/api/auth/status",
  "expires_in": 600
}
```

**Godot Action:** Open `auth_url` in browser, then poll `/api/auth/status`

---

### 2. Poll Auth Status
```
GET /api/auth/status?device_code={device_code}
```

**Response (pending):**
```json
{
  "status": "pending",
  "message": "Waiting for user authentication"
}
```

**Response (success):**
```json
{
  "status": "success",
  "user_id": 123,
  "username": "Ashbane-a1b2c3d4",
  "token": "eyJ..."
}
```

**Response (expired):**
```json
{
  "status": "expired",
  "message": "Device code not found or expired"
}
```

**Godot Action:**
- On `pending`: wait 2s, poll again
- On `success`: save `token` to file, use for API calls
- On `expired`: show error, let user retry

---

## Authenticated Endpoints

> All these require header: `Authorization: Bearer {token}`

### Get My Profile
```
GET /api/me
Authorization: Bearer {token}
```

**Response:**
```json
{
  "user_id": 123,
  "username": "Ashbane-a1b2c3d4",
  "total_achievements": 847,
  "by_rarity": {
    "Common": 412,
    "Uncommon": 298,
    "Rare": 89,
    "Epic": 34,
    "Legendary": 14
  },
  "ashbane": {
    "tier": "gold",
    "name": "Gold",
    "color": "#FFD700",
    "glow": "#DAA520",
    "effective_score": 847
  },
  "providers": [
    {
      "provider_name": "steam",
      "provider_user_id": "76561198012345678",
      "display_name": "ProGamer_2024",
      "avatar_url": "https://..."
    },
    {
      "provider_name": "battlenet",
      "provider_user_id": "12345",
      "display_name": "Player#1234"
    }
  ]
}
```

---

### Get My Achievements
```
GET /api/achievements
Authorization: Bearer {token}
```

**Response:**
```json
{
  "total": 847,
  "by_rarity": {
    "Common": 412,
    "Uncommon": 203,
    "Rare": 156,
    "Epic": 64,
    "Legendary": 12
  },
  "achievements": [
    {
      "id": 1,
      "api_name": "ACH_FIRST_BLOOD",
      "display_name": "First Blood",
      "description": "Get your first kill",
      "icon_url": "https://...",
      "rarity_tier": "Common",
      "percent": 85.2,
      "provider": "steam",
      "date_credited": "2024-01-15T10:30:00",
      "is_original_claim": true
    }
  ]
}
```

---

### Get Achievements by Rarity
```
GET /achievements/by-rarity/{rarity_tier}?provider_name={optional}
```

**Parameters:**
- `rarity_tier`: One of `Common`, `Uncommon`, `Rare`, `Epic`, `Legendary`
- `provider_name` (optional): Filter to specific provider

**Response:**
```json
{
  "rarity_tier": "Legendary",
  "count": 12,
  "achievements": [
    {
      "id": 1,
      "api_name": "ACH_LEGENDARY_HERO",
      "display_name": "Legendary Hero",
      "description": "Complete the impossible challenge",
      "icon_url": "https://...",
      "percent": 0.5,
      "rarity_tier": "Legendary",
      "game_name": "Some Game",
      "app_id": "440",
      "provider_name": "steam",
      "unlock_time": "2024-01-15T10:30:00",
      "is_original_claim": true
    }
  ]
}
```

---

### Get Linked Providers
```
GET /api/providers
Authorization: Bearer {token}
```

**Response:**
```json
{
  "providers": [
    {
      "provider_name": "steam",
      "display_name": "ProGamer_2024",
      "avatar_url": "https://...",
      "linked_at": "2024-01-01T00:00:00",
      "achievement_count": 500,
      "last_sync_at": "2024-12-06T10:30:00"
    }
  ]
}
```

---

### Sync Achievements
```
POST /sync_achievements/{provider_name}/{provider_user_id}
```

**Response (success):**
```json
{
  "provider": "steam",
  "credited": 15,
  "details": {}
}
```

**Response (cooldown - 429):**
```json
{
  "detail": "Sync cooldown active. 847 seconds remaining."
}
```

**Note:** 15-minute cooldown between syncs per provider. Admin users bypass cooldown.

---

### Unclaim Provider
```
POST /unclaim/{provider_name}
```

**Response (success):**
Redirects to `/dashboard`

**Response (blocked - last provider):**
Sets cookie `message=You must have at least one provider linked to your account.`
Redirects to `/dashboard`

---

## Public Endpoints (No Auth Required)

### Get Player Badge (Multiplayer)
```
GET /api/player/{user_id}/badge
```

**Response:**
```json
{
  "user_id": 123,
  "tier": "gold",
  "name": "Gold",
  "color": "#FFD700",
  "glow": "#DAA520",
  "effective_score": 1247
}
```

**404 Response:**
```json
{
  "detail": "Player not found"
}
```

**Godot Action:** Use for rendering other players' badges in multiplayer

---

### Get Tier Definitions
```
GET /api/tiers
```

**Response:**
```json
{
  "tiers": {
    "initiate":  {"min_score": 0,    "color": "#666666", "glow": "#444444", "name": "Initiate"},
    "bronze":    {"min_score": 100,  "color": "#CD7F32", "glow": "#8B4513", "name": "Bronze"},
    "silver":    {"min_score": 500,  "color": "#C0C0C0", "glow": "#808080", "name": "Silver"},
    "gold":      {"min_score": 1000, "color": "#FFD700", "glow": "#DAA520", "name": "Gold"},
    "platinum":  {"min_score": 2000, "color": "#E5E4E2", "glow": "#A0D8EF", "name": "Platinum"},
    "diamond":   {"min_score": 3000, "color": "#B9F2FF", "glow": "#40E0D0", "name": "Diamond"},
    "legendary": {"min_score": 5000, "color": "#FF6600", "glow": "#FF4500", "name": "Legendary"},
    "mythic":    {"min_score": 7500, "color": "#FF00FF", "glow": "#00FFFF", "name": "Mythic"}
  },
  "order": ["mythic", "legendary", "diamond", "platinum", "gold", "silver", "bronze", "initiate"]
}
```

**Godot Action:** Cache this on startup, use for local tier color lookups

---

## Wallet & Forging Endpoints

### Get Wallet Status
```
GET /api/wallet/status
Authorization: Bearer {token}
```

**Response (connected):**
```json
{
  "connected": true,
  "wallet_address": "0x1234...5678",
  "chain_id": 8453,
  "linked_at": "2024-12-01T00:00:00",
  "forged_count": 5
}
```

**Response (not connected):**
```json
{
  "connected": false
}
```

---

### Connect Wallet (Step 1 - Get Nonce)
```
POST /api/wallet/nonce
Authorization: Bearer {token}
Content-Type: application/json

{
  "wallet_address": "0x1234...5678"
}
```

**Response:**
```json
{
  "nonce": "abc123",
  "message": "Sign this message to connect your wallet to Ashbane...",
  "expires_at": "2024-12-06T10:40:00Z"
}
```

---

### Connect Wallet (Step 2 - Verify Signature)
```
POST /api/wallet/verify
Authorization: Bearer {token}
Content-Type: application/json

{
  "message": "Sign this message...",
  "signature": "0x..."
}
```

**Response:**
```json
{
  "success": true,
  "wallet_address": "0x1234...5678"
}
```

---

### Disconnect Wallet
```
DELETE /api/wallet/disconnect
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true
}
```

---

### Get Forgeable Achievements
```
GET /api/wallet/forgeable
Authorization: Bearer {token}
```

**Response:**
```json
{
  "wallet_address": "0x1234...5678",
  "forgeable": [
    {
      "credit_id": 123,
      "achievement_id": 456,
      "display_name": "Legendary Hero",
      "description": "Complete the impossible",
      "icon_url": "https://...",
      "rarity_tier": "Legendary",
      "percent": 0.5,
      "app_id": "440",
      "api_name": "ACH_LEGENDARY"
    }
  ]
}
```

**Note:** Only Rare, Epic, and Legendary achievements with `is_original_claim=true` can be forged.

---

### Forge Achievements
```
POST /api/wallet/forge
Authorization: Bearer {token}
Content-Type: application/json

{
  "achievement_credit_ids": [123, 456]
}
```

**Response:**
```json
{
  "forged": [
    {
      "credit_id": 123,
      "token_id": 1,
      "tx_hash": "0x...",
      "achievement_name": "Legendary Hero"
    }
  ],
  "failed": [
    {
      "credit_id": 456,
      "error": "Already forged"
    }
  ]
}
```

---

### Get Forged Achievements
```
GET /api/wallet/forged
Authorization: Bearer {token}
```

**Response:**
```json
{
  "forged": [
    {
      "token_id": 1,
      "contract_address": "0x...",
      "chain_id": 8453,
      "tx_hash": "0x...",
      "forged_at": "2024-12-01T00:00:00",
      "achievement": {
        "display_name": "Legendary Hero",
        "description": "Complete the impossible",
        "icon_url": "https://...",
        "rarity_tier": "Legendary"
      }
    }
  ]
}
```

---

### Check Token Ownership (Public)
```
POST /api/wallet/check-ownership
Content-Type: application/json

{
  "wallet_address": "0x1234...5678",
  "achievement_ids": ["steam_440_ACH_LEGENDARY"]
}
```

**Response:**
```json
{
  "wallet_address": "0x1234...5678",
  "ownership": {
    "steam_440_ACH_LEGENDARY": true
  }
}
```

---

### Get Token Provenance (Public)
```
GET /api/wallet/provenance/{token_id}
```

**Response:**
```json
{
  "token_id": 1,
  "item_id": "hand_of_malenia",
  "item_name": "Hand of Malenia",
  "original_earner": "0xabc...",
  "original_earner_display": "Legolazz",
  "current_owner": "0xdef...",
  "current_owner_display": "xXSlayerXx",
  "is_original": false,
  "acquisition_type": "traded",
  "achievement": {
    "id": "steam_1245620_SHARDBEARER_MALENIA",
    "display_name": "Shardbearer Malenia",
    "provider": "steam",
    "rarity_tier": "Legendary",
    "global_percent": 4.2,
    "unlocked_at": "2022-03-15T14:23:45Z"
  },
  "provenance": {
    "forged_at": "2024-12-08T10:30:00Z",
    "forged_by_display": "Legolazz",
    "trade_count": 2,
    "owned_since": "2024-12-10T08:15:00Z"
  },
  "census": {
    "total_forged": 847,
    "in_game": 823
  }
}
```

**Godot Action:** Use to show "EARNED" vs "TRADED" badges on equipped items, display full provenance in item inspection UI

---

### Get Token Metadata (NFT Marketplaces)
```
GET /api/wallet/metadata/{credit_id}
```

**Response (ERC-721 compatible):**
```json
{
  "name": "Legendary Hero",
  "description": "Complete the impossible\n\nVerified gaming achievement from steam.",
  "image": "https://...",
  "external_url": "https://Ashbane.gg/achievement/123",
  "attributes": [
    {"trait_type": "Rarity", "value": "Legendary"},
    {"trait_type": "Provider", "value": "steam"},
    {"trait_type": "Global Unlock %", "value": 0.5},
    {"trait_type": "Game ID", "value": "440"}
  ],
  "background_color": "ff8000"
}
```

---

## Trading & Economy Endpoints

> **Design Philosophy:** Live trading - players must be in proximity to trade. No auction house.
> Chat-based advertising populates a "Recently Advertised" list.
> See `docs/FORGE_ECONOMY_DESIGN.md` for full specification.

### Record Direct Trade
```
POST /api/trades/direct
Authorization: Bearer {token}
Content-Type: application/json

{
  "token_id": 42069,
  "to_user_id": 456,
  "price_gold": 50000
}
```

**Response:**
```json
{
  "success": true,
  "trade_id": "uuid-123",
  "item": {
    "token_id": 42069,
    "item_id": "hand_of_malenia",
    "new_owner_id": 456
  },
  "gold_transferred": 47500,
  "tax_applied": 2500,
  "provenance_updated": true
}
```

**Notes:**
- 5% gold tax applied to seller
- 24-hour trade cooldown starts for buyer
- Provenance updated on-chain (batched)
- Godot validates proximity before calling

---

### Get Trade History
```
GET /api/trades/history?limit=50&offset=0
Authorization: Bearer {token}
```

**Response:**
```json
{
  "trades": [
    {
      "trade_id": "uuid-123",
      "traded_at": "2024-12-10T08:15:00Z",
      "role": "seller",
      "item": {
        "token_id": 42069,
        "item_id": "hand_of_malenia",
        "item_name": "Hand of Malenia"
      },
      "counterparty_display": "DarkKnight99",
      "price_gold": 50000
    }
  ],
  "total": 15
}
```

---

### Post Trade Listing (Chat Auction)
```
POST /api/trades/listing
Authorization: Bearer {token}
Content-Type: application/json

{
  "token_id": 42069,
  "listing_type": "sell",
  "price_gold": 50000,
  "message": "WTS Hand of Malenia 50k - at campfire"
}
```

**Response:**
```json
{
  "success": true,
  "listing_id": "uuid-456",
  "expires_at": "2024-12-10T09:00:00Z",
  "broadcast_to": "trade_chat"
}
```

**Notes:**
- Listings expire after 30 minutes
- One active listing per item per player
- 30-second cooldown between /sell commands
- Message broadcast to Trade chat channel

---

### Get Active Listings (Recently Advertised)
```
GET /api/trades/listings?zone_id=dreadland
Authorization: Bearer {token}
```

**Response:**
```json
{
  "listings": [
    {
      "listing_id": "uuid-456",
      "listing_type": "sell",
      "item": {
        "token_id": 42069,
        "item_id": "hand_of_malenia",
        "item_name": "Hand of Malenia",
        "rarity": "legendary"
      },
      "price_gold": 50000,
      "seller": {
        "user_id": 123,
        "display_name": "Legolazz",
        "position": {"x": 450, "y": 320}
      },
      "message": "WTS Hand of Malenia 50k - at campfire",
      "posted_at": "2024-12-10T08:30:00Z",
      "expires_at": "2024-12-10T09:00:00Z"
    }
  ]
}
```

**Godot Action:** Populate "Recently Advertised" UI panel

---

### Cancel Trade Listing
```
DELETE /api/trades/listing/{listing_id}
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true
}
```

---

### Get Item Trade Cooldown
```
GET /api/trades/cooldown/{token_id}
Authorization: Bearer {token}
```

**Response (on cooldown):**
```json
{
  "token_id": 42069,
  "tradeable": false,
  "cooldown_ends": "2024-12-11T08:15:00Z",
  "seconds_remaining": 43200
}
```

**Response (tradeable):**
```json
{
  "token_id": 42069,
  "tradeable": true
}
```

---

### Get Item Census (Public)
```
GET /api/census/items
```

**Response:**
```json
{
  "items": [
    {
      "item_id": "hand_of_malenia",
      "item_name": "Hand of Malenia",
      "total_forged": 847,
      "in_game": 823,
      "first_forged": "2024-12-08T10:30:00Z"
    }
  ],
  "total_items": 15847
}
```

**Godot Action:** Display "Only X of these exist" on item tooltips

---

## Bridge System Endpoints

> **Design Philosophy:** Bridge system allows items to move between in-game (platform wallet) and external wallets (OpenSea).
> Traditional gamers never see this - it's opt-in for crypto-aware users.
> 48-hour cooldown prevents exploitation and gives time to recover compromised accounts.
> See `docs/FORGE_BRIDGE_SYSTEM.md` for full specification.

### Request Bridge Out
```
POST /api/wallet/bridge-out
Authorization: Bearer {token}
Content-Type: application/json

{
  "forged_achievement_ids": [1, 2, 3],
  "destination_wallet": "0x..."  // Optional, defaults to linked wallet
}
```

**Response:**
```json
{
  "success": true,
  "bridge_requests": [
    {
      "forged_achievement_id": 1,
      "item_name": "Hand of Malenia",
      "status": "bridging_out",
      "cooldown_ends_at": "2024-12-17T10:30:00Z",
      "destination_wallet": "0x..."
    }
  ],
  "failed": []
}
```

**Error (400):**
```json
{
  "error": "Items must be claimed to inventory before bridging"
}
```

**Notes:**
- 48-hour cooldown starts immediately
- Items become unusable in-game during cooldown
- Must have wallet connected
- Must own the items

---

### Get Bridge Out Status
```
GET /api/wallet/bridge-out/status
Authorization: Bearer {token}
```

**Response:**
```json
{
  "pending_bridges": [
    {
      "forged_achievement_id": 1,
      "item_name": "Hand of Malenia",
      "item_id": "hand_of_malenia",
      "status": "bridging_out",
      "requested_at": "2024-12-15T10:30:00Z",
      "cooldown_ends_at": "2024-12-17T10:30:00Z",
      "hours_remaining": 23.5,
      "can_confirm": false,
      "destination_wallet": "0x..."
    }
  ]
}
```

**Godot Action:** Show countdown timer on bridging items in inventory

---

### Confirm Bridge Out
```
POST /api/wallet/bridge-out/confirm
Authorization: Bearer {token}
Content-Type: application/json

{
  "forged_achievement_ids": [1]
}
```

**Response:**
```json
{
  "success": true,
  "transferred": [
    {
      "forged_achievement_id": 1,
      "item_name": "Hand of Malenia",
      "token_id": 42069,
      "tx_hash": "0x...",
      "destination_wallet": "0x..."
    }
  ],
  "failed": []
}
```

**Error (cooldown not expired):**
```json
{
  "failed": [
    {
      "forged_achievement_id": 1,
      "error": "Cooldown not expired. 23.5 hours remaining."
    }
  ]
}
```

**Notes:**
- Can only confirm after 48h cooldown expires
- Actually transfers NFT to external wallet
- Item removed from in-game inventory

---

### Cancel Bridge Out
```
POST /api/wallet/bridge-out/cancel
Authorization: Bearer {token}
Content-Type: application/json

{
  "forged_achievement_ids": [1]
}
```

**Response:**
```json
{
  "success": true,
  "cancelled": [1],
  "failed": []
}
```

**Notes:**
- Can cancel any time during cooldown
- Item returns to normal in-game status

---

### Get Bridge In Available
```
GET /api/wallet/bridge-in/available
Authorization: Bearer {token}
```

**Response:**
```json
{
  "wallet_address": "0x...",
  "available_items": [
    {
      "token_id": 42069,
      "item_id": "hand_of_malenia",
      "item_name": "Hand of Malenia",
      "item_rarity": "Legendary",
      "forged_by": "Legolazz",
      "forged_at": "2024-12-08T10:30:00Z",
      "can_bridge_in": true
    }
  ]
}
```

**Notes:**
- Scans user's external wallet for Dreadland items
- Only shows items in "bridged" status owned by connected wallet
- Items purchased on OpenSea appear here

---

### Request Bridge In
```
POST /api/wallet/bridge-in
Authorization: Bearer {token}
Content-Type: application/json

{
  "token_ids": [42069]
}
```

**Response:**
```json
{
  "success": true,
  "bridged_in": [
    {
      "token_id": 42069,
      "item_name": "Hand of Malenia",
      "status": "in_game",
      "tx_hash": "0x..."
    }
  ],
  "failed": []
}
```

**Notes:**
- Transfers NFT from user wallet to platform wallet
- Item becomes usable in-game immediately
- Updates ownership in database

---

### Bridge Status on Forged Items

The `/api/me/forge-status` endpoint now includes bridge information:

```json
{
  "wallet_connected": true,
  "wallet_address": "0x...",
  "summary": {
    "forged": 10,
    "forgeable": 5,
    "unforgeable": 100,
    "total": 115,
    "in_game": 8,
    "bridging_out": 1,
    "bridged": 1
  },
  "forged": [
    {
      "credit_id": 123,
      "achievement_id": 456,
      "display_name": "Legendary Hero",
      "rarity_tier": "Legendary",
      "provider": "steam",
      "is_original_claim": true,
      "forged_id": 1,
      "item_id": "hand_of_malenia",
      "item_name": "Hand of Malenia",
      "bridge_status": "in_game",
      "claimed_in_game": true,
      "usable_in_game": true
    }
  ],
  "forgeable": [...],
  "unforgeable": [...]
}
```

**Bridge Status Values:**
- `in_game` - Item is in platform wallet, usable in Dreadland
- `bridging_out` - 48h cooldown, item locked, not usable
- `bridged` - Item in external wallet, not usable in-game
- `bridging_in` - Being transferred back to platform

**Godot Action:** Use `usable_in_game` to determine if item can be equipped/used

---

## World Tree & Chunk Expansion Endpoints

### Get All Seed Plots
```
GET /api/world-tree/seed-plots?shard_id={shard_id}
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "seed_plots": [
    {
      "chunk_id": -1,
      "position_x": -4000.0,
      "position_y": 0.0,
      "owner_id": "123",
      "state": "claimed",
      "claim_cost": 1000,
      "contribution_score": 15420,
      "claimed_at": "2024-12-13T10:30:00",
      "last_contribution_at": "2024-12-13T14:22:00"
    }
  ]
}
```

---

### Get Specific Seed Plot
```
GET /api/world-tree/seed-plots/{chunk_id}?shard_id={shard_id}
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "seed_plot": {
    "chunk_id": -1,
    "position_x": -4000.0,
    "position_y": 0.0,
    "owner_id": "123",
    "state": "claimed",
    "claim_cost": 1000,
    "contribution_score": 15420,
    "total_gold_contributed": 5000,
    "total_wood_contributed": 200,
    "total_stone_contributed": 150,
    "total_kills": 842,
    "total_time_minutes": 1320,
    "claimed_at": "2024-12-13T10:30:00",
    "last_contribution_at": "2024-12-13T14:22:00"
  }
}
```

---

### Claim Seed Plot
```
POST /api/world-tree/seed-plots/{chunk_id}/claim
Authorization: Bearer {token}
Content-Type: application/json

{
  "chunk_id": -2,
  "shard_id": "default"
}
```

**Response:**
```json
{
  "success": true,
  "cost": 2000,
  "plot_id": -2,
  "message": "Seed plot claimed for 2000 gold"
}
```

**Notes:**
- Claim cost scales exponentially: base_cost * 2^(distance - 1)
- Half price during decay state
- Deducts gold from player's in-game balance

---

### Contribute to Seed Plot
```
POST /api/world-tree/seed-plots/{chunk_id}/contribute
Authorization: Bearer {token}
Content-Type: application/json

{
  "chunk_id": -1,
  "shard_id": "default",
  "gold": 100,
  "wood": 50,
  "stone": 30,
  "gems": 2,
  "kills": 15,
  "time_minutes": 60
}
```

**Response:**
```json
{
  "success": true,
  "score_added": 347,
  "total_score": 15767,
  "message": "Contributed 347 points to seed plot"
}
```

**Scoring:**
- Gold: 1 point each
- Wood/Stone: 5 points each
- Gems: 50 points each
- Kills: 2 points each
- Time: 1 point per hour

---

### Get World Tree Rankings
```
GET /api/world-tree/rankings?shard_id={shard_id}&week_number={week}
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "week_number": 2765,
  "rankings": [
    {
      "rank": 1,
      "owner_id": "123",
      "total_score": 24580,
      "promoted_to_origin": true,
      "promoted_at": "2024-12-13T00:00:00",
      "blockchain_tx_hash": "0xabc123..."
    }
  ]
}
```

**Notes:**
- Rankings calculated every Sunday midnight UTC
- Top seed plot promoted to World Tree (Chunk -1)
- Winner recorded on Ashbane blockchain

---

### Get Current Week Live Rankings
```
GET /api/world-tree/rankings/current?shard_id={shard_id}
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "rankings": [
    {
      "rank": 1,
      "chunk_id": -2,
      "owner_id": "123",
      "total_score": 15420
    }
  ]
}
```

**Notes:**
- Real-time rankings (not finalized)
- Updates as contributions come in

---

### Get Player Ranking
```
GET /api/world-tree/rankings/player/{user_id}?shard_id={shard_id}
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "ranked": true,
  "rank": 3,
  "total_score": 8940,
  "chunk_id": -1
}
```

---

### Record World Tree on Blockchain
```
POST /api/world-tree/record
Authorization: Bearer {token}
Content-Type: application/json

{
  "week_number": 2765,
  "shard_id": "default",
  "chunk_id": -1,
  "owner_id": "123",
  "total_score": 24580,
  "top_contributors": [...],
  "recorded_at": "2024-12-13T00:00:00"
}
```

**Response:**
```json
{
  "success": true,
  "record_id": 42,
  "tx_hash": "0xabc123...",
  "message": "World Tree winner recorded on blockchain"
}
```

**Notes:**
- Called automatically by server on Sunday midnight
- Records winner permanently on Ashbane L2
- Includes top 10 contributors with wallet addresses
- IPFS metadata link for detailed stats

---

## Admin Endpoints

### Grant Admin Status
```
POST /api/admin/grant?secret={ADMIN_SECRET}
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "message": "Admin status granted to {username}"
}
```

---

### Revoke Admin Status
```
POST /api/admin/revoke?secret={ADMIN_SECRET}
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "message": "Admin status revoked from {username}"
}
```

---

### Get Indexer Status
```
GET /api/admin/indexer-status
Authorization: Bearer {token}
```

**Response:**
```json
{
  "running": true,
  "last_processed_block": 12345678,
  "chain_id": 84532,
  "contract_address": "0x...",
  "platform_wallet": "0x...",
  "poll_interval_seconds": 30,
  "pending_bridge_transactions": 2
}
```

**Notes:**
- Requires admin access
- Shows transfer indexer status for bridge system monitoring

---

### Trigger Indexer Poll
```
POST /api/admin/indexer-poll
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "transfers_processed": 3
}
```

**Notes:**
- Requires admin access
- Manually triggers blockchain poll for testing
- Returns number of transfer events processed

---

## Web Pages (HTML Responses)

| Route | Description |
|-------|-------------|
| `/` | Redirects to `/login` or `/dashboard` |
| `/login` | OAuth provider selection page |
| `/dashboard` | Main dashboard with Ashbane card and providers |
| `/auth/steam/login` | Initiates Steam OAuth |
| `/auth/steam/callback` | Steam OAuth callback |
| `/auth/battlenet/login` | Initiates Battle.net OAuth |
| `/auth/battlenet/callback` | Battle.net OAuth callback |
| `/logout` | Clears session, redirects to login |
| `/demo` | Demo page for testing |

---

## Error Responses

All errors follow this format:
```json
{
  "detail": "Error message here"
}
```

| Status Code | Meaning |
|-------------|---------|
| 400 | Bad request (invalid parameters) |
| 401 | Token missing or expired - prompt re-login |
| 403 | Forbidden (not authorized) |
| 404 | Resource not found |
| 429 | Rate limited (sync cooldown) |
| 500 | Server error |
| 503 | Service unavailable (wallet service not configured) |

---

## Key Concepts

### Achievement Credits

When achievements are synced from providers, they create `AchievementCredit` records:

- **`is_original_claim = true`**: You were the first to claim this achievement. Counts toward Ashbane score and can be forged.
- **`is_original_claim = false`**: Achievement was already claimed by someone else. Display only, doesn't count toward Ashbane.

### Ashbane Score

Only original claims count toward Ashbane score. The score determines your tier (Bronze, Silver, Gold, etc.).

### Forging

Only Rare, Epic, and Legendary achievements with `is_original_claim=true` can be forged into NFTs.

### Trading (Twinking System)

Forged items are the **twinking system** for Dreadland:

- **No level requirements** - Forged items work at level 1
- **Fully tradeable** - Standard MMO trade windows + marketplace
- **5% gold tax** - Applied on trades to seller
- **24-hour cooldown** - After acquiring, before can trade again
- **Provenance tracked** - Trade history recorded (batched to chain)

See `docs/FORGE_ECONOMY_DESIGN.md` for full economy specification.

### Provenance

Every forged item tracks its history:

- **Original achievement date** - When the source achievement was earned
- **Forged date** - When the item was created
- **Forged by** - Original forger's display name
- **Trade count** - Number of times traded
- **Current owner** - Who owns it now

See `docs/FORGE_PROVENANCE_SYSTEM.md` for implementation details.

### Sync Cooldown

15-minute cooldown between syncs per provider. Admin users bypass this cooldown.

### Provider States

- **Active**: Provider is linked and functional
- **Inactive**: Provider was unlinked but can be reclaimed
- **Orphaned**: Provider account exists but user account was deleted

---

## Responsibility Matrix

| Component | Owner | Description |
|-----------|-------|-------------|
| `/api/*` endpoints | **Backend** | All API logic, database, auth |
| Token storage | **Godot** | Save to `user://ashbane_session.dat` |
| Browser auth flow | **Backend** | Login page, OAuth, success page |
| Badge rendering | **Godot** | Visual badge on player characters |
| Multiplayer badge fetch | **Godot** | Call `/api/player/{id}/badge` for other players |
| Badge caching | **Godot** | Cache badge lookups to reduce API calls |
| Profile UI | **Godot** | Display ashbane card, tier, achievements |
| Achievement sync | **Backend** | Fetch from Steam/Battle.net APIs |
| Wallet connection | **Backend** | SIWE authentication, wallet linking |
| NFT forging | **Backend** | Smart contract interaction |
| Provenance checks | **Both** | Backend provides API, Godot displays |

---

## Account Merge System

When a user tries to link a provider (Discord, GitHub, etc.) that's already linked to another Ashbane account, the system offers to **merge** the accounts instead of blocking the action.

### How It Works

1. **User A** (multi-provider account) tries to link Discord
2. Discord is already linked to **User B** (Discord-only account)
3. System shows merge confirmation page instead of error
4. If user confirms, **User B's** data is transferred to **User A**:
   - Provider accounts
   - Achievement credits
   - Forged items (current ownership)
   - Wallet accounts
   - Trade history
   - User achievements
5. **User B** is deleted after transfer

### Use Cases

- **Consolidating accounts**: Player created separate accounts with different providers, wants to combine them
- **Recovery**: Player lost access to primary account but can still log in via another provider
- **Simplification**: Player wants all their gaming data under one Ashbane account

### Merge Endpoint

```
POST /merge-confirm
Content-Type: application/x-www-form-urlencoded

other_user_id={id}&target_provider={provider}&current_user_id={id}
```

**Response (success):** Redirect to `/dashboard` with merged account

**Response (conflict):** Returns `merge_confirm.html` with conflict details if both accounts have the same provider linked

### Conflict Resolution

If both accounts have the same provider type linked (e.g., both have Steam), the merge cannot proceed automatically. User must first unlink one of the conflicting providers.

---

## Godot Autoload Expected

The game should have an `AshbaneAuth` autoload singleton with:

```gdscript
# Properties
var auth_token: String
var user_id: int
var username: String
var ashbane_tier: Dictionary  # {tier, name, color, glow, effective_score}
var is_guest: bool

# Methods
func start_login()                              # Begin device auth flow
func logout()                                   # Clear session
func refresh_profile()                          # Fetch /api/me
func get_player_badge(id: int, callback: Callable)  # Fetch other player's badge
func is_logged_in() -> bool

# Signals
signal auth_completed(user_data)
signal auth_failed(error)
signal profile_updated(profile)
```

---

## Data Flow Diagram

```
                           GAME LAUNCH
                                │
                                ▼
                 ┌──────────────────────────────┐
                 │  Load saved token from file  │
                 └──────────────────────────────┘
                                │
                 ┌──────────────┴──────────────┐
                 ▼                             ▼
         [Token exists]                  [No token]
                 │                             │
                 ▼                             ▼
        GET /api/me                    Show "Login" button
                 │                             │
      ┌─────────┴─────────┐                   │
      ▼                   ▼                   ▼
 [200 OK]            [401 Error]        Player clicks Login
      │                   │                   │
      ▼                   ▼                   ▼
Show profile         Clear token         GET /api/auth/device
Show Ashbane          Show login                │
                                               ▼
                                        Open browser
                                               │
                                               ▼
                                  Poll /api/auth/status
                                               │
                                  ┌────────────┴────────────┐
                                  ▼                         ▼
                            [success]                  [pending]
                                  │                         │
                                  ▼                         ▼
                            Save token               Wait 2s, retry
                            GET /api/me
                                  │
                                  ▼
                            Show profile
```

---

## Version

- **API Version**: 1.6
- **Last Updated**: 2024-12-17
- **Backend Status**: Complete (bridge system, indexer, trading, world tree expansion, account merge all implemented)
- **Godot Status**: Complete (Armory UI with bind/unbind/lockbox terminology, ChunkExpansionManager for world tree)

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2024-12-17 | 1.6 | Added Account Merge System: when linking a provider that's already linked to another user, system now offers to merge accounts instead of blocking. Supports Discord, GitHub, and other OAuth providers. Documented in "Account Merge System" section |
| 2024-12-13 | 1.5 | Added World Tree & Chunk Expansion endpoints: seed plot claiming, contribution tracking, weekly rankings, blockchain recording. Database migration 7e8f9a0b1c2d adds seed_plots, active_chunks, world_tree_rankings, world_tree_contributions tables |
| 2024-12-10 | 1.4 | Updated status to reflect complete implementation. Note: Godot UI uses "bind/unbind" instead of "bridge" and "lockbox" instead of "wallet" for RPG-friendly terminology |
| 2024-12-09 | 1.3 | Added Bridge System endpoints (bridge-out, bridge-in, status), updated forge-status with bridge information, added BridgeStatus enum and BridgeTransaction table |
| 2024-12-08 | 1.2 | Added Trading & Economy endpoints, expanded provenance response, added census endpoint, documented twinking system and provenance concepts |
| 2024-12-06 | 1.1 | Added wallet/forging endpoints, admin endpoints, sync cooldown, achievements by rarity endpoint, provider states |
| 2024-12-05 | 1.0 | Initial API contract |
