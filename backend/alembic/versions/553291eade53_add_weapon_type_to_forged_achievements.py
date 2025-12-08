"""add_weapon_type_to_forged_achievements

Revision ID: 553291eade53
Revises: c6db71635464
Create Date: 2025-12-08 15:25:39.333363

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '553291eade53'
down_revision: Union[str, None] = 'c6db71635464'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add weapon_type column to forged_achievements table."""
    op.add_column('forged_achievements', sa.Column('weapon_type', sa.String(32), nullable=True))


def downgrade() -> None:
    """Remove weapon_type column from forged_achievements table."""
    op.drop_column('forged_achievements', 'weapon_type')
