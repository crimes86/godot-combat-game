"""add unlocked_at to achievement_credits

Revision ID: 5e6cf000cc3c
Revises: 122352061fc7
Create Date: 2025-12-07 00:49:43.054875

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '5e6cf000cc3c'
down_revision: Union[str, None] = '122352061fc7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('achievement_credits', sa.Column('unlocked_at', sa.DateTime(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('achievement_credits', 'unlocked_at')
