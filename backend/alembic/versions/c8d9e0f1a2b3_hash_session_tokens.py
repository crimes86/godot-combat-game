"""hash_session_tokens

Revision ID: c8d9e0f1a2b3
Revises: ba6720f48d33
Create Date: 2025-12-30

Security: Session tokens are now stored as SHA-256 hashes instead of plaintext.
This migration invalidates all existing sessions (users must re-login).

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c8d9e0f1a2b3'
down_revision: Union[str, None] = 'ba6720f48d33'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Hash session tokens for security."""
    # Delete all existing sessions (they have plaintext tokens, can't be migrated)
    # Users will need to re-login after this migration
    op.execute("DELETE FROM sessions")

    # Drop the old index
    op.drop_index('ix_sessions_token', table_name='sessions')

    # Rename column from 'token' to 'token_hash'
    op.alter_column('sessions', 'token', new_column_name='token_hash')

    # Create new index with updated name
    op.create_index('ix_sessions_token_hash', 'sessions', ['token_hash'], unique=True)


def downgrade() -> None:
    """Revert to plaintext tokens (not recommended)."""
    # Delete all sessions (hashed tokens can't be reverted)
    op.execute("DELETE FROM sessions")

    # Drop the new index
    op.drop_index('ix_sessions_token_hash', table_name='sessions')

    # Rename column back
    op.alter_column('sessions', 'token_hash', new_column_name='token')

    # Recreate old index
    op.create_index('ix_sessions_token', 'sessions', ['token'], unique=True)
