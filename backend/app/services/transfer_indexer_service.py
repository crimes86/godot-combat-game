"""
Transfer Indexer Service for bridge system.

Polls the blockchain for Transfer events on our NFT contract and
updates the database when items change hands externally (OpenSea sales, etc).

This enables:
1. Detecting when Player A sells to Player B on OpenSea
2. Updating ownership records so Player B can bridge item into game
3. Broadcasting notifications ("Your item sold!")

The database is the source of truth for gameplay.
The indexer keeps it in sync with on-chain state.
"""
import os
import asyncio
import logging
from datetime import datetime
from typing import Optional, List
from sqlalchemy.orm import Session as DbSession

from app.models import ForgedAchievement, WalletAccount, User, BridgeTransaction, BridgeStatus
from app.database import SessionLocal

logger = logging.getLogger(__name__)

# Configuration
POLL_INTERVAL_SECONDS = int(os.getenv("INDEXER_POLL_INTERVAL", "30"))  # 30 seconds
MAX_BLOCKS_PER_POLL = int(os.getenv("INDEXER_MAX_BLOCKS", "1000"))  # Max blocks to scan per poll
START_BLOCK_ENV = os.getenv("INDEXER_START_BLOCK", "latest")  # "latest" or block number

# Chain configuration (from wallet_service)
CHAIN_ID = int(os.getenv("CHAIN_ID", "84532"))  # Base Sepolia testnet
RPC_URL = os.getenv("RPC_URL", "https://sepolia.base.org")
CONTRACT_ADDRESS = os.getenv("ACHIEVEMENT_CONTRACT_ADDRESS", "")
PLATFORM_WALLET = os.getenv("PLATFORM_WALLET_ADDRESS", "")  # Platform custody wallet

# ERC-721 Transfer event signature
# Transfer(address indexed from, address indexed to, uint256 indexed tokenId)
TRANSFER_EVENT_SIGNATURE = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"


