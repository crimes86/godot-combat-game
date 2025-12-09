"""
Chain Batching Service for trade provenance.

Batches trades and syncs them to Polygon blockchain every 5 minutes.
This is invisible to users - they just see fast in-game trades.

The backend database is the source of truth for gameplay.
The chain is just for provenance/permanence.

Uses the RelayerService for all blockchain interactions.
"""
import os
import asyncio
import logging
from datetime import datetime
from typing import List, Optional
from sqlalchemy.orm import Session as DbSession

from app.models import ItemTrade, ForgedAchievement, WalletAccount
from app.database import SessionLocal

logger = logging.getLogger(__name__)

# Configuration
BATCH_INTERVAL_SECONDS = int(os.getenv("CHAIN_BATCH_INTERVAL", "300"))  # 5 minutes
MAX_BATCH_SIZE = int(os.getenv("CHAIN_BATCH_SIZE", "50"))  # Max trades per batch


class ChainBatchingService:
    """Service to batch trades and sync to blockchain using RelayerService."""

    def __init__(self):
        self._is_running = False
        self._task: Optional[asyncio.Task] = None
        self._relayer = None

    def start(self) -> None:
        """Start the background batching task."""
        if self._is_running:
            logger.warning("Chain batching service already running")
            return

        # Initialize relayer
        try:
            from app.services.relayer_service import relayer_service
            if not relayer_service.initialize():
                logger.warning("Chain batching disabled - relayer not configured")
                return
            self._relayer = relayer_service
        except Exception as e:
            logger.warning(f"Chain batching disabled - failed to init relayer: {e}")
            return

        self._is_running = True
        self._task = asyncio.create_task(self._batch_loop())
        logger.info(f"Chain batching service started (interval: {BATCH_INTERVAL_SECONDS}s)")

    def stop(self) -> None:
        """Stop the background batching task."""
        self._is_running = False
        if self._task:
            self._task.cancel()
            self._task = None
        logger.info("Chain batching service stopped")

    async def _batch_loop(self) -> None:
        """Main loop that processes pending trades every interval."""
        while self._is_running:
            try:
                await asyncio.sleep(BATCH_INTERVAL_SECONDS)
                await self.process_pending_trades()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in batch loop: {e}", exc_info=True)
                # Continue running, will retry next interval

    async def process_pending_trades(self) -> int:
        """
        Process pending trades and submit to chain.
        Returns the number of trades processed.
        """
        db = SessionLocal()
        try:
            # Get pending trades (no chain_tx_hash)
            pending = db.query(ItemTrade).filter(
                ItemTrade.chain_tx_hash.is_(None)
            ).order_by(ItemTrade.traded_at).limit(MAX_BATCH_SIZE).all()

            if not pending:
                logger.debug("No pending trades to batch")
                return 0

            logger.info(f"Processing batch of {len(pending)} trades")

            # Prepare batch data
            batch_data = self._prepare_batch(pending, db)
            if not batch_data:
                return 0

            # Submit to chain
            tx_hash = await self._submit_batch(batch_data)

            if tx_hash:
                # Mark trades as synced
                for trade in pending:
                    trade.chain_tx_hash = tx_hash
                    trade.chain_recorded_at = datetime.utcnow()
                db.commit()

                logger.info(f"Batch submitted: {tx_hash} ({len(pending)} trades)")
                return len(pending)
            else:
                logger.error("Failed to submit batch to chain")
                return 0

        except Exception as e:
            logger.error(f"Error processing pending trades: {e}", exc_info=True)
            db.rollback()
            return 0
        finally:
            db.close()

    def _prepare_batch(self, trades: List[ItemTrade], db: DbSession) -> Optional[List[dict]]:
        """
        Prepare batch data for chain submission.
        Returns list of trade dicts for relayer_service.record_trade_batch().
        """
        trade_records = []

        for trade in trades:
            forged = trade.forged_item
            if not forged or not forged.token_id:
                logger.warning(f"Trade {trade.id} has no token_id, skipping")
                continue

            # Get the new owner's wallet address
            recipient = trade.to_user
            if not recipient:
                logger.warning(f"Trade {trade.id} has no recipient, skipping")
                continue

            # Find recipient's wallet
            recipient_wallet = db.query(WalletAccount).filter(
                WalletAccount.user_id == recipient.id
            ).first()

            # Find sender's wallet
            sender = trade.from_user
            sender_wallet = None
            if sender:
                sender_wallet = db.query(WalletAccount).filter(
                    WalletAccount.user_id == sender.id
                ).first()

            # Use zero address as placeholder if no wallet linked
            from_addr = sender_wallet.wallet_address if sender_wallet else "0x0000000000000000000000000000000000000000"
            to_addr = recipient_wallet.wallet_address if recipient_wallet else "0x0000000000000000000000000000000000000000"

            trade_records.append({
                'token_id': forged.token_id,
                'from_wallet': from_addr,
                'to_wallet': to_addr,
                'price_gold': trade.price_gold or 0,
                'traded_at': int(trade.traded_at.timestamp()),
                'tx_ref': f"trade_{trade.id}"  # Unique reference for replay protection
            })

        return trade_records if trade_records else None

    async def _submit_batch(self, batch_data: List[dict]) -> Optional[str]:
        """
        Submit batch to blockchain using relayer service.
        Returns tx hash on success, None on failure.
        """
        if not self._relayer:
            logger.error("Relayer not initialized")
            return None

        try:
            # Run in executor since web3 is synchronous
            import asyncio
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None,
                self._relayer.record_trade_batch,
                batch_data,
                None  # Let relayer generate batch_id
            )

            if result and result.get('tx_hash'):
                return result['tx_hash']
            elif result and result.get('skipped'):
                logger.debug("Batch skipped (empty)")
                return None
            else:
                logger.error("Failed to submit batch to chain")
                return None

        except Exception as e:
            logger.error(f"Error submitting batch to chain: {e}", exc_info=True)
            return None


# Global instance
chain_batching_service = ChainBatchingService()


def get_pending_trades_count() -> int:
    """Get count of pending trades waiting for chain sync."""
    db = SessionLocal()
    try:
        return db.query(ItemTrade).filter(
            ItemTrade.chain_tx_hash.is_(None)
        ).count()
    finally:
        db.close()


async def manual_process_batch() -> int:
    """Manually trigger batch processing (for testing/admin)."""
    return await chain_batching_service.process_pending_trades()
