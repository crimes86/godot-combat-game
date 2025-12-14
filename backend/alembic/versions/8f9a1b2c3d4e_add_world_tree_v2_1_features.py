"""add world tree v2.1 features

Revision ID: 8f9a1b2c3d4e
Revises: 7e8f9a0b1c2d
Create Date: 2024-12-14

Adds World Tree v2.1 features:
- Dual ownership (original_owner_id + current_guild_id)
- Champion migration and decay system
- Warehouse safe + overflow storage
- Tree ranks and building system
- Resource mines with active collection
- Bane siege system with scheduled windows
- Seasonal (all-time) leaderboard
- Extended decay timers (90 days dynamic, 14 days champion)
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '8f9a1b2c3d4e'
down_revision: Union[str, None] = '7e8f9a0b1c2d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ===== EXTEND seed_plots TABLE =====

    # Core ownership (Fix #1 - Dual ownership)
    op.add_column('seed_plots', sa.Column('original_owner_id', sa.Integer(), nullable=True))
    op.add_column('seed_plots', sa.Column('last_ownership_transfer', sa.DateTime(), nullable=True))
    op.add_column('seed_plots', sa.Column('current_guild_id', sa.String(64), nullable=True))
    op.add_column('seed_plots', sa.Column('last_guild_change', sa.DateTime(), nullable=True))

    # Backfill original_owner_id from owner_id for existing rows
    op.execute('UPDATE seed_plots SET original_owner_id = owner_id WHERE owner_id IS NOT NULL')

    # Migration/Champion (Fix #2 - Tree duplication)
    op.add_column('seed_plots', sa.Column('is_origin_champion', sa.Boolean(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('champion_since', sa.DateTime(), nullable=True))
    op.add_column('seed_plots', sa.Column('is_decaying', sa.Boolean(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('decay_complete_at', sa.DateTime(), nullable=True))
    op.add_column('seed_plots', sa.Column('migration_expires', sa.DateTime(), nullable=True))
    op.add_column('seed_plots', sa.Column('original_chunk_id', sa.Integer(), nullable=True))

    # Tree rank system
    op.add_column('seed_plots', sa.Column('tree_rank', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('tree_health', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('tree_max_health', sa.Integer(), nullable=False, server_default='0'))

    # Guild/Faction
    op.add_column('seed_plots', sa.Column('guild_name', sa.String(128), nullable=True))
    op.add_column('seed_plots', sa.Column('faction', sa.String(32), nullable=False, server_default='individual'))

    # Upgrades
    op.add_column('seed_plots', sa.Column('upgrade_started_at', sa.DateTime(), nullable=True))
    op.add_column('seed_plots', sa.Column('upgrade_target_rank', sa.Integer(), nullable=True))

    # Watering system
    op.add_column('seed_plots', sa.Column('last_watered', sa.DateTime(), nullable=True))
    op.add_column('seed_plots', sa.Column('times_watered', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('growth_bonus_accumulated', sa.Float(), nullable=False, server_default='0.0'))

    # Respawn binding
    op.add_column('seed_plots', sa.Column('allow_public_binding', sa.Boolean(), nullable=False, server_default='0'))

    # Warehouse (Fix #6 - Safe + Overflow storage)
    op.add_column('seed_plots', sa.Column('warehouse_safe_gold', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('warehouse_safe_wood', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('warehouse_safe_stone', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('warehouse_safe_gems', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('warehouse_overflow_gold', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('warehouse_overflow_wood', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('warehouse_overflow_stone', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('seed_plots', sa.Column('warehouse_overflow_gems', sa.Integer(), nullable=False, server_default='0'))

    # Resource mines
    op.add_column('seed_plots', sa.Column('claimed_mine_ids', sa.Text(), nullable=True))  # JSON stored as TEXT

    # Bane defense (Fix #10 - Scheduled windows)
    op.add_column('seed_plots', sa.Column('defense_window_hour', sa.Integer(), nullable=False, server_default='20'))
    op.add_column('seed_plots', sa.Column('defense_window_timezone_offset', sa.Integer(), nullable=False, server_default='0'))

    # Add indexes for new columns
    op.create_index('ix_seed_plots_original_owner_id', 'seed_plots', ['original_owner_id'])
    op.create_index('ix_seed_plots_current_guild_id', 'seed_plots', ['current_guild_id'])
    op.create_index('ix_seed_plots_is_origin_champion', 'seed_plots', ['is_origin_champion'])
    op.create_index('ix_seed_plots_tree_rank', 'seed_plots', ['tree_rank'])
    op.create_index('ix_seed_plots_faction', 'seed_plots', ['faction'])

    # Note: SQLite doesn't support adding foreign keys after table creation
    # The foreign key relationship is implied but not enforced at DB level
    # This is fine for our use case as we control the application layer

    # ===== CREATE resource_mines TABLE (Fix #7) =====
    op.create_table(
        'resource_mines',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('shard_id', sa.String(32), nullable=False),
        sa.Column('chunk_id', sa.Integer(), nullable=False),
        sa.Column('mine_type', sa.String(16), nullable=False),  # "gold", "stone", "wood", "gems"
        sa.Column('position_x', sa.Float(), nullable=False),
        sa.Column('position_y', sa.Float(), nullable=False),

        # Ownership
        sa.Column('owner_tree_id', sa.Integer(), nullable=True),

        # Collection tracking (Fix #7 - Active collection)
        sa.Column('last_collected', sa.DateTime(), nullable=True),
        sa.Column('last_collector', sa.String(64), nullable=True),
        sa.Column('quick_collect_count', sa.Integer(), nullable=False, server_default='0'),

        # Accumulated resources
        sa.Column('resources_accumulated', sa.Integer(), nullable=False, server_default='0'),

        # Timestamps
        sa.Column('created_at', sa.DateTime(), nullable=False),

        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['owner_tree_id'], ['seed_plots.id']),
    )

    # Create indexes for resource_mines
    op.create_index('ix_resource_mines_shard_id', 'resource_mines', ['shard_id'])
    op.create_index('ix_resource_mines_chunk_id', 'resource_mines', ['chunk_id'])
    op.create_index('ix_resource_mines_owner_tree_id', 'resource_mines', ['owner_tree_id'])
    op.create_index('ix_resource_mines_mine_type', 'resource_mines', ['mine_type'])

    # ===== CREATE seed_plot_buildings TABLE =====
    op.create_table(
        'seed_plot_buildings',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('seed_plot_id', sa.Integer(), nullable=False),
        sa.Column('building_type', sa.String(32), nullable=False),  # "vendor", "warehouse", "shrine", "crafting"
        sa.Column('position_slot', sa.String(1), nullable=False),  # "A" through "F"

        # Health
        sa.Column('health', sa.Integer(), nullable=False, server_default='1000'),
        sa.Column('max_health', sa.Integer(), nullable=False, server_default='1000'),

        # Protection
        sa.Column('is_protected', sa.Boolean(), nullable=False, server_default='0'),

        # Migration (Fix #2)
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('activation_cost', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('original_cost', sa.Integer(), nullable=False),

        # Timestamps
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('destroyed_at', sa.DateTime(), nullable=True),
        sa.Column('activated_at', sa.DateTime(), nullable=True),

        # Vendor data (stored as TEXT for JSON)
        sa.Column('vendor_inventory', sa.Text(), nullable=True),
        sa.Column('vendor_prices', sa.Text(), nullable=True),
        sa.Column('total_sales', sa.Integer(), nullable=False, server_default='0'),

        # Shrine data
        sa.Column('shrine_buff_type', sa.String(32), nullable=True),

        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['seed_plot_id'], ['seed_plots.id']),
    )

    # Create indexes for seed_plot_buildings
    op.create_index('ix_seed_plot_buildings_seed_plot_id', 'seed_plot_buildings', ['seed_plot_id'])
    op.create_index('ix_seed_plot_buildings_building_type', 'seed_plot_buildings', ['building_type'])
    op.create_index('ix_seed_plot_buildings_is_active', 'seed_plot_buildings', ['is_active'])

    # ===== CREATE bane_stones TABLE (Fix #5, #10) =====
    op.create_table(
        'bane_stones',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('shard_id', sa.String(32), nullable=False),
        sa.Column('target_tree_id', sa.Integer(), nullable=False),
        sa.Column('attacker_guild_id', sa.String(64), nullable=False),

        # Health
        sa.Column('health', sa.Integer(), nullable=False, server_default='50000'),
        sa.Column('max_health', sa.Integer(), nullable=False, server_default='50000'),

        # Timeline (Fix #10 - Scheduled windows)
        sa.Column('planted_at', sa.DateTime(), nullable=False),
        sa.Column('window_start', sa.DateTime(), nullable=True),
        sa.Column('window_end', sa.DateTime(), nullable=True),

        # Status
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('outcome', sa.String(16), nullable=True),  # "defenders_win", "attackers_win", "cancelled"

        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['target_tree_id'], ['seed_plots.id']),
    )

    # Create indexes for bane_stones
    op.create_index('ix_bane_stones_shard_id', 'bane_stones', ['shard_id'])
    op.create_index('ix_bane_stones_target_tree_id', 'bane_stones', ['target_tree_id'])
    op.create_index('ix_bane_stones_attacker_guild_id', 'bane_stones', ['attacker_guild_id'])
    op.create_index('ix_bane_stones_is_active', 'bane_stones', ['is_active'])

    # ===== CREATE seasonal_rankings TABLE (Fix #9) =====
    op.create_table(
        'seasonal_rankings',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('shard_id', sa.String(32), nullable=False),
        sa.Column('tree_id', sa.Integer(), nullable=False),
        sa.Column('guild_id', sa.String(64), nullable=False),

        # All-time stats
        sa.Column('total_contribution', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_kills', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_boss_kills', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_waterings', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('weeks_participated', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('weeks_won', sa.Integer(), nullable=False, server_default='0'),

        # Milestones
        sa.Column('highest_rank_achieved', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('first_contribution', sa.DateTime(), nullable=True),
        sa.Column('last_contribution', sa.DateTime(), nullable=True),

        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['tree_id'], ['seed_plots.id']),
    )

    # Create indexes for seasonal_rankings
    op.create_index('ix_seasonal_rankings_shard_id', 'seasonal_rankings', ['shard_id'])
    op.create_index('ix_seasonal_rankings_tree_id', 'seasonal_rankings', ['tree_id'])
    op.create_index('ix_seasonal_rankings_guild_id', 'seasonal_rankings', ['guild_id'])
    op.create_index('ix_seasonal_rankings_total_contribution', 'seasonal_rankings', ['total_contribution'])

    # ===== UPDATE world_tree_contributions TABLE (Fix #11 - Rebalanced scoring) =====
    # Add boss_kills column
    op.add_column('world_tree_contributions', sa.Column('boss_kills', sa.Integer(), nullable=False, server_default='0'))


def downgrade() -> None:
    # Drop seasonal_rankings table
    op.drop_index('ix_seasonal_rankings_total_contribution', 'seasonal_rankings')
    op.drop_index('ix_seasonal_rankings_guild_id', 'seasonal_rankings')
    op.drop_index('ix_seasonal_rankings_tree_id', 'seasonal_rankings')
    op.drop_index('ix_seasonal_rankings_shard_id', 'seasonal_rankings')
    op.drop_table('seasonal_rankings')

    # Drop bane_stones table
    op.drop_index('ix_bane_stones_is_active', 'bane_stones')
    op.drop_index('ix_bane_stones_attacker_guild_id', 'bane_stones')
    op.drop_index('ix_bane_stones_target_tree_id', 'bane_stones')
    op.drop_index('ix_bane_stones_shard_id', 'bane_stones')
    op.drop_table('bane_stones')

    # Drop seed_plot_buildings table
    op.drop_index('ix_seed_plot_buildings_is_active', 'seed_plot_buildings')
    op.drop_index('ix_seed_plot_buildings_building_type', 'seed_plot_buildings')
    op.drop_index('ix_seed_plot_buildings_seed_plot_id', 'seed_plot_buildings')
    op.drop_table('seed_plot_buildings')

    # Drop resource_mines table
    op.drop_index('ix_resource_mines_mine_type', 'resource_mines')
    op.drop_index('ix_resource_mines_owner_tree_id', 'resource_mines')
    op.drop_index('ix_resource_mines_chunk_id', 'resource_mines')
    op.drop_index('ix_resource_mines_shard_id', 'resource_mines')
    op.drop_table('resource_mines')

    # Remove boss_kills from world_tree_contributions
    op.drop_column('world_tree_contributions', 'boss_kills')

    # Remove seed_plots columns in reverse order
    op.drop_index('ix_seed_plots_faction', 'seed_plots')
    op.drop_index('ix_seed_plots_tree_rank', 'seed_plots')
    op.drop_index('ix_seed_plots_is_origin_champion', 'seed_plots')
    op.drop_index('ix_seed_plots_current_guild_id', 'seed_plots')
    op.drop_index('ix_seed_plots_original_owner_id', 'seed_plots')

    op.drop_column('seed_plots', 'defense_window_timezone_offset')
    op.drop_column('seed_plots', 'defense_window_hour')
    op.drop_column('seed_plots', 'claimed_mine_ids')
    op.drop_column('seed_plots', 'warehouse_overflow_gems')
    op.drop_column('seed_plots', 'warehouse_overflow_stone')
    op.drop_column('seed_plots', 'warehouse_overflow_wood')
    op.drop_column('seed_plots', 'warehouse_overflow_gold')
    op.drop_column('seed_plots', 'warehouse_safe_gems')
    op.drop_column('seed_plots', 'warehouse_safe_stone')
    op.drop_column('seed_plots', 'warehouse_safe_wood')
    op.drop_column('seed_plots', 'warehouse_safe_gold')
    op.drop_column('seed_plots', 'allow_public_binding')
    op.drop_column('seed_plots', 'growth_bonus_accumulated')
    op.drop_column('seed_plots', 'times_watered')
    op.drop_column('seed_plots', 'last_watered')
    op.drop_column('seed_plots', 'upgrade_target_rank')
    op.drop_column('seed_plots', 'upgrade_started_at')
    op.drop_column('seed_plots', 'faction')
    op.drop_column('seed_plots', 'guild_name')
    op.drop_column('seed_plots', 'tree_max_health')
    op.drop_column('seed_plots', 'tree_health')
    op.drop_column('seed_plots', 'tree_rank')
    op.drop_column('seed_plots', 'original_chunk_id')
    op.drop_column('seed_plots', 'migration_expires')
    op.drop_column('seed_plots', 'decay_complete_at')
    op.drop_column('seed_plots', 'is_decaying')
    op.drop_column('seed_plots', 'champion_since')
    op.drop_column('seed_plots', 'is_origin_champion')
    op.drop_column('seed_plots', 'last_guild_change')
    op.drop_column('seed_plots', 'current_guild_id')
    op.drop_column('seed_plots', 'last_ownership_transfer')
    op.drop_column('seed_plots', 'original_owner_id')
