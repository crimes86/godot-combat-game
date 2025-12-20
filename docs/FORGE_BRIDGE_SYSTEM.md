# Forge Bridge System

Technical specification for bridging forged items between in-game inventory and external wallets (OpenSea, etc.).

---

## Overview

The bridge system allows items to move between two states:
1. **In-Game** - Item in platform custody, usable in Dreadland, tradeable via in-game trade windows
2. **Bridged Out** - Item in user's external wallet, NOT usable in-game, tradeable on OpenSea/etc.

**Key Principle**: Traditional gamers never see this system. It's opt-in for crypto-aware users who want external marketplace access.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Ashbane DATABASE                                │
│                    (Source of truth for gameplay)                       │
│                                                                         │
│   forged_achievements:                                                  │
│   ├── owner_user_id (who can use it in-game)                           │
│   ├── bridge_status (in_game | bridging_out | bridged | bridging_in)   │
│   ├── bridge_requested_at (for 48h cooldown)                           │
│   └── external_owner_wallet (if bridged, who holds it)                 │
└─────────────────────────────────────────────────────────────────────────┘
                              │
           ┌──────────────────┼──────────────────┐
           ▼                  ▼                  ▼
    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
    │   GODOT     │    │   INDEXER   │    │  BLOCKCHAIN │
    │   CLIENT    │    │   SERVICE   │    │   (Base)    │
    │             │    │             │    │             │
    │ Reads from  │    │ Watches for │    │ NFT storage │
    │ database    │    │ transfers   │    │ & ownership │
    └─────────────┘    └─────────────┘    └─────────────┘
```

---

## States

### Bridge Status Enum

```python
class BridgeStatus(str, Enum):
    IN_GAME = "in_game"           # In platform wallet, usable in Dreadland
    BRIDGING_OUT = "bridging_out" # Cooldown period (48h), not tradeable
    BRIDGED = "bridged"           # In external wallet, not usable in-game
    BRIDGING_IN = "bridging_in"   # Being transferred back to platform
```

### State Transitions

```
                    ┌─────────────┐
                    │  IN_GAME    │◄────────────────────┐
                    │  (default)  │                     │
                    └──────┬──────┘                     │
                           │                            │
                    User requests                Bridge in
                    bridge out                   completes
                           │                            │
                           ▼                            │
                    ┌─────────────┐                     │
                    │ BRIDGING_   │                     │
                    │ OUT (48h)   │                     │
                    └──────┬──────┘                     │
                           │                            │
                    Cooldown                            │
                    expires +                           │
                    transfer                            │
                           │                            │
                           ▼                            │
                    ┌─────────────┐              ┌──────┴──────┐
                    │  BRIDGED    │──────────────│ BRIDGING_   │
                    │ (external)  │  User links  │ IN          │
                    └──────┬──────┘  wallet &    └─────────────┘
                           │        requests
                           │        bridge in
                    External
                    transfer
                    detected
                           │
                           ▼
                    ┌─────────────┐
                    │  BRIDGED    │
                    │ (new owner) │
                    └─────────────┘
```

---

## Database Schema Changes

### ForgedAchievement Updates

```python
class ForgedAchievement(Base):
    # ... existing fields ...

    # Ownership tracking (NEW)
    owner_user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    owner_since = Column(DateTime, default=datetime.utcnow)
    trade_count = Column(Integer, default=0)

    # Bridge state (NEW)
    bridge_status = Column(String(20), default='in_game')  # in_game, bridging_out, bridged, bridging_in
    bridge_requested_at = Column(DateTime, nullable=True)  # When bridge-out was requested
    bridge_completed_at = Column(DateTime, nullable=True)  # When bridge completed
    external_owner_wallet = Column(String(42), nullable=True)  # Wallet holding item if bridged

    # In-game claim tracking (existing, renamed for clarity)
    claimed_in_game_at = Column(DateTime, nullable=True)  # When added to inventory

    # Indexes
    __table_args__ = (
        Index('idx_owner_user', 'owner_user_id'),
        Index('idx_bridge_status', 'bridge_status'),
        Index('idx_external_wallet', 'external_owner_wallet'),
    )
