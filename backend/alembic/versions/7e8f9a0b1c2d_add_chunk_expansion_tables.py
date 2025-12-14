"""add chunk expansion and world tree tables

Revision ID: 7e8f9a0b1c2d
Revises: 6d0e4f3a5b8c
Create Date: 2024-12-13

Adds:
- seed_plots table for chunk expansion claims
- active_chunks table for tracking loaded chunks
- world_tree_rankings table for weekly competition
- world_tree_contributions table for player contributions
- world_tree_blockchain_records table for on-chain records
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7e8f9a0b1c2d'
down_revision: Union[str, None] = '6d0e4f3a5b8c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create seed_plots table
    op.create_table(
        'seed_plots',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('shard_id', sa.String(32), nullable=False),
        sa.Column('chunk_id', sa.Integer(), nullable=False),
        sa.Column('position_x', sa.Float(), nullable=False),
        sa.Column('position_y', sa.Float(), nullable=False),

        # Ownership
        sa.Column('owner_id', sa.Integer(), nullable=True),
        sa.Column('claimed_at', sa.DateTime(), nullable=True),
        sa.Column('last_contribution_at', sa.DateTime(), nullable=True),

        # State tracking
        sa.Column('state', sa.String(16), nullable=False, server_default='unclaimed'),
        sa.Column('claim_cost', sa.Integer(), nullable=False, server_default='1000'),

        # Statistics
        sa.Column('total_gold_contributed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_wood_contributed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_stone_contributed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_kills', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_time_minutes', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('contribution_score', sa.Integer(), nullable=False, server_default='0'),

        # Decay tracking
        sa.Column('abandoned_at', sa.DateTime(), nullable=True),
        sa.Column('decay_warning_sent', sa.Boolean(), server_default='0'),

        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id']),
    )

    # Create indexes for seed_plots
    op.create_index('ix_seed_plots_shard_id', 'seed_plots', ['shard_id'])
    op.create_index('ix_seed_plots_chunk_id', 'seed_plots', ['chunk_id'])
    op.create_index('ix_seed_plots_owner_id', 'seed_plots', ['owner_id'])
    op.create_index('ix_seed_plots_state', 'seed_plots', ['state'])
    op.create_index('ix_seed_plots_shard_chunk', 'seed_plots', ['shard_id', 'chunk_id'], unique=True)

    # Create active_chunks table
    op.create_table(
        'active_chunks',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('shard_id', sa.String(32), nullable=False),
        sa.Column('chunk_id', sa.Integer(), nullable=False),
        sa.Column('chunk_type', sa.String(16), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('player_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('is_loaded', sa.Boolean(), nullable=False, server_default='1'),

        sa.PrimaryKeyConstraint('id'),
    )

    # Create indexes for active_chunks
    op.create_index('ix_active_chunks_shard_id', 'active_chunks', ['shard_id'])
    op.create_index('ix_active_chunks_chunk_id', 'active_chunks', ['chunk_id'])
    op.create_index('ix_active_chunks_shard_chunk', 'active_chunks', ['shard_id', 'chunk_id'], unique=True)

    # Create world_tree_rankings table
    op.create_table(
        'world_tree_rankings',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('shard_id', sa.String(32), nullable=False),
        sa.Column('week_number', sa.Integer(), nullable=False),
        sa.Column('week_start', sa.DateTime(), nullable=False),
        sa.Column('week_end', sa.DateTime(), nullable=False),

        # Winner info
        sa.Column('seed_plot_id', sa.Integer(), nullable=False),
        sa.Column('owner_id', sa.Integer(), nullable=False),
        sa.Column('total_score', sa.Integer(), nullable=False),
        sa.Column('rank', sa.Integer(), nullable=False),

        # Status
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('promoted_to_origin', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('promoted_at', sa.DateTime(), nullable=True),

        # Blockchain integration
        sa.Column('blockchain_record_id', sa.Integer(), nullable=True),
        sa.Column('blockchain_tx_hash', sa.String(66), nullable=True),
        sa.Column('recorded_on_chain_at', sa.DateTime(), nullable=True),

        # Ban tracking
        sa.Column('owner_banned_until', sa.DateTime(), nullable=True),

        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['seed_plot_id'], ['seed_plots.id']),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id']),
    )

    # Create indexes for world_tree_rankings
    op.create_index('ix_world_tree_rankings_shard_id', 'world_tree_rankings', ['shard_id'])
    op.create_index('ix_world_tree_rankings_week_number', 'world_tree_rankings', ['week_number'])
    op.create_index('ix_world_tree_rankings_owner_id', 'world_tree_rankings', ['owner_id'])
    op.create_index('ix_world_tree_rankings_is_active', 'world_tree_rankings', ['is_active'])
    op.create_index('ix_world_tree_rankings_shard_week', 'world_tree_rankings', ['shard_id', 'week_number'])

    # Create world_tree_contributions table
    op.create_table(
        'world_tree_contributions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('seed_plot_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('week_number', sa.Integer(), nullable=False),

        # Contribution breakdown
        sa.Column('gold_contributed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('wood_contributed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('stone_contributed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('gems_contributed', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('kills', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('time_minutes', sa.Integer(), nullable=False, server_default='0'),

        # Score
        sa.Column('contribution_score', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('rank', sa.Integer(), nullable=True),

        # Rewards
        sa.Column('rewards_claimed', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('rewards_claimed_at', sa.DateTime(), nullable=True),

        # Timestamps
        sa.Column('first_contribution_at', sa.DateTime(), nullable=False),
        sa.Column('last_contribution_at', sa.DateTime(), nullable=False),

        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['seed_plot_id'], ['seed_plots.id']),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
    )

    # Create indexes for world_tree_contributions
    op.create_index('ix_world_tree_contributions_seed_plot_id', 'world_tree_contributions', ['seed_plot_id'])
    op.create_index('ix_world_tree_contributions_user_id', 'world_tree_contributions', ['user_id'])
    op.create_index('ix_world_tree_contributions_week_number', 'world_tree_contributions', ['week_number'])
    op.create_index('ix_world_tree_contributions_score', 'world_tree_contributions', ['contribution_score'])


def downgrade() -> None:
    # Drop world_tree_contributions table
    op.drop_index('ix_world_tree_contributions_score', 'world_tree_contributions')
    op.drop_index('ix_world_tree_contributions_week_number', 'world_tree_contributions')
    op.drop_index('ix_world_tree_contributions_user_id', 'world_tree_contributions')
    op.drop_index('ix_world_tree_contributions_seed_plot_id', 'world_tree_contributions')
    op.drop_table('world_tree_contributions')

    # Drop world_tree_rankings table
    op.drop_index('ix_world_tree_rankings_shard_week', 'world_tree_rankings')
    op.drop_index('ix_world_tree_rankings_is_active', 'world_tree_rankings')
    op.drop_index('ix_world_tree_rankings_owner_id', 'world_tree_rankings')
    op.drop_index('ix_world_tree_rankings_week_number', 'world_tree_rankings')
    op.drop_index('ix_world_tree_rankings_shard_id', 'world_tree_rankings')
    op.drop_table('world_tree_rankings')

    # Drop active_chunks table
    op.drop_index('ix_active_chunks_shard_chunk', 'active_chunks')
    op.drop_index('ix_active_chunks_chunk_id', 'active_chunks')
    op.drop_index('ix_active_chunks_shard_id', 'active_chunks')
    op.drop_table('active_chunks')

    # Drop seed_plots table
    op.drop_index('ix_seed_plots_shard_chunk', 'seed_plots')
    op.drop_index('ix_seed_plots_state', 'seed_plots')
    op.drop_index('ix_seed_plots_owner_id', 'seed_plots')
    op.drop_index('ix_seed_plots_chunk_id', 'seed_plots')
    op.drop_index('ix_seed_plots_shard_id', 'seed_plots')
    op.drop_table('seed_plots')
