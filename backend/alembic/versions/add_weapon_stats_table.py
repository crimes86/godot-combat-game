"""add weapon_stats table

Revision ID: 5c9d3e2f4a7b
Revises: 4b8d2e1f3a6c
Create Date: 2024-12-10

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '5c9d3e2f4a7b'
down_revision: Union[str, None] = '4b8d2e1f3a6c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'weapon_stats',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('forged_achievement_id', sa.Integer(), nullable=False),

        # Kill stats
        sa.Column('kills_total', sa.Integer(), default=0),
        sa.Column('kills_by_type', sa.JSON(), default=dict),
        sa.Column('kills_elite', sa.Integer(), default=0),
        sa.Column('kills_boss', sa.Integer(), default=0),
        sa.Column('kills_pvp', sa.Integer(), default=0),

        # Damage stats
        sa.Column('damage_total', sa.Integer(), default=0),
        sa.Column('damage_max_hit', sa.Integer(), default=0),
        sa.Column('damage_overkill', sa.Integer(), default=0),

        # Crit stats
        sa.Column('crits_landed', sa.Integer(), default=0),
        sa.Column('hits_total', sa.Integer(), default=0),
        sa.Column('weakpoints_destroyed', sa.Integer(), default=0),
        sa.Column('chain_max_reached', sa.Integer(), default=0),

        # Usage stats
        sa.Column('swings_total', sa.Integer(), default=0),
        sa.Column('shots_fired', sa.Integer(), default=0),
        sa.Column('bursts_fired', sa.Integer(), default=0),
        sa.Column('time_equipped_seconds', sa.Integer(), default=0),
        sa.Column('sessions_equipped', sa.Integer(), default=0),

        # Negative stats
        sa.Column('deaths_equipped', sa.Integer(), default=0),
        sa.Column('misses_total', sa.Integer(), default=0),
        sa.Column('battles_lost', sa.Integer(), default=0),
        sa.Column('show_negative_stats', sa.Boolean(), default=True),

        # Milestones
        sa.Column('first_equipped_at', sa.DateTime(), nullable=True),
        sa.Column('first_kill_at', sa.DateTime(), nullable=True),
        sa.Column('first_crit_at', sa.DateTime(), nullable=True),
        sa.Column('milestone_100_kills_at', sa.DateTime(), nullable=True),
        sa.Column('milestone_1000_kills_at', sa.DateTime(), nullable=True),
        sa.Column('milestone_10000_kills_at', sa.DateTime(), nullable=True),

        # Level system
        sa.Column('level', sa.Integer(), default=0),
        sa.Column('experience', sa.Integer(), default=0),

        # Achievements
        sa.Column('achievements', sa.JSON(), default=list),

        # Sync tracking
        sa.Column('last_synced_at', sa.DateTime(), nullable=True),
        sa.Column('last_synced_from_ip', sa.String(45), nullable=True),

        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['forged_achievement_id'], ['forged_achievements.id']),
        sa.UniqueConstraint('forged_achievement_id', name='uq_weapon_stats_forged_achievement'),
    )
    op.create_index('ix_weapon_stats_forged_achievement_id', 'weapon_stats', ['forged_achievement_id'])


def downgrade() -> None:
    op.drop_index('ix_weapon_stats_forged_achievement_id', 'weapon_stats')
    op.drop_table('weapon_stats')