class TransferIndexerService:
    """Service to watch blockchain for NFT transfers and sync to database."""

    def __init__(self):
        self._is_running = False
        self._task: Optional[asyncio.Task] = None
        self._w3 = None
        self._contract = None
        self._last_processed_block: int = 0
        self._state_file = os.path.join(os.path.dirname(__file__), ".indexer_state")

    def _load_state(self) -> int:
        """Load last processed block from state file."""
        try:
            if os.path.exists(self._state_file):
                with open(self._state_file, "r") as f:
                    return int(f.read().strip())
        except Exception as e:
            logger.warning(f"Failed to load indexer state: {e}")
        return 0

    def _save_state(self, block: int) -> None:
        """Save last processed block to state file."""
        try:
            with open(self._state_file, "w") as f:
                f.write(str(block))
        except Exception as e:
            logger.warning(f"Failed to save indexer state: {e}")

    def initialize(self) -> bool:
        """Initialize web3 connection and contract."""
        if not CONTRACT_ADDRESS:
            logger.warning("Transfer indexer disabled - no CONTRACT_ADDRESS configured")
            return False

        if not PLATFORM_WALLET:
            logger.warning("Transfer indexer disabled - no PLATFORM_WALLET_ADDRESS configured")
            return False

        try:
            from web3 import Web3

            self._w3 = Web3(Web3.HTTPProvider(RPC_URL))
            if not self._w3.is_connected():
                logger.error(f"Failed to connect to RPC: {RPC_URL}")
                return False

            # Minimal ABI for Transfer event and ownerOf
            abi = [
                {
                    "anonymous": False,
                    "inputs": [
                        {"indexed": True, "name": "from", "type": "address"},
                        {"indexed": True, "name": "to", "type": "address"},
                        {"indexed": True, "name": "tokenId", "type": "uint256"}
                    ],
                    "name": "Transfer",
                    "type": "event"
                },
                {
                    "inputs": [{"name": "tokenId", "type": "uint256"}],
                    "name": "ownerOf",
                    "outputs": [{"name": "", "type": "address"}],
                    "stateMutability": "view",
                    "type": "function"
                }
            ]

            self._contract = self._w3.eth.contract(
                address=Web3.to_checksum_address(CONTRACT_ADDRESS),
                abi=abi
            )

            # Initialize start block
            saved_block = self._load_state()
            if saved_block > 0:
                self._last_processed_block = saved_block
                logger.info(f"Resuming indexer from block {saved_block}")
            elif START_BLOCK_ENV == "latest":
                self._last_processed_block = self._w3.eth.block_number
                logger.info(f"Starting indexer from current block {self._last_processed_block}")
            else:
                self._last_processed_block = int(START_BLOCK_ENV)
                logger.info(f"Starting indexer from configured block {self._last_processed_block}")

            logger.info(f"Transfer indexer initialized - contract: {CONTRACT_ADDRESS[:10]}..., platform wallet: {PLATFORM_WALLET[:10]}...")
            return True

        except ImportError:
            logger.warning("Transfer indexer disabled - web3 not installed")
            return False
        except Exception as e:
            logger.error(f"Failed to initialize transfer indexer: {e}")
            return False

    def start(self) -> None:
        """Start the background indexing task."""
        if self._is_running:
            logger.warning("Transfer indexer already running")
            return

        if not self.initialize():
            return

        self._is_running = True
        self._task = asyncio.create_task(self._poll_loop())
        logger.info(f"Transfer indexer started (interval: {POLL_INTERVAL_SECONDS}s)")

    def stop(self) -> None:
        """Stop the background indexing task."""
        self._is_running = False
        if self._task:
            self._task.cancel()
            self._task = None
        # Save state on shutdown
        if self._last_processed_block > 0:
            self._save_state(self._last_processed_block)
        logger.info("Transfer indexer stopped")

    async def _poll_loop(self) -> None:
        """Main loop that polls for Transfer events."""
        while self._is_running:
            try:
                await self.poll_transfers()
                await asyncio.sleep(POLL_INTERVAL_SECONDS)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in indexer poll loop: {e}", exc_info=True)
                await asyncio.sleep(POLL_INTERVAL_SECONDS)  # Continue after error

    async def poll_transfers(self) -> int:
        """
        Poll for new Transfer events and process them.
        Returns the number of transfers processed.
        """
        if not self._w3 or not self._contract:
            return 0

        try:
            current_block = self._w3.eth.block_number

            if current_block <= self._last_processed_block:
                return 0

            # Calculate block range
            from_block = self._last_processed_block + 1
            to_block = min(current_block, from_block + MAX_BLOCKS_PER_POLL - 1)

            logger.debug(f"Scanning blocks {from_block} to {to_block}")

            # Get Transfer events
            # Run in executor since web3 is synchronous
            loop = asyncio.get_event_loop()
            events = await loop.run_in_executor(
                None,
                self._get_transfer_events,
                from_block,
                to_block
            )

            processed = 0
            for event in events:
                try:
                    await self._process_transfer(event)
                    processed += 1
                except Exception as e:
                    logger.error(f"Error processing transfer event: {e}", exc_info=True)

            # Update last processed block
            self._last_processed_block = to_block
            self._save_state(to_block)

            if processed > 0:
                logger.info(f"Processed {processed} transfers in blocks {from_block}-{to_block}")

            return processed

        except Exception as e:
            logger.error(f"Error polling transfers: {e}", exc_info=True)
            return 0

    def _get_transfer_events(self, from_block: int, to_block: int) -> List:
        """Get Transfer events from blockchain (synchronous)."""
        try:
            event_filter = self._contract.events.Transfer.create_filter(
                fromBlock=from_block,
                toBlock=to_block
            )
            return event_filter.get_all_entries()
        except Exception as e:
            logger.error(f"Failed to get transfer events: {e}")
            return []

    async def _process_transfer(self, event) -> None:
        """Process a single Transfer event."""
        token_id = event.args.tokenId
        from_address = event.args['from'].lower()
        to_address = event.args['to'].lower()
        tx_hash = event.transactionHash.hex()
        block_number = event.blockNumber

        logger.debug(f"Transfer detected: token {token_id} from {from_address[:10]}... to {to_address[:10]}...")

        # Skip mint events (from zero address)
        if from_address == "0x0000000000000000000000000000000000000000":
            logger.debug(f"Skipping mint event for token {token_id}")
            return

        # Skip burn events (to zero address)
        if to_address == "0x0000000000000000000000000000000000000000":
            logger.debug(f"Skipping burn event for token {token_id}")
            return

        platform_wallet_lower = PLATFORM_WALLET.lower()

        # Determine transfer type
        is_from_platform = from_address == platform_wallet_lower
        is_to_platform = to_address == platform_wallet_lower

        if is_from_platform and is_to_platform:
            # Internal platform transfer - ignore
            logger.debug(f"Skipping internal platform transfer for token {token_id}")
            return

        if is_from_platform:
            # Bridge OUT completion - platform sent to user
            # This should be handled by our bridge-out/confirm endpoint, but log it
            logger.debug(f"Bridge-out transfer detected for token {token_id} to {to_address[:10]}...")
            return

        if is_to_platform:
            # Bridge IN - user sent to platform
            # This should be handled by our bridge-in endpoint, but log it
            logger.debug(f"Bridge-in transfer detected for token {token_id} from {from_address[:10]}...")
            return

        # External transfer! (e.g., OpenSea sale between two external wallets)
        await self._handle_external_transfer(token_id, from_address, to_address, tx_hash, block_number)

    async def _handle_external_transfer(
        self,
        token_id: int,
        from_wallet: str,
        to_wallet: str,
        tx_hash: str,
        block_number: int
    ) -> None:
        """Handle transfer between external wallets (OpenSea sale, etc)."""
        db = SessionLocal()
        try:
            # Find the forged item
            item = db.query(ForgedAchievement).filter(
                ForgedAchievement.token_id == token_id,
                ForgedAchievement.chain_id == CHAIN_ID
            ).first()

            if not item:
                logger.warning(f"Transfer for unknown token {token_id} - not in our database")
                return

            # Verify item is in bridged status
            if item.bridge_status != BridgeStatus.BRIDGED.value:
                logger.warning(
                    f"Transfer for token {token_id} but status is {item.bridge_status}, "
                    f"expected 'bridged'. Updating anyway."
                )

            # Find if new owner has a Ashbane account
            new_owner_wallet = db.query(WalletAccount).filter(
                WalletAccount.wallet_address == to_wallet
            ).first()

            old_owner_id = item.current_owner_id

            if new_owner_wallet:
                # New owner has a Ashbane account - they can bridge in!
                new_owner = db.query(User).filter(User.id == new_owner_wallet.user_id).first()
                logger.info(
                    f"External transfer: token {token_id} -> {new_owner.username if new_owner else 'unknown'} "
                    f"(wallet: {to_wallet[:10]}...)"
                )

                # Update ownership in database
                item.current_owner_id = new_owner_wallet.user_id
                item.external_owner_wallet = to_wallet
                item.owned_since = datetime.utcnow()
                item.trade_count = (item.trade_count or 0) + 1
                # Keep bridge_status as 'bridged' - new owner must explicitly bridge in

            else:
                # New owner doesn't have Ashbane account (external-only)
                logger.info(
                    f"External transfer: token {token_id} -> external wallet {to_wallet[:10]}... "
                    f"(no Ashbane account)"
                )

                # Clear Ashbane ownership, track external wallet
                item.current_owner_id = None
                item.external_owner_wallet = to_wallet
                item.trade_count = (item.trade_count or 0) + 1

            # Log the transfer
            bridge_tx = BridgeTransaction(
                forged_achievement_id=item.id,
                transaction_type="external_transfer",
                from_user_id=old_owner_id,
                to_user_id=new_owner_wallet.user_id if new_owner_wallet else None,
                from_wallet=from_wallet,
                to_wallet=to_wallet,
                tx_hash=tx_hash,
                requested_at=datetime.utcnow(),
                completed_at=datetime.utcnow(),
                status="completed"
            )
            db.add(bridge_tx)
            db.commit()

            logger.info(
                f"External transfer recorded: token {token_id}, "
                f"trade count now {item.trade_count}, "
                f"tx: {tx_hash[:16]}..."
            )

            # TODO: Could emit notification here for in-game broadcast
            # e.g., "Your Hand of Malenia sold on OpenSea!"

        except Exception as e:
            logger.error(f"Error handling external transfer: {e}", exc_info=True)
            db.rollback()
        finally:
            db.close()

    def get_status(self) -> dict:
        """Get current indexer status."""
        return {
            "running": self._is_running,
            "last_processed_block": self._last_processed_block,
            "chain_id": CHAIN_ID,
            "contract_address": CONTRACT_ADDRESS,
            "platform_wallet": PLATFORM_WALLET,
            "poll_interval_seconds": POLL_INTERVAL_SECONDS,
        }


# Global instance
transfer_indexer_service = TransferIndexerService()


async def manual_poll() -> int:
    """Manually trigger a poll (for testing/admin)."""
    return await transfer_indexer_service.poll_transfers()


def get_indexer_status() -> dict:
    """Get indexer status (for admin API)."""
    return transfer_indexer_service.get_status()
