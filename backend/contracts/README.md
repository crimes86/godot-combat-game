# Achievement Token Contract

> ⚠️ **SECURITY WARNING** ⚠️
>
> This guide references private keys and secrets. **NEVER commit real private keys to git.**
>
> Before deploying:
> 1. Use `.env.example` as a template (contains placeholders only)
> 2. Create `.env` locally with real values
> 3. Verify `.env` is in `.gitignore`
> 4. Consider using a hardware wallet for production deployments

## Overview

This is the smart contract for minting verified gaming achievements as NFTs.

## Deployment

### Prerequisites

```bash
npm install -g hardhat
npm install @openzeppelin/contracts
```

### Deploy to Base Testnet (Sepolia)

1. Create `.env`:
```
PRIVATE_KEY=your_deployer_wallet_private_key
BASE_SEPOLIA_RPC=https://sepolia.base.org
```

2. Deploy:
```bash
npx hardhat run scripts/deploy.js --network base-sepolia
```

3. Note the contract address and add to your backend `.env`:
```
ACHIEVEMENT_CONTRACT_ADDRESS=0x...
MINTER_PRIVATE_KEY=same_as_deployer_for_now
```

### Deploy to Base Mainnet

Same process but with mainnet RPC and real ETH for gas.

## Contract Features

- **Verified Minting**: Only the backend (contract owner/relayer) can mint
- **Duplicate Prevention**: Same achievement can't be minted twice to same wallet
- **Provenance Tracking**: Stores original forger, trade count, ownership chain
- **Trade Recording**: Backend batches trade updates to chain (every 5 min)
- **Standard ERC-721**: Compatible with OpenSea, Blur, etc.

### Provenance Data Stored On-Chain

```solidity
struct ItemProvenance {
    string definitionId;      // "hand_of_malenia"
    string achievementId;     // "steam:1245620:SHARDBEARER_MALENIA"
    uint256 forgedAt;         // Unix timestamp
    address originalForger;   // Wallet that forged (platform wallet for most users)
    uint256 tradeCount;       // Incremented on each trade
}
```

### Trading Flow

Most users trade **in-game** without touching crypto:
1. Trade completes in Dreadland (instant)
2. Backend records trade in database (source of truth)
3. Backend queues chain update
4. Relayer batches updates to Polygon (every 5 min)

Users can optionally **bridge out** to personal wallets for external trading (OpenSea, etc.).

## Backend Verification (Before Minting)

The backend enforces additional checks before calling the contract:
1. User owns the AchievementCredit
2. `is_original_claim = TRUE` (not a reclaimed/display-only achievement)
3. AchievementCredit hasn't been forged yet (no ForgedAchievement record)
4. Achievement rarity is Rare, Epic, or Legendary

See `docs/ACHIEVEMENT_VERIFICATION.md` for the full 6-layer anti-exploit system.

## Gas Costs (Base L2)

- Deploy: ~$1-2
- Mint single: ~$0.01-0.05
- Batch mint (10): ~$0.05-0.20

## Backend Integration

See `app/services/wallet_service.py` for the Python integration.

Required environment variables:
```
CHAIN_ID=8453                    # Base mainnet (84532 for testnet)
RPC_URL=https://mainnet.base.org
ACHIEVEMENT_CONTRACT_ADDRESS=0x...
MINTER_PRIVATE_KEY=0x...         # Backend wallet that owns contract
```

## Testing

```bash
npx hardhat test
```

## Related Documentation

- `docs/ACHIEVEMENT_VERIFICATION.md` - Full 6-layer anti-exploit system
- `docs/FORGE_PROVENANCE_SYSTEM.md` - Provenance tracking specification
- `docs/FORGE_ECONOMY_DESIGN.md` - Trading and economy design
- `docs/API_CONTRACT.md` - Backend API endpoints for trading
