"""add_is_admin_and_last_sync_at

Revision ID: 122352061fc7
Revises: 7f27b3649bad
Create Date: 2025-12-06 02:14:37.276169

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '122352061fc7'
down_revision: Union[str, None] = '7f27b3649bad'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    Add is_admin to users and last_sync_at to provider_accounts.

    - is_admin: Bypass sync cooldowns for testing
    - last_sync_at: Track when provider was last synced (15 min cooldown)
    """
    # Add is_admin to users (default False)
    op.add_column('users', sa.Column('is_admin', sa.Boolean(), nullable=True))

    # Backfill existing users to False
    connection = op.get_bind()
    connection.execute(sa.text("UPDATE users SET is_admin = 0 WHERE is_admin IS NULL"))

    # Add last_sync_at to provider_accounts
    op.add_column('provider_accounts', sa.Column('last_sync_at', sa.DateTime(), nullable=True))


def downgrade() -> None:
    """Remove is_admin and last_sync_at columns."""
    op.drop_column('provider_accounts', 'last_sync_at')
    op.drop_column('users', 'is_admin')
