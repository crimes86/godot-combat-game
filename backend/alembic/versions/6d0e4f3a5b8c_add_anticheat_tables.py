"""add anti-cheat tables and columns

Revision ID: 6d0e4f3a5b8c
Revises: 5c9d3e2f4a7b
Create Date: 2024-12-13

Adds:
- suspicious_activities table for telemetry logging
- Anti-cheat flags to weapon_stats table
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6d0e4f3a5b8c'
down_revision: Union[str, None] = '5c9d3e2f4a7b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add anti-cheat columns to weapon_stats
    op.add_column('weapon_stats', sa.Column('suspicious_flags', sa.Integer(), server_default='0'))
    op.add_column('weapon_stats', sa.Column('suspicious_score', sa.Float(), server_default='0.0'))
    op.add_column('weapon_stats', sa.Column('is_flagged', sa.Boolean(), server_default='0'))
    op.add_column('weapon_stats', sa.Column('flagged_at', sa.DateTime(), nullable=True))
    op.add_column('weapon_stats', sa.Column('review_notes', sa.Text(), nullable=True))

    # Create suspicious_activities table for telemetry
    op.create_table(
        'suspicious_activities',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('weapon_stats_id', sa.Integer(), nullable=True),
        sa.Column('forged_achievement_id', sa.Integer(), nullable=True),

        # What triggered the flag
        sa.Column('suspicious_type', sa.String(32), nullable=False),
        sa.Column('severity', sa.String(16), nullable=False, server_default='low'),

        # Evidence snapshot
        sa.Column('details', sa.JSON(), nullable=True),
        sa.Column('old_value', sa.JSON(), nullable=True),
        sa.Column('new_value', sa.JSON(), nullable=True),
        sa.Column('delta', sa.JSON(), nullable=True),

        # Request metadata
        sa.Column('client_ip', sa.String(45), nullable=True),
        sa.Column('user_agent', sa.String(256), nullable=True),
        sa.Column('client_timestamp', sa.DateTime(), nullable=True),
        sa.Column('server_timestamp', sa.DateTime(), nullable=False),

        # Session tracking
        sa.Column('session_id', sa.String(64), nullable=True),

        # Action taken
        sa.Column('action_taken', sa.String(32), server_default='logged'),

        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.ForeignKeyConstraint(['weapon_stats_id'], ['weapon_stats.id']),
        sa.ForeignKeyConstraint(['forged_achievement_id'], ['forged_achievements.id']),
    )

    # Create indexes for efficient querying
    op.create_index('ix_suspicious_activities_user_id', 'suspicious_activities', ['user_id'])
    op.create_index('ix_suspicious_activities_weapon_stats_id', 'suspicious_activities', ['weapon_stats_id'])
    op.create_index('ix_suspicious_activities_forged_achievement_id', 'suspicious_activities', ['forged_achievement_id'])
    op.create_index('ix_suspicious_activities_suspicious_type', 'suspicious_activities', ['suspicious_type'])
    op.create_index('ix_suspicious_activities_server_timestamp', 'suspicious_activities', ['server_timestamp'])


def downgrade() -> None:
    # Drop suspicious_activities table
    op.drop_index('ix_suspicious_activities_server_timestamp', 'suspicious_activities')
    op.drop_index('ix_suspicious_activities_suspicious_type', 'suspicious_activities')
    op.drop_index('ix_suspicious_activities_forged_achievement_id', 'suspicious_activities')
    op.drop_index('ix_suspicious_activities_weapon_stats_id', 'suspicious_activities')
    op.drop_index('ix_suspicious_activities_user_id', 'suspicious_activities')
    op.drop_table('suspicious_activities')

    # Remove anti-cheat columns from weapon_stats
    op.drop_column('weapon_stats', 'review_notes')
    op.drop_column('weapon_stats', 'flagged_at')
    op.drop_column('weapon_stats', 'is_flagged')
    op.drop_column('weapon_stats', 'suspicious_score')
    op.drop_column('weapon_stats', 'suspicious_flags')
