"""add_guest_account_fields

Revision ID: 1718512c17ab
Revises: d9e3b2c4f5a6
Create Date: 2026-01-06 22:28:53.702380

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '1718512c17ab'
down_revision: Union[str, None] = 'd9e3b2c4f5a6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Add guest account fields to users table (renamed to local account in next migration)
    op.add_column('users', sa.Column('is_guest', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('users', sa.Column('recovery_code_hash', sa.String(128), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('users', 'recovery_code_hash')
    op.drop_column('users', 'is_guest')
