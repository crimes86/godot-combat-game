"""add provider_username to provider_accounts

Revision ID: 81d197ee7132
Revises: b5d9e3f2a1c4
Create Date: 2025-12-09 09:25:43.377636

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '81d197ee7132'
down_revision: Union[str, None] = 'b5d9e3f2a1c4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('provider_accounts', sa.Column('provider_username', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('provider_accounts', 'provider_username')