```

### New Table: BridgeTransactions

```python
class BridgeTransaction(Base):
    """Tracks all bridge operations for audit/debugging."""
    __tablename__ = 'bridge_transactions'

    id = Column(Integer, primary_key=True)
    forged_achievement_id = Column(Integer, ForeignKey('forged_achievements.id'))

    transaction_type = Column(String(20))  # 'bridge_out', 'bridge_in', 'external_transfer'
    from_user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    to_user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    from_wallet = Column(String(42), nullable=True)
    to_wallet = Column(String(42), nullable=True)

    tx_hash = Column(String(66), nullable=True)  # Blockchain transaction hash

    requested_at = Column(DateTime, default=datetime.utcnow)
    completed_at = Column(DateTime, nullable=True)
    status = Column(String(20), default='pending')  # pending, completed, failed, cancelled

    error_message = Column(Text, nullable=True)
```

---

## API Endpoints

### Bridge Out Flow

#### 1. Request Bridge Out
```
POST /api/wallet/bridge-out
Authorization: Bearer <token>
Content-Type: application/json

{
    "forged_achievement_ids": [1, 2, 3],
    "destination_wallet": "0x..."  // Optional, defaults to linked wallet
}

Response 200:
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

Response 400:
{
    "error": "Items must be claimed to inventory before bridging"
}
```

#### 2. Check Bridge Out Status
```
GET /api/wallet/bridge-out/status
Authorization: Bearer <token>

Response 200:
{
    "pending_bridges": [
        {
            "forged_achievement_id": 1,
            "item_name": "Hand of Malenia",
            "status": "bridging_out",
            "requested_at": "2024-12-15T10:30:00Z",
            "cooldown_ends_at": "2024-12-17T10:30:00Z",
            "hours_remaining": 23.5,
            "can_confirm": false
        }
    ]
}
```

#### 3. Confirm Bridge Out (after cooldown)
```
POST /api/wallet/bridge-out/confirm
Authorization: Bearer <token>
Content-Type: application/json

{
    "forged_achievement_ids": [1]
}

Response 200:
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
    ]
}
```

#### 4. Cancel Bridge Out (before cooldown ends)
```
POST /api/wallet/bridge-out/cancel
Authorization: Bearer <token>
Content-Type: application/json

{
    "forged_achievement_ids": [1]
}

Response 200:
{
    "success": true,
    "cancelled": [1]
}
```

### Bridge In Flow

#### 1. Scan Wallet for Bridgeable Items
```
GET /api/wallet/bridge-in/available
Authorization: Bearer <token>

Response 200:
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
    ],
    "not_owned": [
        {
            "token_id": 12345,
            "reason": "Token not owned by connected wallet"
        }
    ]
}
```

#### 2. Request Bridge In
```
POST /api/wallet/bridge-in
Authorization: Bearer <token>
Content-Type: application/json

{
    "token_ids": [42069]
}

Response 200:
{
    "success": true,
    "bridged_in": [
        {
            "token_id": 42069,
            "item_name": "Hand of Malenia",
            "status": "in_game",
            "tx_hash": "0x..."
        }
    ]
}
```

---

## Indexer Service

Background service that watches for on-chain transfers and updates the database.

### Configuration

```python
# config.py
INDEXER_CONFIG = {
    "chain_id": 8453,  # Base mainnet
    "contract_address": "0x...",
    "poll_interval_seconds": 30,
    "batch_size": 1000,  # Max events per poll
    "start_block": "latest",  # Or specific block number
}
```

### Core Logic

```python
# services/indexer_service.py

