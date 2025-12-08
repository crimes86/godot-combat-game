"""add_forged_item_properties

Revision ID: c6db71635464
Revises: af1aa7d4afb6
Create Date: 2025-12-08 15:03:41.140851

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c6db71635464'
down_revision: Union[str, None] = 'af1aa7d4afb6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add item properties to forged_achievements table."""
    # Item identity
    op.add_column('forged_achievements', sa.Column('item_type', sa.String(32), nullable=True))
    op.add_column('forged_achievements', sa.Column('item_id', sa.String(64), nullable=True))
    op.add_column('forged_achievements', sa.Column('item_name', sa.String(128), nullable=True))
    op.add_column('forged_achievements', sa.Column('item_rarity', sa.String(16), nullable=True))

    # Visual properties
    op.add_column('forged_achievements', sa.Column('effect_intensity', sa.Float, nullable=True))
    op.add_column('forged_achievements', sa.Column('effect_name', sa.String(32), nullable=True))
    op.add_column('forged_achievements', sa.Column('glow_color', sa.String(7), nullable=True))

    # Metadata
    op.add_column('forged_achievements', sa.Column('effort_tier', sa.String(16), nullable=True))
    op.add_column('forged_achievements', sa.Column('vintage_years', sa.Integer, nullable=True))
    op.add_column('forged_achievements', sa.Column('is_secret', sa.Boolean, nullable=True))


def downgrade() -> None:
    """Remove item properties from forged_achievements table."""
    op.drop_column('forged_achievements', 'is_secret')
    op.drop_column('forged_achievements', 'vintage_years')
    op.drop_column('forged_achievements', 'effort_tier')
    op.drop_column('forged_achievements', 'glow_color')
    op.drop_column('forged_achievements', 'effect_name')
    op.drop_column('forged_achievements', 'effect_intensity')
    op.drop_column('forged_achievements', 'item_rarity')
    op.drop_column('forged_achievements', 'item_name')
    op.drop_column('forged_achievements', 'item_id')
    op.drop_column('forged_achievements', 'item_type')
