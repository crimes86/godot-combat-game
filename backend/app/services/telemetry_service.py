"""
Telemetry service for backend operation logging.

Provides a shared function for logging backend events without circular imports.
"""
import logging
from sqlalchemy.orm import Session as DbSession

from app.models import GameEventLog

logger = logging.getLogger(__name__)


def log_backend_event(
    db: DbSession,
    user_id: int,
    character_id: int,
    event_type: str,
    event_data: dict,
    ip_address: str = None
):
    """
    Log a backend operation event for monitoring and auditing.

    Event types:
    - vendor_purchase: Item purchased from vendor
    - vendor_sell: Item sold to vendor
    - character_save: Character data saved (logout)
    - character_load: Character data loaded (login)
    """
    try:
        event = GameEventLog(
            user_id=user_id,
            character_id=character_id,
            event_type=event_type,
            event_data=event_data,
            ip_address=ip_address,
            is_suspicious=False
        )
        db.add(event)
        # Don't commit here - let the caller's transaction handle it
    except Exception as e:
        logger.warning(f"Failed to log backend event: {e}")
