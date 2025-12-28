"""
Relayer Service for Gasless Transactions

Handles all blockchain interactions for forging items and recording trades.
Users never pay gas - the relayer wallet pays for all transactions.

Environment Variables Required:
    RELAYER_PRIVATE_KEY: Private key for the relayer wallet
    POLYGON_RPC_URL: RPC endpoint for Polygon (mainnet or testnet)
    FORGED_ITEMS_CONTRACT: Deployed ForgedItems contract address
"""

import os
import json
import hashlib
import logging
from typing import Optional, List, Dict, Any
from datetime import datetime
from web3 import Web3
try:
    from web3.middleware import ExtraDataToPOAMiddleware
except ImportError:
    # web3 6.x moved this middleware
    from web3.middleware import geth_poa_middleware as ExtraDataToPOAMiddleware
from eth_account import Account

logger = logging.getLogger(__name__)

# Contract ABI (subset for the functions we need)
FORGED_ITEMS_ABI = [
    {
        "inputs": [
            {"internalType": "address", "name": "to", "type": "address"},
            {"internalType": "string", "name": "itemId", "type": "string"},
            {"internalType": "string", "name": "achievementId", "type": "string"},
            {"internalType": "string", "name": "rarity", "type": "string"},
            {"internalType": "string", "name": "metadataUri", "type": "string"}
        ],
        "name": "forgeItem",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {
                "components": [
                    {"internalType": "uint256", "name": "tokenId", "type": "uint256"},
                    {"internalType": "address", "name": "from", "type": "address"},
                    {"internalType": "address", "name": "to", "type": "address"},
                    {"internalType": "uint256", "name": "priceGold", "type": "uint256"},
                    {"internalType": "uint256", "name": "tradedAt", "type": "uint256"},
                    {"internalType": "bytes32", "name": "txRef", "type": "bytes32"}
                ],
                "internalType": "struct ForgedItems.TradeRecord[]",
                "name": "trades",
                "type": "tuple[]"
            },
            {"internalType": "bytes32", "name": "batchId", "type": "bytes32"}
        ],
        "name": "recordTradeBatch",
        "outputs": [{"internalType": "uint256", "name": "processedCount", "type": "uint256"}],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "uint256", "name": "tokenId", "type": "uint256"},
            {"internalType": "address", "name": "from", "type": "address"},
            {"internalType": "address", "name": "to", "type": "address"},
            {"internalType": "uint256", "name": "priceGold", "type": "uint256"},
            {"internalType": "bytes32", "name": "txRef", "type": "bytes32"}
        ],
        "name": "recordTrade",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "uint256", "name": "tokenId", "type": "uint256"}],
        "name": "getProvenance",
        "outputs": [
            {
                "components": [
                    {"internalType": "address", "name": "forger", "type": "address"},
                    {"internalType": "address", "name": "currentOwner", "type": "address"},
                    {"internalType": "uint256", "name": "forgedAt", "type": "uint256"},
                    {"internalType": "uint256", "name": "lastTradeAt", "type": "uint256"},
                    {"internalType": "uint32", "name": "tradeCount", "type": "uint32"},
                    {"internalType": "string", "name": "itemId", "type": "string"},
                    {"internalType": "string", "name": "achievementId", "type": "string"},
                    {"internalType": "string", "name": "rarity", "type": "string"}
                ],
                "internalType": "struct ForgedItems.Provenance",
                "name": "",
                "type": "tuple"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "uint256", "name": "tokenId", "type": "uint256"}],
        "name": "getTradeHistory",
        "outputs": [
            {
                "components": [
                    {"internalType": "uint256", "name": "tokenId", "type": "uint256"},
                    {"internalType": "address", "name": "from", "type": "address"},
                    {"internalType": "address", "name": "to", "type": "address"},
                    {"internalType": "uint256", "name": "priceGold", "type": "uint256"},
                    {"internalType": "uint256", "name": "tradedAt", "type": "uint256"},
                    {"internalType": "bytes32", "name": "txRef", "type": "bytes32"}
                ],
                "internalType": "struct ForgedItems.TradeRecord[]",
                "name": "",
                "type": "tuple[]"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "address", "name": "forger", "type": "address"},
            {"internalType": "string", "name": "achievementId", "type": "string"}
        ],
        "name": "isForged",
        "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "address", "name": "forger", "type": "address"},
            {"internalType": "string", "name": "achievementId", "type": "string"}
        ],
        "name": "getForgedTokenId",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function"
    }
]