class TransferIndexer:
    """Watches blockchain for ForgedItem transfers and updates database."""

    def __init__(self, db_session, web3_provider, contract_address):
        self.db = db_session
        self.w3 = web3_provider
        self.contract = self.w3.eth.contract(
            address=contract_address,
            abi=FORGED_ITEMS_ABI
        )
        self.last_processed_block = self._get_last_processed_block()

    async def poll_transfers(self):
        """Poll for new Transfer events."""
        current_block = self.w3.eth.block_number

        if current_block <= self.last_processed_block:
            return

        # Get Transfer events
        transfer_filter = self.contract.events.Transfer.create_filter(
            fromBlock=self.last_processed_block + 1,
            toBlock=current_block
        )

        events = transfer_filter.get_all_entries()

        for event in events:
            await self._process_transfer(event)

        self._update_last_processed_block(current_block)

    async def _process_transfer(self, event):
        """Process a single Transfer event."""
        token_id = event.args.tokenId
        from_address = event.args['from'].lower()
        to_address = event.args['to'].lower()
        tx_hash = event.transactionHash.hex()

        # Find the forged item
        item = self.db.query(ForgedAchievement).filter(
            ForgedAchievement.token_id == token_id
        ).first()

        if not item:
            logger.warning(f"Transfer for unknown token {token_id}")
            return

        # Check if this is a platform wallet transfer (internal)
        if self._is_platform_wallet(from_address) or self._is_platform_wallet(to_address):
            # Internal transfer (bridge in/out), handled by API
            return

        # External transfer (OpenSea sale, direct transfer, etc.)
        await self._handle_external_transfer(item, from_address, to_address, tx_hash)

    async def _handle_external_transfer(self, item, from_wallet, to_wallet, tx_hash):
        """Handle transfer between external wallets."""

        # Find new owner by wallet
        new_owner_wallet = self.db.query(WalletAccount).filter(
            WalletAccount.wallet_address == to_wallet
        ).first()

        old_owner_id = item.owner_user_id

        if new_owner_wallet:
            # New owner has a Dreadland account
            item.owner_user_id = new_owner_wallet.user_id
            item.bridge_status = 'bridged'  # Still bridged until they bridge in
            item.external_owner_wallet = to_wallet
            item.owner_since = datetime.utcnow()
            item.trade_count += 1
            item.claimed_in_game_at = None  # Must re-claim after bridge in
        else:
            # New owner is external-only
            item.owner_user_id = None
            item.bridge_status = 'bridged'
            item.external_owner_wallet = to_wallet
            item.trade_count += 1

        # Log the transfer
        bridge_tx = BridgeTransaction(
            forged_achievement_id=item.id,
            transaction_type='external_transfer',
            from_user_id=old_owner_id,
            to_user_id=new_owner_wallet.user_id if new_owner_wallet else None,
            from_wallet=from_wallet,
            to_wallet=to_wallet,
            tx_hash=tx_hash,
            completed_at=datetime.utcnow(),
            status='completed'
        )
        self.db.add(bridge_tx)
        self.db.commit()

        logger.info(f"External transfer detected: token {item.token_id} from {from_wallet} to {to_wallet}")
```

### Running the Indexer

```python
# Can run as:
# 1. Background thread in FastAPI
# 2. Separate process (recommended for production)
# 3. Celery task

async def run_indexer():
    """Main indexer loop."""
    indexer = TransferIndexer(
        db_session=SessionLocal(),
        web3_provider=Web3(Web3.HTTPProvider(RPC_URL)),
        contract_address=CONTRACT_ADDRESS
    )

    while True:
        try:
            await indexer.poll_transfers()
        except Exception as e:
            logger.error(f"Indexer error: {e}")

        await asyncio.sleep(POLL_INTERVAL)
```

---

## Godot Integration

### Settings UI Addition

```gdscript
# In Armory.gd or separate BridgeUI.gd

