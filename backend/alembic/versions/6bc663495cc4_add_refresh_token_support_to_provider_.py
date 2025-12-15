"""add refresh token support to provider accounts

Revision ID: 6bc663495cc4
Revises: 8f9a1b2c3d4e
Create Date: 2025-12-14 16:42:27.128961

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6bc663495cc4'
down_revision: Union[str, None] = '8f9a1b2c3d4e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('provider_accounts', sa.Column('refresh_token', sa.String(), nullable=True))
    op.add_column('provider_accounts', sa.Column('token_expires_at', sa.DateTime(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('provider_accounts', 'token_expires_at')
    op.drop_column('provider_accounts', 'refresh_token')
