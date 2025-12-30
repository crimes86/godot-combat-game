"""add_pending_game_discoveries_table

Revision ID: d7a45ac92340
Revises: 100c8948e9d0
Create Date: 2025-12-29 16:48:50.507093

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd7a45ac92340'
down_revision: Union[str, None] = '100c8948e9d0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create pending_game_discoveries table for dynamic Tapestry discovery."""
    op.create_table(
        'pending_game_discoveries',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),

        # Discovery source
        sa.Column('discovered_by_user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True, index=True),
        sa.Column('source_provider', sa.String(32), nullable=False, index=True),

        # Game identification
        sa.Column('provider_game_id', sa.String(128), nullable=False, index=True),
        sa.Column('game_name', sa.String(256), nullable=False),

        # Discovery metadata
        sa.Column('achievement_count', sa.Integer(), default=0),
        sa.Column('sample_achievements', sa.JSON(), nullable=True),

        # Cross-platform research
        sa.Column('cross_platform_notes', sa.Text(), nullable=True),
        sa.Column('available_on_steam', sa.Boolean(), nullable=True),
        sa.Column('available_on_xbox', sa.Boolean(), nullable=True),
        sa.Column('available_on_psn', sa.Boolean(), nullable=True),
        sa.Column('steam_app_id', sa.String(32), nullable=True),
        sa.Column('xbox_title_id', sa.String(64), nullable=True),
        sa.Column('psn_np_id', sa.String(64), nullable=True),

        # Forge eligibility
        sa.Column('has_forge_items', sa.Boolean(), nullable=True),
        sa.Column('forge_item_count', sa.Integer(), nullable=True),

        # Status tracking
        sa.Column('status', sa.String(20), default='pending', index=True),
        sa.Column('priority', sa.Integer(), default=0),
        sa.Column('discovery_count', sa.Integer(), default=1),

        # Timestamps
        sa.Column('first_discovered_at', sa.DateTime(), nullable=True, index=True),
        sa.Column('last_seen_at', sa.DateTime(), nullable=True),
        sa.Column('reviewed_at', sa.DateTime(), nullable=True),

        # Admin handling
        sa.Column('reviewed_by_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('admin_notes', sa.Text(), nullable=True),
    )

    # Create unique constraint on provider + game_id to prevent duplicates
    op.create_index(
        'ix_pending_game_unique',
        'pending_game_discoveries',
        ['source_provider', 'provider_game_id'],
        unique=True
    )


def downgrade() -> None:
    """Drop pending_game_discoveries table."""
    op.drop_index('ix_pending_game_unique', table_name='pending_game_discoveries')
    op.drop_table('pending_game_discoveries')
