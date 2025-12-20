"""
Wallet authentication and NFT minting service.

Uses SIWE (Sign-In with Ethereum) for wallet verification
and web3.py for contract interaction.
"""
import os
import secrets
import logging
from datetime import datetime, timedelta
from typing import Optional
from eth_account.messages import encode_defunct
from web3 import Web3
from siwe import SiweMessage, VerificationError

logger = logging.getLogger(__name__)

# Configuration from environment
# Default to Base Sepolia testnet for development
CHAIN_ID = int(os.getenv("CHAIN_ID", "84532"))  # Base Sepolia testnet (use 8453 for mainnet)
RPC_URL = os.getenv("RPC_URL", "https://sepolia.base.org")
CONTRACT_ADDRESS = os.getenv("ACHIEVEMENT_CONTRACT_ADDRESS", "")
MINTER_PRIVATE_KEY = os.getenv("MINTER_PRIVATE_KEY", "")  # Backend wallet that owns the contract
APP_URL = os.getenv("APP_URL", "http://localhost:8000")

# Dev mode - simulates blockchain operations without actual transactions
DEV_MODE = os.getenv("DEV_MODE", "false").lower() in ("true", "1", "yes")

# Contract ABI (minimal - just the mint function)
ACHIEVEMENT_ABI = [
    {
        "inputs": [
            {"name": "to", "type": "address"},
            {"name": "achievementId", "type": "string"},
            {"name": "provider", "type": "string"},
            {"name": "rarityTier", "type": "string"},
            {"name": "metadataUri", "type": "string"}
        ],
        "name": "mintAchievement",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"name": "wallet", "type": "address"},
            {"name": "achievementId", "type": "string"}
        ],
        "name": "isMinted",
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"name": "tokenId", "type": "uint256"}],
        "name": "getAchievementData",
        "outputs": [
            {
                "components": [
                    {"name": "originalEarner", "type": "address"},
                    {"name": "achievementId", "type": "string"},
                    {"name": "provider", "type": "string"},
                    {"name": "mintedAt", "type": "uint256"},
                    {"name": "rarityTier", "type": "string"}
                ],
                "type": "tuple"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"name": "tokenId", "type": "uint256"}],
        "name": "ownerOf",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function"
    }
]


def get_web3() -> Web3:
    """Get configured Web3 instance."""
    return Web3(Web3.HTTPProvider(RPC_URL))


def get_contract(w3: Web3):
    """Get the achievement contract instance."""
    if not CONTRACT_ADDRESS:
        raise ValueError("ACHIEVEMENT_CONTRACT_ADDRESS not configured")
    return w3.eth.contract(address=Web3.to_checksum_address(CONTRACT_ADDRESS), abi=ACHIEVEMENT_ABI)


def generate_nonce() -> str:
    """Generate a random nonce for SIWE."""
    return secrets.token_urlsafe(16)


def create_siwe_message(
    wallet_address: str,
    nonce: str,
    chain_id: int = CHAIN_ID,
) -> str:
    """
    Create a SIWE message for the user to sign.

    Returns the message string that should be signed by the wallet.
    """
    # Parse domain from APP_URL
    from urllib.parse import urlparse
    parsed = urlparse(APP_URL)
    domain = parsed.netloc or "localhost:8000"

    message = SiweMessage(
        domain=domain,
        address=Web3.to_checksum_address(wallet_address),
        statement="Link your wallet to Ashbane to forge achievements into tradeable tokens.",
        uri=APP_URL,
        version="1",
        chain_id=chain_id,
        nonce=nonce,
        issued_at=datetime.utcnow().isoformat() + "Z",
        expiration_time=(datetime.utcnow() + timedelta(minutes=10)).isoformat() + "Z",
    )

    return message.prepare_message()


def verify_siwe_signature(
    message: str,
    signature: str,
    expected_nonce: str,
) -> Optional[str]:
    """
    Verify a SIWE signature.

    Returns the wallet address if valid, None if invalid.
    """
    try:
        siwe_message = SiweMessage.from_message(message)

        # Verify nonce matches
        if siwe_message.nonce != expected_nonce:
            logger.warning(f"SIWE nonce mismatch: expected {expected_nonce}, got {siwe_message.nonce}")
            return None

        # Verify the signature
        siwe_message.verify(signature)

        return siwe_message.address

    except VerificationError as e:
        logger.warning(f"SIWE verification failed: {e}")
        return None
    except Exception as e:
        logger.error(f"SIWE error: {e}")
        return None


def build_achievement_id(provider: str, app_id: str, api_name: str) -> str:
    """Build a unique achievement ID for the contract."""
    return f"{provider}_{app_id}_{api_name}"


def build_metadata_uri(achievement_id: int) -> str:
    """Build the metadata URI for an achievement token."""
    return f"{APP_URL}/api/token/metadata/{achievement_id}"