func _build_bridge_section() -> Control:
    """Build the Bridge In/Out section for Settings."""
    var vbox = VBoxContainer.new()

    # Header
    var header = Label.new()
    header.text = "EXTERNAL WALLET"
    header.add_theme_font_size_override("font_size", 14)
    vbox.add_child(header)

    # Description
    var desc = Label.new()
    desc.text = "Transfer items to your external wallet to trade on OpenSea.\nItems cannot be used in-game while bridged out."
    desc.add_theme_font_size_override("font_size", 10)
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vbox.add_child(desc)

    # Bridge Out button
    var bridge_out_btn = Button.new()
    bridge_out_btn.text = "BRIDGE OUT"
    bridge_out_btn.pressed.connect(_on_bridge_out_pressed)
    vbox.add_child(bridge_out_btn)

    # Bridge In button
    var bridge_in_btn = Button.new()
    bridge_in_btn.text = "BRIDGE IN"
    bridge_in_btn.pressed.connect(_on_bridge_in_pressed)
    vbox.add_child(bridge_in_btn)

    return vbox
```

### ForgeItemManager Updates

```gdscript
# In ForgeItemManager.gd

# Bridge status enum
enum BridgeStatus { IN_GAME, BRIDGING_OUT, BRIDGED, BRIDGING_IN }

func request_bridge_out(item_ids: Array, callback: Callable) -> void:
    """Request to bridge items out to external wallet."""
    var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-out"
    var body = JSON.stringify({"forged_achievement_ids": item_ids})
    # ... HTTP request logic

func get_bridge_status(callback: Callable) -> void:
    """Get status of pending bridge operations."""
    var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-out/status"
    # ... HTTP request logic

func confirm_bridge_out(item_ids: Array, callback: Callable) -> void:
    """Confirm bridge out after cooldown."""
    var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-out/confirm"
    # ... HTTP request logic

func get_bridge_in_available(callback: Callable) -> void:
    """Scan wallet for items that can be bridged in."""
    var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-in/available"
    # ... HTTP request logic

func request_bridge_in(token_ids: Array, callback: Callable) -> void:
    """Bridge items from external wallet to game."""
    var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-in"
    # ... HTTP request logic
