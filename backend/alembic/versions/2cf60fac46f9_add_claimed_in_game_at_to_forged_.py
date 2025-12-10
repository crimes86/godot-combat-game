"""add_claimed_in_game_at_to_forged_achievements

Revision ID: 2cf60fac46f9
Revises: 81d197ee7132
Create Date: 2025-12-09 10:48:14.752158

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '2cf60fac46f9'
down_revision: Union[str, None] = '81d197ee7132'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('forged_achievements', sa.Column('claimed_in_game_at', sa.DateTime(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('forged_achievements', 'claimed_in_game_at')