async def mint_achievement_nft(
    wallet_address: str,
    achievement_credit_id: int,
    provider: str,
    app_id: str,
    api_name: str,
    rarity_tier: str,
) -> dict:
    """
    Mint an achievement NFT to the specified wallet.

    Returns dict with:
    - token_id: The minted token ID
    - tx_hash: Transaction hash
    - contract_address: Contract address
    """
    if not MINTER_PRIVATE_KEY:
        raise ValueError("MINTER_PRIVATE_KEY not configured - cannot mint")

    w3 = get_web3()
    contract = get_contract(w3)

    # Build achievement ID
    achievement_id = build_achievement_id(provider, app_id, api_name)
    metadata_uri = build_metadata_uri(achievement_credit_id)

    # Check if already minted
    checksum_address = Web3.to_checksum_address(wallet_address)
    already_minted = contract.functions.isMinted(checksum_address, achievement_id).call()
    if already_minted:
        raise ValueError(f"Achievement {achievement_id} already minted for {wallet_address}")

    # Build transaction
    minter_account = w3.eth.account.from_key(MINTER_PRIVATE_KEY)
    nonce = w3.eth.get_transaction_count(minter_account.address)

    tx = contract.functions.mintAchievement(
        checksum_address,
        achievement_id,
        provider,
        rarity_tier,
        metadata_uri
    ).build_transaction({
        'from': minter_account.address,
        'nonce': nonce,
        'gas': 200000,  # Estimated gas
        'maxFeePerGas': w3.eth.gas_price * 2,
        'maxPriorityFeePerGas': w3.to_wei('0.001', 'gwei'),
    })

    # Sign and send
    signed_tx = w3.eth.account.sign_transaction(tx, MINTER_PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)

    # Wait for receipt
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

    if receipt['status'] != 1:
        raise Exception(f"Transaction failed: {tx_hash.hex()}")

    # Parse token ID from logs (AchievementMinted event)
    # Event signature: AchievementMinted(uint256 indexed tokenId, address indexed originalEarner, ...)
    token_id = None
    for log in receipt['logs']:
        if len(log['topics']) >= 2:
            # First topic is event signature, second is tokenId (indexed)
            token_id = int(log['topics'][1].hex(), 16)
            break

    logger.info(f"Minted achievement {achievement_id} to {wallet_address}: token_id={token_id}, tx={tx_hash.hex()}")

    return {
        'token_id': token_id,
        'tx_hash': tx_hash.hex(),
        'contract_address': CONTRACT_ADDRESS,
        'chain_id': CHAIN_ID,
    }


def check_wallet_owns_achievement(wallet_address: str, achievement_id: str) -> bool:
    """
    Check if a wallet owns a specific achievement token.
    Used by Godot to verify item ownership.
    """
    w3 = get_web3()
    contract = get_contract(w3)

    checksum_address = Web3.to_checksum_address(wallet_address)
    return contract.functions.isMinted(checksum_address, achievement_id).call()


def get_achievement_token_data(token_id: int) -> Optional[dict]:
    """Get on-chain data for a token."""
    w3 = get_web3()
    contract = get_contract(w3)

    try:
        data = contract.functions.getAchievementData(token_id).call()
        return {
            'original_earner': data[0],
            'achievement_id': data[1],
            'provider': data[2],
            'minted_at': data[3],
            'rarity_tier': data[4],
        }
    except Exception as e:
        logger.error(f"Failed to get token data: {e}")
        return None


# =============================================================================
# BRIDGE SYSTEM - Transfer functions
# =============================================================================

# Platform wallet that holds items when they're "in-game"
PLATFORM_WALLET_ADDRESS = os.getenv("PLATFORM_WALLET_ADDRESS", "")
PLATFORM_WALLET_KEY = os.getenv("PLATFORM_WALLET_KEY", "")  # Private key for platform wallet

# Extended ABI for transfers
TRANSFER_ABI = [
    {
        "inputs": [
            {"name": "from", "type": "address"},
            {"name": "to", "type": "address"},
            {"name": "tokenId", "type": "uint256"}
        ],
        "name": "transferFrom",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"name": "from", "type": "address"},
            {"name": "to", "type": "address"},
            {"name": "tokenId", "type": "uint256"}
        ],
        "name": "safeTransferFrom",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [{"name": "tokenId", "type": "uint256"}],
        "name": "ownerOf",
        "outputs": [{"name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function"
    }
]


def get_transfer_contract(w3: Web3):
    """Get contract instance with transfer functions."""
    if not CONTRACT_ADDRESS:
        raise ValueError("ACHIEVEMENT_CONTRACT_ADDRESS not configured")
    # Combine ABIs
    full_abi = ACHIEVEMENT_ABI + TRANSFER_ABI
    return w3.eth.contract(address=Web3.to_checksum_address(CONTRACT_ADDRESS), abi=full_abi)


