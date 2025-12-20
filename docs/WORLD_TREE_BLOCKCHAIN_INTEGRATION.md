# World Tree Blockchain Integration

## Overview

World Tree winners are **permanently recorded on-chain** via the Ashbane blockchain, creating an immutable historical record and enabling future NFT/governance features.

```
Game Server                Ashbane Backend              Ashbane Blockchain
┌──────────┐              ┌──────────┐                ┌──────────────┐
│  World   │  HTTP POST   │  Record  │  Smart         │  World Tree  │
│  Tree    │ ───────────> │  World   │  Contract ───> │  Registry    │
│  Ranking │              │  Tree    │  Call          │  Contract    │
│  System  │              │  Winner  │                │              │
└──────────┘              └──────────┘                └──────────────┘
     │                         │                            │
     │                         │                            ▼
     │                         │                     ┌──────────────┐
     │                         │                     │ Immutable    │
     │                         │                     │ World Tree   │
     │                         │                     │ History      │
     │                         │                     └──────────────┘
     │                         │
     ▼                         ▼
On-Chain Verification    NFT Minting (Future)
Achievement Unlock       Governance Tokens
```

---

## What Gets Logged On-Chain

### World Tree Record Structure

**Blockchain Storage** (immutable):
```solidity
struct WorldTreeRecord {
    uint256 recordId;           // Unique record ID
    uint256 weekNumber;         // ISO week number
    uint256 startTimestamp;     // Week start (Unix)
    uint256 endTimestamp;       // Week end (Unix)
    string shardId;             // Shard identifier
    int256 chunkId;             // Winning chunk ID
    string ownerId;             // Owner player/guild ID
    uint256 totalScore;         // Final contribution score
    address[] topContributors;  // Top 10 contributor wallet addresses
    uint256[] contributorScores;// Top 10 contribution amounts
    string metadataUri;         // IPFS link to full record JSON
}
```

**IPFS Metadata** (detailed stats):
```json
{
  "recordId": 123,
  "weekNumber": 45,
  "period": {
    "start": "2024-11-05T00:00:00Z",
    "end": "2024-11-12T00:00:00Z"
  },
  "shard": "us-west-1",
  "winner": {
    "chunkId": -2,
    "ownerId": "player123",
    "ownerAddress": "0x1234...",
    "ownerType": "guild",
    "guildName": "Phoenix Rising",
    "totalScore": 45600
  },
  "topContributors": [
    {
      "rank": 1,
      "playerId": "player456",
      "address": "0x5678...",
      "score": 12000,
      "contributions": {
        "gold": 8000,
        "materials": 2000,
        "kills": 1000,
        "time": 1000
      }
    }
    // ... top 10
  ],
  "statistics": {
    "totalContributors": 47,
    "totalContributions": 256,
    "averageScore": 970,
    "competingTrees": 12
  }
}
```

---

## Smart Contract

