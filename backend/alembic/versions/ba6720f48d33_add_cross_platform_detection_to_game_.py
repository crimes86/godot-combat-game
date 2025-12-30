"""add cross platform detection to game discoveries

Revision ID: ba6720f48d33
Revises: d7a45ac92340
Create Date: 2025-12-30 04:10:03.705010

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ba6720f48d33'
down_revision: Union[str, None] = 'd7a45ac92340'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('pending_game_discoveries',
        sa.Column('cross_platform_match_id', sa.Integer(), nullable=True))
    op.add_column('pending_game_discoveries',
        sa.Column('is_cross_platform', sa.Boolean(), server_default='false', nullable=False))
    op.create_index('ix_pending_game_discoveries_cross_platform_match_id',
        'pending_game_discoveries', ['cross_platform_match_id'])
    op.create_index('ix_pending_game_discoveries_is_cross_platform',
        'pending_game_discoveries', ['is_cross_platform'])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index('ix_pending_game_discoveries_is_cross_platform', 'pending_game_discoveries')
    op.drop_index('ix_pending_game_discoveries_cross_platform_match_id', 'pending_game_discoveries')
    op.drop_column('pending_game_discoveries', 'is_cross_platform')
    op.drop_column('pending_game_discoveries', 'cross_platform_match_id')