async def transfer_to_external(token_id: int, to_address: str) -> str:
    """
    Transfer NFT from platform wallet to user's external wallet.
    Used for bridge-out confirmation.

    Returns: transaction hash
    """
    # Dev mode - simulate successful transfer without blockchain
    if DEV_MODE:
        mock_tx_hash = f"0x{'dev' + str(token_id).zfill(61)}"
        logger.info(f"[DEV MODE] Simulated bridge-out transfer: token {token_id} -> {to_address}, tx: {mock_tx_hash}")
        return mock_tx_hash

    if not PLATFORM_WALLET_KEY:
        raise ValueError("PLATFORM_WALLET_KEY not configured - cannot transfer")

    if not PLATFORM_WALLET_ADDRESS:
        raise ValueError("PLATFORM_WALLET_ADDRESS not configured")

    w3 = get_web3()
    contract = get_transfer_contract(w3)

    # Verify platform owns the token
    current_owner = contract.functions.ownerOf(token_id).call()
    platform_checksum = Web3.to_checksum_address(PLATFORM_WALLET_ADDRESS)

    if current_owner.lower() != platform_checksum.lower():
        raise ValueError(f"Platform does not own token {token_id}. Owner: {current_owner}")

    # Build transfer transaction
    to_checksum = Web3.to_checksum_address(to_address)
    platform_account = w3.eth.account.from_key(PLATFORM_WALLET_KEY)
    nonce = w3.eth.get_transaction_count(platform_account.address)

    tx = contract.functions.safeTransferFrom(
        platform_checksum,
        to_checksum,
        token_id
    ).build_transaction({
        'from': platform_account.address,
        'nonce': nonce,
        'gas': 100000,
        'maxFeePerGas': w3.eth.gas_price * 2,
        'maxPriorityFeePerGas': w3.to_wei('0.001', 'gwei'),
    })

    # Sign and send
    signed_tx = w3.eth.account.sign_transaction(tx, PLATFORM_WALLET_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)

    # Wait for receipt
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

    if receipt['status'] != 1:
        raise Exception(f"Transfer failed: {tx_hash.hex()}")

    logger.info(f"Bridge-out transfer: token {token_id} -> {to_address}, tx: {tx_hash.hex()}")

    return tx_hash.hex()


async def transfer_from_external(token_id: int, from_address: str) -> str:
    """
    Transfer NFT from user's external wallet to platform wallet.
    Used for bridge-in.

    NOTE: This requires the user to have approved the platform wallet
    to transfer their tokens (via setApprovalForAll or approve).

    Returns: transaction hash
    """
    # Dev mode - simulate successful transfer without blockchain
    if DEV_MODE:
        mock_tx_hash = f"0x{'dev' + str(token_id).zfill(61)}"
        logger.info(f"[DEV MODE] Simulated bridge-in transfer: token {token_id} <- {from_address}, tx: {mock_tx_hash}")
        return mock_tx_hash

    if not PLATFORM_WALLET_KEY:
        raise ValueError("PLATFORM_WALLET_KEY not configured - cannot transfer")

    if not PLATFORM_WALLET_ADDRESS:
        raise ValueError("PLATFORM_WALLET_ADDRESS not configured")

    w3 = get_web3()
    contract = get_transfer_contract(w3)

    # Verify user owns the token
    current_owner = contract.functions.ownerOf(token_id).call()
    from_checksum = Web3.to_checksum_address(from_address)

    if current_owner.lower() != from_checksum.lower():
        raise ValueError(f"User does not own token {token_id}. Owner: {current_owner}")

    # Build transfer transaction (platform executes transferFrom)
    platform_checksum = Web3.to_checksum_address(PLATFORM_WALLET_ADDRESS)
    platform_account = w3.eth.account.from_key(PLATFORM_WALLET_KEY)
    nonce = w3.eth.get_transaction_count(platform_account.address)

    tx = contract.functions.safeTransferFrom(
        from_checksum,
        platform_checksum,
        token_id
    ).build_transaction({
        'from': platform_account.address,
        'nonce': nonce,
        'gas': 100000,
        'maxFeePerGas': w3.eth.gas_price * 2,
        'maxPriorityFeePerGas': w3.to_wei('0.001', 'gwei'),
    })

    # Sign and send
    signed_tx = w3.eth.account.sign_transaction(tx, PLATFORM_WALLET_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)

    # Wait for receipt
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

    if receipt['status'] != 1:
        raise Exception(f"Transfer failed: {tx_hash.hex()}")

    logger.info(f"Bridge-in transfer: token {token_id} <- {from_address}, tx: {tx_hash.hex()}")

    return tx_hash.hex()


def get_token_owner(token_id: int) -> Optional[str]:
    """Get current on-chain owner of a token."""
    w3 = get_web3()
    contract = get_transfer_contract(w3)

    try:
        owner = contract.functions.ownerOf(token_id).call()
        return owner.lower()
    except Exception as e:
        logger.error(f"Failed to get token owner: {e}")
        return None