```

---

## User Flows

### Flow 1: Bridge Out (Game → OpenSea)

```
1. User opens Settings → External Wallet
2. User clicks "Bridge Out"
3. UI shows their in-game forged items
4. User selects items to bridge
5. User confirms (48h cooldown starts)
6. Items marked as "Bridging Out" in inventory (greyed out, unusable)
7. After 48h, user clicks "Confirm Bridge"
8. Platform wallet transfers NFTs to user's external wallet
9. Items removed from in-game inventory
10. User can now list on OpenSea
```

### Flow 2: Bridge In (OpenSea → Game)

```
1. User buys item on OpenSea (item lands in their wallet)
2. User opens Dreadland, goes to Settings → External Wallet
3. User clicks "Bridge In"
4. System scans their wallet for Dreadland items
5. User sees list of bridgeable items
6. User selects items to bridge in
7. User approves transfer to platform wallet (signs transaction)
8. Items transferred to platform wallet
9. Items appear in user's Forge catalog as "CLAIM"
10. User claims to inventory
```

### Flow 3: External Transfer Detection

```
1. Player A lists item on OpenSea
2. Player B (also has Dreadland account) buys it
3. Indexer detects Transfer event
4. Database updated: owner_user_id = Player B
5. Player B logs into Dreadland
6. Item appears in their Forge catalog (bridge_status = 'bridged')
7. Player B clicks "Bridge In" → item moves to their inventory
```

---

## Security Considerations

### Anti-Exploit Measures

1. **48h Cooldown on Bridge Out**
   - Prevents rapid flipping between game and OpenSea
   - Gives time to detect stolen accounts

2. **Bridge Requests Logged**
   - All bridge operations tracked in bridge_transactions
   - Audit trail for disputes

3. **Items Unusable While Bridging**
   - Can't use/trade items during bridge_out cooldown
   - Prevents duplication exploits

4. **Wallet Verification**
   - SIWE signature required for wallet linking
   - Can't bridge to unverified wallet

### Recovery Scenarios

**Scenario: Account Compromised**
```
1. Attacker bridges out items
2. User reports to support within 48h
3. Support cancels pending bridge
4. Items remain in-game
```

**Scenario: Items Sold on OpenSea**
```
1. Items are legitimately sold
2. Indexer updates ownership
3. Provenance shows "External Marketplace Trade"
4. No recovery - sale was valid
```

---

## Implementation Phases

### Phase 1: Database & Core ✅ COMPLETE
- [x] Add bridge columns to ForgedAchievement (`bridge_status`, `bridge_requested_at`, `bridge_completed_at`, `external_owner_wallet`)
- [x] Create BridgeTransaction table
- [x] Write migration (`3a7f8b2c1e9d_add_bridge_system_tables.py`)
- [x] Add BridgeStatus enum

### Phase 2: API Endpoints ✅ COMPLETE
- [x] Bridge out request/status/confirm/cancel (`/api/wallet/bridge-out/*`)
- [x] Bridge in scan/request (`/api/wallet/bridge-in/*`)
- [x] Update forge-status to include bridge information

### Phase 3: Indexer Service ✅ COMPLETE
- [x] Transfer event listener (`transfer_indexer_service.py`)
- [x] Database sync logic (external transfer detection)
- [x] Error handling/retry with state persistence
- [x] Admin endpoints for monitoring (`/api/admin/indexer-status`, `/api/admin/indexer-poll`)

### Phase 4: Godot UI ✅ COMPLETE
- [x] Armory → BINDING section (replaces "External Wallet")
- [x] Unbind button (UI says "UNBIND", API uses `bridge-out`)
- [x] Bind button (UI says "BIND", API uses `bridge-in`)
- [x] Status indicators on unbound items ("BOX" badge, countdown timers)
- [x] Lockbox connection UI (UI says "lockbox", API uses `wallet`)

> **UI Terminology Note (Dec 2024):**
> The Godot UI uses RPG-friendly terminology instead of crypto terms:
> - "bridge out" → "unbind" (unbind from character)
> - "bridge in" → "bind" (bind to character)
> - "wallet" → "lockbox" (personal secure storage)
> - "EXT" badge → "BOX" badge (item in lockbox)
>
> The API endpoints retain the original `bridge-out`, `bridge-in`, `wallet` naming for stability.

---

## Key Files

| File | Purpose |
|------|---------|
| `app/models.py` | BridgeStatus enum, BridgeTransaction table, ForgedAchievement bridge columns |
| `app/routes/wallet_routes.py` | Bridge API endpoints |
| `app/services/transfer_indexer_service.py` | Blockchain event indexer |
| `app/services/wallet_service.py` | Transfer functions (`transfer_to_external`, `transfer_from_external`) |
| `alembic/versions/3a7f8b2c1e9d_*.py` | Database migration |

## Environment Variables

```bash
# Required for bridge system
PLATFORM_WALLET_ADDRESS=0x...   # Platform custody wallet address
PLATFORM_WALLET_KEY=0x...       # Platform wallet private key (for transfers)

# Indexer configuration
INDEXER_POLL_INTERVAL=30        # Seconds between polls (default: 30)
INDEXER_MAX_BLOCKS=1000         # Max blocks per poll (default: 1000)
INDEXER_START_BLOCK=latest      # Start block or "latest"
```

---

## Related Documents

- `FORGE_PROVENANCE_SYSTEM.md` - Blockchain architecture
- `FORGE_ECONOMY_DESIGN.md` - Trading philosophy
- `GOLDEN_RULES.md` - Rule #6: Blockchain Is Invisible
- `API_CONTRACT.md` - Full API documentation

---

## Version History

| Date | Change |
|------|--------|
| Dec 2024 | Initial specification |
| Dec 2024 | Phase 1-3 implemented (database, API, indexer) |
| Dec 2024 | Phase 4 complete - Godot UI with bind/unbind/lockbox terminology |
