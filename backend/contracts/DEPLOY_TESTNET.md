# Deploying to Base Sepolia Testnet

This guide walks you through deploying the AchievementToken contract to Base Sepolia testnet for testing the full forge/mint/bridge flow.

## What You'll Need

1. A crypto wallet (MetaMask recommended)
2. Free testnet ETH from a faucet
3. Node.js installed on your machine

## Step-by-Step Guide

### Step 1: Create a Deployer Wallet

You need a wallet that will:
- Deploy the contract (and become its owner)
- Sign minting transactions from the backend
- Hold the platform custody wallet for bridging

**Option A: Use MetaMask (Recommended)**

1. Install MetaMask browser extension if you haven't: https://metamask.io
2. Create a new account (or use existing)
3. Click the three dots → "Account details" → "Show private key"
4. Enter your password and copy the private key (starts with 0x)

**Option B: Generate a fresh wallet (for dedicated backend use)**

```bash
# In the contracts directory
cd /root/ashbane-backend/backend/contracts
npm install  # Install dependencies first
npx hardhat console

# In the console:
const wallet = ethers.Wallet.createRandom()
console.log("Address:", wallet.address)
console.log("Private Key:", wallet.privateKey)
# Copy both values, then type .exit
```

### Step 2: Get Free Testnet ETH

Base Sepolia uses free "test ETH" that has no real value. You need a small amount for gas fees.

**Faucets (pick one that works):**

1. **Alchemy Faucet** (recommended): https://www.alchemy.com/faucets/base-sepolia
   - Connect wallet or paste address
   - Get 0.1 ETH (enough for hundreds of deploys)

2. **Coinbase Faucet**: https://faucet.quicknode.com/base/sepolia
   - May require verification

3. **Alternative**: https://faucet.triangleplatform.com/base/sepolia

Wait 1-2 minutes after requesting. Check your balance at:
https://sepolia.basescan.org/address/YOUR_WALLET_ADDRESS

### Step 3: Set Up Environment

```bash
cd /root/ashbane-backend/backend/contracts

# Install dependencies
npm install

# Create your .env file (copy from example)
cp .env.example .env

# Edit .env and add your private key
nano .env
```

Your `.env` should look like:
```
DEPLOYER_PRIVATE_KEY=0x1234567890abcdef...your_actual_private_key...
```

### Step 4: Deploy the Contract

```bash
npm run deploy:testnet
```

You should see output like:
```
Deploying AchievementToken to baseSepolia ...

Deploying with account: 0xYourAddress
Account balance: 0.1 ETH

Deploying AchievementToken...

========================================
SUCCESS! Contract deployed!
========================================

Contract Address: 0xAbCdEf123...
Owner (Minter): 0xYourAddress

View on BaseScan:
https://sepolia.basescan.org/address/0xAbCdEf123...

========================================
NEXT STEPS - Add to backend/.env:
========================================

CHAIN_ID=84532
RPC_URL=https://sepolia.base.org
ACHIEVEMENT_CONTRACT_ADDRESS=0xAbCdEf123...
MINTER_PRIVATE_KEY=0x...
PLATFORM_WALLET_ADDRESS=0xYourAddress
PLATFORM_WALLET_KEY=0x...
BRIDGE_COOLDOWN_HOURS=0.033
```

### Step 5: Update Backend Configuration

Add the output values to your backend `.env` file:

```bash
nano /root/ashbane-backend/backend/.env
```

Add these lines at the bottom:
```env
# Blockchain Configuration (Base Sepolia Testnet)
CHAIN_ID=84532
RPC_URL=https://sepolia.base.org
ACHIEVEMENT_CONTRACT_ADDRESS=0x_paste_from_deploy_output
MINTER_PRIVATE_KEY=0x_same_as_deployer_key
PLATFORM_WALLET_ADDRESS=0x_paste_from_deploy_output
PLATFORM_WALLET_KEY=0x_same_as_deployer_key
BRIDGE_COOLDOWN_HOURS=0.033
```

### Step 6: Restart Backend

```bash
# If using systemd
sudo systemctl restart ashbane

# Or if running manually
# Ctrl+C to stop, then restart
```

## Verify It's Working

### Check Contract on BaseScan

Visit the URL from the deploy output. You should see:
- Contract created
- Owner set to your deployer address
- "Ashbane Achievement" as the token name

### Test a Mint (via Backend)

1. Log into Ashbane with a gaming account (Steam, etc.)
2. Sync achievements
3. Go to the Armory
4. Find a forgeable achievement (Rare or higher)
5. Link your wallet (can be any testnet wallet)
6. Click Forge

The backend will call the contract and mint an NFT!

## Troubleshooting

### "Deployer wallet has no ETH"
→ Faucet didn't work or you're using wrong address. Check balance on BaseScan.

### "Invalid private key"
→ Make sure key starts with `0x` and has no extra spaces

### "Transaction failed"
→ Usually means not enough gas. Get more testnet ETH.

### Backend can't connect to chain
→ Check RPC_URL is exactly `https://sepolia.base.org`

## Two Wallets vs One Wallet

For testing, we use **one wallet** for everything (deployer = minter = platform).

For production, you'd want:
- **Deployer**: One-time use, can be discarded after deploy
- **Minter**: Backend wallet that signs mint transactions (keep secure)
- **Platform**: Custody wallet that holds bridged items (separate keys)

## Cost Summary (Testnet = Free)

| Action | Cost |
|--------|------|
| Deploy contract | ~0.001 ETH (free testnet ETH) |
| Mint one NFT | ~0.0001 ETH |
| Bridge transfer | ~0.0001 ETH |

## Next Steps

Once deployed and configured:
1. Test the full flow in Godot
2. Verify minting works
3. Test bridge-out (2 min cooldown on testnet)
4. Test bridge-in
5. When ready for production, deploy to Base Mainnet (chain ID 8453)