class RelayerService:
    """
    Handles gasless blockchain transactions for the forge system.

    The relayer wallet pays all gas fees, making blockchain interactions
    invisible to players. Users never need to own crypto or understand gas.
    """

    def __init__(self):
        self.w3: Optional[Web3] = None
        self.account: Optional[Account] = None
        self.contract = None
        self._initialized = False
        self._nonce_lock = False
        self._current_nonce: Optional[int] = None

    def initialize(self) -> bool:
        """
        Initialize web3 connection and relayer account.
        Returns True if successful, False otherwise.
        """
        if self._initialized:
            return True

        rpc_url = os.environ.get("POLYGON_RPC_URL")
        private_key = os.environ.get("RELAYER_PRIVATE_KEY")
        contract_address = os.environ.get("FORGED_ITEMS_CONTRACT")

        if not all([rpc_url, private_key, contract_address]):
            logger.warning(
                "Relayer not configured. Set POLYGON_RPC_URL, RELAYER_PRIVATE_KEY, "
                "and FORGED_ITEMS_CONTRACT environment variables."
            )
            return False

        try:
            # Connect to Polygon
            self.w3 = Web3(Web3.HTTPProvider(rpc_url))

            # Add PoA middleware for Polygon
            self.w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)

            if not self.w3.is_connected():
                logger.error("Failed to connect to Polygon RPC")
                return False

            # Setup relayer account
            self.account = Account.from_key(private_key)
            logger.info(f"Relayer initialized: {self.account.address}")

            # Setup contract
            self.contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(contract_address),
                abi=FORGED_ITEMS_ABI
            )

            self._initialized = True
            return True

        except Exception as e:
            logger.error(f"Failed to initialize relayer: {e}")
            return False

    def get_relayer_address(self) -> Optional[str]:
        """Get the relayer wallet address."""
        if self.account:
            return self.account.address
        return None

    def get_balance(self) -> Optional[float]:
        """Get relayer wallet balance in MATIC."""
        if not self._initialized:
            return None
        try:
            balance_wei = self.w3.eth.get_balance(self.account.address)
            return float(self.w3.from_wei(balance_wei, 'ether'))
        except Exception as e:
            logger.error(f"Failed to get balance: {e}")
            return None

    def _get_nonce(self) -> int:
        """Get the next nonce for the relayer account."""
        if self._current_nonce is not None:
            self._current_nonce += 1
            return self._current_nonce
        self._current_nonce = self.w3.eth.get_transaction_count(self.account.address)
        return self._current_nonce

    def _reset_nonce(self):
        """Reset nonce cache (call after transaction errors)."""
        self._current_nonce = None

    def _estimate_gas_price(self) -> Dict[str, int]:
        """
        Get gas price parameters for Polygon.
        Uses EIP-1559 style pricing.
        """
        try:
            # Get base fee from latest block
            latest = self.w3.eth.get_block('latest')
            base_fee = latest.get('baseFeePerGas', self.w3.to_wei(30, 'gwei'))

            # Add priority fee (tip)
            priority_fee = self.w3.to_wei(30, 'gwei')  # 30 gwei priority
            max_fee = base_fee * 2 + priority_fee  # 2x base + priority

            return {
                'maxFeePerGas': max_fee,
                'maxPriorityFeePerGas': priority_fee
            }
        except Exception as e:
            logger.warning(f"Failed to estimate gas price, using defaults: {e}")
            return {
                'maxFeePerGas': self.w3.to_wei(100, 'gwei'),
                'maxPriorityFeePerGas': self.w3.to_wei(30, 'gwei')
            }

    def forge_item(
        self,
        player_wallet: str,
        item_id: str,
        achievement_id: str,
        rarity: str,
        metadata_uri: str
    ) -> Optional[Dict[str, Any]]:
        """
        Forge a new item NFT for a player.

        Args:
            player_wallet: Player's wallet address (receives the NFT)
            item_id: Internal item ID from items.json
            achievement_id: Source achievement ID
            rarity: Rarity tier (Legendary, Epic, etc.)
            metadata_uri: URI to item metadata JSON

        Returns:
            Dict with tx_hash and token_id, or None on failure
        """
        if not self._initialized:
            if not self.initialize():
                return None

        try:
            # Check if already forged
            is_forged = self.contract.functions.isForged(
                Web3.to_checksum_address(player_wallet),
                achievement_id
            ).call()

            if is_forged:
                # Return existing token ID
                token_id = self.contract.functions.getForgedTokenId(
                    Web3.to_checksum_address(player_wallet),
                    achievement_id
                ).call()
                return {
                    'tx_hash': None,
                    'token_id': token_id,
                    'already_forged': True
                }

            # Build transaction
            tx = self.contract.functions.forgeItem(
                Web3.to_checksum_address(player_wallet),
                item_id,
                achievement_id,
                rarity,
                metadata_uri
            ).build_transaction({
                'from': self.account.address,
                'nonce': self._get_nonce(),
                'gas': 300000,  # Estimate, will be adjusted
                **self._estimate_gas_price()
            })

            # Estimate gas
            try:
                estimated_gas = self.w3.eth.estimate_gas(tx)
                tx['gas'] = int(estimated_gas * 1.2)  # 20% buffer
            except Exception as e:
                logger.warning(f"Gas estimation failed, using default: {e}")

            # Sign and send
            signed = self.account.sign_transaction(tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)

            logger.info(f"Forge tx sent: {tx_hash.hex()}")

            # Wait for receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

            if receipt['status'] != 1:
                logger.error(f"Forge transaction failed: {receipt}")
                self._reset_nonce()
                return None

            # Get token ID from logs
            token_id = None
            for log in receipt['logs']:
                # ItemForged event topic
                if len(log['topics']) > 1:
                    token_id = int(log['topics'][1].hex(), 16)
                    break

            return {
                'tx_hash': tx_hash.hex(),
                'token_id': token_id,
                'gas_used': receipt['gasUsed'],
                'already_forged': False
            }

        except Exception as e:
            logger.error(f"Failed to forge item: {e}")
            self._reset_nonce()
            return None

    def record_trade_batch(
        self,
        trades: List[Dict[str, Any]],
        batch_id: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        """
        Record a batch of trades on-chain.

        Args:
            trades: List of trade dicts with:
                - token_id: int
                - from_wallet: str (address)
                - to_wallet: str (address)
                - price_gold: int
                - traded_at: int (timestamp)
                - tx_ref: str (backend reference, will be hashed)
            batch_id: Optional batch identifier (generated if not provided)

        Returns:
            Dict with tx_hash and processed_count, or None on failure
        """
        if not self._initialized:
            if not self.initialize():
                return None

        if not trades:
            return {'tx_hash': None, 'processed_count': 0, 'skipped': True}

        try:
            # Generate batch ID if not provided
            if not batch_id:
                batch_id = f"batch_{datetime.utcnow().isoformat()}_{len(trades)}"
            batch_id_bytes = Web3.keccak(text=batch_id)

            # Format trades for contract
            formatted_trades = []
            for trade in trades:
                # Generate tx_ref hash from backend reference
                tx_ref = Web3.keccak(text=str(trade.get('tx_ref', trade.get('id', ''))))

                formatted_trades.append((
                    int(trade['token_id']),
                    Web3.to_checksum_address(trade['from_wallet']),
                    Web3.to_checksum_address(trade['to_wallet']),
                    int(trade['price_gold']),
                    int(trade['traded_at']),
                    tx_ref
                ))

            # Build transaction
            tx = self.contract.functions.recordTradeBatch(
                formatted_trades,
                batch_id_bytes
            ).build_transaction({
                'from': self.account.address,
                'nonce': self._get_nonce(),
                'gas': 100000 + (50000 * len(trades)),  # Base + per trade
                **self._estimate_gas_price()
            })

            # Estimate gas
            try:
                estimated_gas = self.w3.eth.estimate_gas(tx)
                tx['gas'] = int(estimated_gas * 1.2)
            except Exception as e:
                logger.warning(f"Gas estimation failed for batch, using default: {e}")

            # Sign and send
            signed = self.account.sign_transaction(tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)

            logger.info(f"Trade batch tx sent: {tx_hash.hex()} ({len(trades)} trades)")

            # Wait for receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=180)

            if receipt['status'] != 1:
                logger.error(f"Trade batch failed: {receipt}")
                self._reset_nonce()
                return None

            return {
                'tx_hash': tx_hash.hex(),
                'batch_id': batch_id,
                'trade_count': len(trades),
                'gas_used': receipt['gasUsed']
            }

        except Exception as e:
            logger.error(f"Failed to record trade batch: {e}")
            self._reset_nonce()
            return None

    def get_provenance(self, token_id: int) -> Optional[Dict[str, Any]]:
        """
        Get provenance data for a token directly from chain.

        Returns:
            Dict with forger, currentOwner, tradeCount, etc.
        """
        if not self._initialized:
            if not self.initialize():
                return None

        try:
            result = self.contract.functions.getProvenance(token_id).call()

            return {
                'forger': result[0],
                'current_owner': result[1],
                'forged_at': result[2],
                'last_trade_at': result[3],
                'trade_count': result[4],
                'item_id': result[5],
                'achievement_id': result[6],
                'rarity': result[7]
            }
        except Exception as e:
            logger.error(f"Failed to get provenance for token {token_id}: {e}")
            return None

    def get_trade_history(self, token_id: int) -> Optional[List[Dict[str, Any]]]:
        """
        Get full trade history for a token from chain.
        """
        if not self._initialized:
            if not self.initialize():
                return None

        try:
            result = self.contract.functions.getTradeHistory(token_id).call()

            history = []
            for trade in result:
                history.append({
                    'token_id': trade[0],
                    'from': trade[1],
                    'to': trade[2],
                    'price_gold': trade[3],
                    'traded_at': trade[4],
                    'tx_ref': trade[5].hex()
                })

            return history
        except Exception as e:
            logger.error(f"Failed to get trade history for token {token_id}: {e}")
            return None


# Singleton instance
relayer_service = RelayerService()