### World Tree Registry Contract (Ashbane L2)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract WorldTreeRegistry {
    struct WorldTreeRecord {
        uint256 recordId;
        uint256 weekNumber;
        uint256 startTimestamp;
        uint256 endTimestamp;
        string shardId;
        int256 chunkId;
        string ownerId;
        uint256 totalScore;
        address[] topContributors;
        uint256[] contributorScores;
        string metadataUri;
    }

    // Storage
    mapping(uint256 => WorldTreeRecord) public records;
    uint256 public recordCount;

    // Events
    event WorldTreeRecorded(
        uint256 indexed recordId,
        uint256 indexed weekNumber,
        string ownerId,
        uint256 totalScore
    );

    event ContributorRecorded(
        uint256 indexed recordId,
        address indexed contributor,
        uint256 score
    );

    // Modifiers
    modifier onlyGameServer() {
        // Only allow calls from authorized game server backend
        require(
            msg.sender == gameServerAddress,
            "Only game server can record"
        );
        _;
    }

    address public gameServerAddress;

    constructor(address _gameServerAddress) {
        gameServerAddress = _gameServerAddress;
    }

    /**
     * @dev Record a new World Tree winner
     */
    function recordWorldTree(
        uint256 weekNumber,
        uint256 startTimestamp,
        uint256 endTimestamp,
        string memory shardId,
        int256 chunkId,
        string memory ownerId,
        uint256 totalScore,
        address[] memory topContributors,
        uint256[] memory contributorScores,
        string memory metadataUri
    ) external onlyGameServer returns (uint256) {
        require(
            topContributors.length == contributorScores.length,
            "Contributor arrays must match"
        );
        require(
            topContributors.length <= 10,
            "Max 10 contributors"
        );

        uint256 recordId = recordCount++;

        WorldTreeRecord storage record = records[recordId];
        record.recordId = recordId;
        record.weekNumber = weekNumber;
        record.startTimestamp = startTimestamp;
        record.endTimestamp = endTimestamp;
        record.shardId = shardId;
        record.chunkId = chunkId;
        record.ownerId = ownerId;
        record.totalScore = totalScore;
        record.topContributors = topContributors;
        record.contributorScores = contributorScores;
        record.metadataUri = metadataUri;

        emit WorldTreeRecorded(recordId, weekNumber, ownerId, totalScore);

        // Emit contributor events
        for (uint i = 0; i < topContributors.length; i++) {
            emit ContributorRecorded(recordId, topContributors[i], contributorScores[i]);
        }

        return recordId;
    }

    /**
     * @dev Get full record by ID
     */
    function getRecord(uint256 recordId) external view returns (WorldTreeRecord memory) {
        return records[recordId];
    }

    /**
     * @dev Get records by week number
     */
    function getRecordsByWeek(uint256 weekNumber) external view returns (uint256[] memory) {
        uint256[] memory matches = new uint256[](recordCount);
        uint256 matchCount = 0;

        for (uint256 i = 0; i < recordCount; i++) {
            if (records[i].weekNumber == weekNumber) {
                matches[matchCount] = i;
                matchCount++;
            }
        }

        // Resize array to actual match count
        uint256[] memory result = new uint256[](matchCount);
        for (uint256 i = 0; i < matchCount; i++) {
            result[i] = matches[i];
        }

        return result;
    }

    /**
     * @dev Get records by owner
     */
    function getRecordsByOwner(string memory ownerId) external view returns (uint256[] memory) {
        uint256[] memory matches = new uint256[](recordCount);
        uint256 matchCount = 0;

        for (uint256 i = 0; i < recordCount; i++) {
            if (keccak256(bytes(records[i].ownerId)) == keccak256(bytes(ownerId))) {
                matches[matchCount] = i;
                matchCount++;
            }
        }

        // Resize array
        uint256[] memory result = new uint256[](matchCount);
        for (uint256 i = 0; i < matchCount; i++) {
            result[i] = matches[i];
        }

        return result;
    }

    /**
     * @dev Check if player contributed to a winning tree
     */
    function hasContributed(address contributor) external view returns (bool) {
        for (uint256 i = 0; i < recordCount; i++) {
            for (uint256 j = 0; j < records[i].topContributors.length; j++) {
                if (records[i].topContributors[j] == contributor) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * @dev Update game server address (admin only)
     */
    function updateGameServer(address newAddress) external {
        require(msg.sender == gameServerAddress, "Only current server");
        gameServerAddress = newAddress;
    }
}
```

---

## Backend API Integration

### Ashbane Backend Endpoints

**New Endpoint: `POST /api/world-tree/record`**

```python
# backend/app/routes/world_tree.py
from fastapi import APIRouter, HTTPException, Depends
from web3 import Web3
from app.blockchain import Ashbane_client
from app.models import WorldTreeRecord

router = APIRouter(prefix="/api/world-tree", tags=["world-tree"])

@router.post("/record")
async def record_world_tree(
    record: WorldTreeRecord,
    api_key: str = Depends(verify_game_server_key)
):
    """
    Record World Tree winner on-chain.
    Called by game server after weekly ranking calculation.
    """

    # Upload metadata to IPFS
    metadata_uri = await upload_to_ipfs(record.to_metadata_json())

    # Prepare contract call
    contract = Ashbane_client.get_contract("WorldTreeRegistry")

    try:
        # Call smart contract
        tx_hash = contract.functions.recordWorldTree(
            weekNumber=record.week_number,
            startTimestamp=record.start_timestamp,
            endTimestamp=record.end_timestamp,
            shardId=record.shard_id,
            chunkId=record.chunk_id,
            ownerId=record.owner_id,
            totalScore=record.total_score,
            topContributors=[c.address for c in record.top_contributors],
            contributorScores=[c.score for c in record.top_contributors],
            metadataUri=metadata_uri
        ).transact()

        # Wait for confirmation
        receipt = Ashbane_client.wait_for_transaction(tx_hash)

        # Extract record ID from event logs
        record_id = contract.events.WorldTreeRecorded().processReceipt(receipt)[0]['args']['recordId']

        return {
            "success": True,
            "record_id": record_id,
            "tx_hash": tx_hash.hex(),
            "metadata_uri": metadata_uri,
            "block_number": receipt.blockNumber
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Blockchain error: {str(e)}")


@router.get("/records/{owner_id}")
async def get_owner_records(owner_id: str):
    """Get all World Tree wins for a player/guild"""
    contract = Ashbane_client.get_contract("WorldTreeRegistry")
    record_ids = contract.functions.getRecordsByOwner(owner_id).call()

    records = []
    for record_id in record_ids:
        record = contract.functions.getRecord(record_id).call()
        records.append(parse_contract_record(record))

    return {"records": records}


@router.get("/verify/{record_id}")
async def verify_record(record_id: int):
    """Verify a World Tree record exists on-chain"""
    contract = Ashbane_client.get_contract("WorldTreeRegistry")

    try:
        record = contract.functions.getRecord(record_id).call()
        return {
            "verified": True,
            "record": parse_contract_record(record)
        }
    except:
        return {"verified": False}
```

---

## Game Server Integration

### Update `ChunkExpansionManager.gd`

```gdscript
# Add to ChunkExpansionManager.gd

func recalculate_world_tree() -> void:
    """Recalculate World Tree winner and promote"""
    print("🌳 Recalculating World Tree rankings...")

    # ... existing ranking calculation ...

    var winner = eligible_trees[0]

    # Promote winner
    if winner.chunk_id != current_world_tree:
        promote_world_tree(winner)
    else:
        print("🌳 Current World Tree retained position")

    # Save to history
    save_world_tree_history(winner)

    # 🔗 NEW: Record on blockchain
    record_world_tree_on_chain(winner, eligible_trees)

    # Reset weekly scores
    reset_weekly_scores()

    # Broadcast results
    _broadcast_world_tree_rankings.rpc(eligible_trees)


func record_world_tree_on_chain(winner: Dictionary, all_trees: Array) -> void:
    """Record World Tree winner to Ashbane blockchain via backend API"""

    var db = DatabaseManager

    # Get top 10 contributors with wallet addresses
    var top_contributors = db.query("""
        SELECT
            tc.player_id,
            p.wallet_address,
            SUM(tc.points) as total_points
        FROM tree_contributions tc
        JOIN players p ON tc.player_id = p.username
        WHERE tc.chunk_id = ?
          AND tc.week_number = ?
          AND p.wallet_address IS NOT NULL
        GROUP BY tc.player_id
        ORDER BY total_points DESC
        LIMIT 10
    """, [winner.chunk_id, get_current_week()])

    # Get winner's wallet address
    var winner_address = db.query_single(
        "SELECT wallet_address FROM players WHERE username = ?",
        [winner.owner_id]
    ).wallet_address

    if not winner_address:
        print("⚠️ Winner has no wallet address - skipping blockchain record")
        return

    # Prepare payload
    var now = Time.get_unix_time_from_system()
    var week_start = now - (7 * 24 * 60 * 60)

    var payload = {
        "week_number": get_current_week(),
        "start_timestamp": week_start,
        "end_timestamp": now,
        "shard_id": db.get_shard_id(),
        "chunk_id": winner.chunk_id,
        "owner_id": winner.owner_id,
        "owner_address": winner_address,
        "total_score": winner.weekly_score,
        "top_contributors": [],
        "statistics": {
            "total_contributors": winner.contributor_count,
            "competing_trees": all_trees.size()
        }
    }

    # Add contributors
    for contributor in top_contributors:
        payload.top_contributors.append({
            "player_id": contributor.player_id,
            "address": contributor.wallet_address,
            "score": contributor.total_points
        })

    # Send to Ashbane backend
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(_on_blockchain_record_complete)

    var headers = [
        "Content-Type: application/json",
        "X-Game-Server-Key: %s" % AshbaneAuth.get_server_api_key()
    ]

    var url = "%s/api/world-tree/record" % AshbaneAuth.backend_url
    var json = JSON.stringify(payload)

    print("🔗 Recording World Tree to blockchain...")
    http.request(url, headers, HTTPClient.METHOD_POST, json)


func _on_blockchain_record_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    """Handle blockchain record response"""

    if response_code != 200:
        print("❌ Blockchain record failed: HTTP %d" % response_code)
        return

    var json = JSON.parse_string(body.get_string_from_utf8())

    if json and json.success:
        var record_id = json.record_id
        var tx_hash = json.tx_hash

        print("✅ World Tree recorded on-chain!")
        print("   Record ID: %d" % record_id)
        print("   TX Hash: %s" % tx_hash)
        print("   Block: %d" % json.block_number)

        # Broadcast on-chain confirmation to all players
        _broadcast_blockchain_confirmation.rpc(record_id, tx_hash)

        # Store record ID in database for future reference
        var db = DatabaseManager
        db.execute("""
            UPDATE world_tree_history
            SET blockchain_record_id = ?,
                blockchain_tx_hash = ?
            WHERE week_start = ?
        """, [record_id, tx_hash, Time.get_unix_time_from_system() - (7 * 24 * 60 * 60)])
    else:
        print("❌ Blockchain record failed: %s" % json.get("error", "Unknown error"))


@rpc("authority", "call_local")
func _broadcast_blockchain_confirmation(record_id: int, tx_hash: String) -> void:
    """Broadcast blockchain confirmation to all players"""
    print("🔗 World Tree permanently recorded on Ashbane blockchain!")
    print("   Record ID: %d" % record_id)
    print("   View on explorer: https://explorer.Ashbane.xyz/tx/%s" % tx_hash)
```

---

## Database Schema Updates

**Update `world_tree_history` table**:
```sql
ALTER TABLE world_tree_history ADD COLUMN blockchain_record_id INTEGER;
ALTER TABLE world_tree_history ADD COLUMN blockchain_tx_hash TEXT;
ALTER TABLE world_tree_history ADD COLUMN blockchain_confirmed BOOLEAN DEFAULT 0;

CREATE INDEX idx_blockchain_record ON world_tree_history(blockchain_record_id);
```

**Update `players` table** (if not already present):
```sql
ALTER TABLE players ADD COLUMN wallet_address TEXT UNIQUE;
CREATE INDEX idx_wallet_address ON players(wallet_address);
```

---

## Player Wallet Integration

### Linking Wallet to Account

**UI Flow**:
1. Player goes to Settings → Blockchain
2. Clicks "Link Wallet"
3. MetaMask/WalletConnect prompts for signature
4. Backend verifies signature and stores address

**Backend Endpoint**:
```python
@router.post("/api/players/link-wallet")
async def link_wallet(
    username: str,
    wallet_address: str,
    signature: str
):
    """
    Link a wallet address to player account.
    Signature proves ownership of wallet.
    """

    # Verify signature
    message = f"Link wallet {wallet_address} to {username}"
    recovered_address = recover_signer(message, signature)

    if recovered_address.lower() != wallet_address.lower():
        raise HTTPException(400, "Invalid signature")

    # Store in database
    db.execute(
        "UPDATE players SET wallet_address = ? WHERE username = ?",
        [wallet_address, username]
    )

    return {"success": True, "wallet_address": wallet_address}
```

---

## Benefits of Blockchain Integration

### For Players

1. **Permanent Prestige**:
   - Wins recorded forever on immutable blockchain
   - Can prove achievements to anyone
   - Viewable on blockchain explorers

2. **Portable Achievements**:
   - Achievements tied to wallet, not just account
   - Can showcase across platforms
   - Verifiable proof of skill/contribution

3. **Future NFT Rewards**:
   - World Tree winners could receive commemorative NFTs
   - Top contributors get special NFT badges
   - Tradeable on NFT marketplaces

4. **Governance Participation**:
   - Blockchain records enable voting power
   - Winners get governance tokens
   - Influence future game development

### For Game

1. **Anti-Cheat**:
   - On-chain records are tamper-proof
   - Easy to detect manipulation
   - Transparent verification

2. **Cross-Shard Recognition**:
   - Winners visible across all shards
   - Global leaderboard possible
   - Cross-shard competitions

3. **Marketing**:
   - "Play to Earn" narrative
   - Blockchain gaming community interest
   - Verifiable competitive integrity

---

## In-Game Integration Points

### World Tree Monument UI

```gdscript
# When player interacts with World Tree
func show_world_tree_info():
    var ui = WorldTreeInfoPanel.new()

    # Show current winner
    ui.display_current_winner(current_world_tree_owner)

    # Show blockchain verification
    var record_id = get_blockchain_record_id()
    ui.display_blockchain_link(record_id)

    # "View on Blockchain" button
    ui.add_explorer_button(record_id)
```

**Explorer Button**:
```gdscript
func _on_explorer_button_pressed():
    var url = "https://explorer.Ashbane.xyz/tx/%s" % tx_hash
    OS.shell_open(url)
```

### Achievement Notifications

```
🌳 NEW WORLD TREE RECORDED! 🌳

Owner: PhoenixGuild
Score: 45,600 points
Week: 45 (Nov 5-12, 2024)

🔗 Permanently recorded on Ashbane blockchain
Record ID: #123
TX: 0xabcd...1234

[View on Explorer] [Share Achievement]
```

---

## Admin Commands

```gdscript
# Admin can manually trigger blockchain recording
/worldtree record           # Record current winner on-chain
/worldtree verify 123       # Verify record #123 on-chain
/worldtree history player123 # Show player's blockchain records
```

---

## Gas Costs & Optimization

**Estimated Gas Cost** (Ashbane L2):
- Record transaction: ~0.001 MNT ($0.0005)
- Query (read-only): Free

**Who Pays**:
- Game server pays gas fees
- Winners/contributors pay nothing
- Included in server operating costs

**Batch Optimization**:
```gdscript
# Record multiple shards in single transaction
func batch_record_world_trees(shard_records: Array):
    # Call contract batch function
    contract.recordMultipleWorldTrees(shard_records)
```

---

## Security Considerations

1. **Server Key Protection**:
   - Game server private key stored in secure environment variable
   - Never exposed to clients
   - Rotated periodically

2. **Signature Verification**:
   - All wallet links require signature proof
   - Prevents account hijacking
   - Expires after 5 minutes

3. **Rate Limiting**:
   - Max 1 blockchain record per week per shard
   - Prevents spam/DoS attacks

---

## Future Enhancements

### 1. NFT Minting
Automatically mint commemorative NFTs for winners:
```solidity
contract WorldTreeNFT is ERC721 {
    function mintWinnerNFT(
        address winner,
        uint256 recordId,
        string memory metadataUri
    ) external onlyGameServer {
        _mint(winner, recordId);
        _setTokenURI(recordId, metadataUri);
    }
}
```

### 2. Governance Tokens
Award governance tokens to winners:
```solidity
function distributeGovernanceTokens(
    address winner,
    address[] memory contributors
) external {
    governanceToken.mint(winner, 1000e18);  // 1000 tokens
    for (uint i = 0; i < contributors.length; i++) {
        governanceToken.mint(contributors[i], 100e18);  // 100 tokens
    }
}
```

### 3. Cross-Game Integration
Other games can query World Tree records:
```solidity
// External game checks if player has World Tree win
function hasWorldTreeWin(address player) external view returns (bool) {
    return worldTreeRegistry.hasContributed(player);
}
```

---

## Testing Plan

1. **Local Testing**:
   - Deploy contract to Ashbane testnet
   - Test recording with dummy data
   - Verify queries work correctly

2. **Integration Testing**:
   - Test game server → backend → blockchain flow
   - Verify metadata upload to IPFS
   - Test wallet linking

3. **Production Deployment**:
   - Deploy to Ashbane mainnet
   - Test with first real World Tree winner
   - Monitor gas costs and transaction success

---

## Documentation for Players

### "How to Link Your Wallet"

1. Go to Settings → Blockchain
2. Click "Link Wallet"
3. Connect your MetaMask wallet
4. Sign the verification message
5. Done! Your achievements will be recorded on-chain.

### "Viewing Your On-Chain Records"

1. Go to World Tree Monument
2. Click "My Blockchain Records"
3. Click any record to view on Ashbane Explorer
4. Share the link to prove your achievements!

---

## Notes

- Blockchain recording is **automatic** for World Tree winners
- Only players with linked wallets can be recorded
- All records are **public** and **permanent**
- Gas fees are covered by the game server
- Records enable future NFT/token rewards
