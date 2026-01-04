"""Create game_event_logs table for gameplay telemetry

Revision ID: d9e3b2c4f5a6
Revises: c8f2a1b3d4e5
Create Date: 2026-01-04

Adds GameEventLog model for tracking kills, loot pickups, and combat events.
Used for anti-cheat detection and audit trails.
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'd9e3b2c4f5a6'
down_revision = 'c8f2a1b3d4e5'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'game_event_logs',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('character_id', sa.Integer(), nullable=True),
        sa.Column('event_type', sa.String(32), nullable=False),
        sa.Column('event_data', sa.JSON(), nullable=False),
        sa.Column('session_id', sa.String(64), nullable=True),
        sa.Column('is_multiplayer', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('zone_id', sa.String(32), nullable=True),
        sa.Column('position_x', sa.Float(), nullable=True),
        sa.Column('position_y', sa.Float(), nullable=True),
        sa.Column('client_timestamp', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('ip_address', sa.String(45), nullable=True),
        sa.Column('client_version', sa.String(16), nullable=True),
        sa.Column('is_suspicious', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('suspicious_reason', sa.String(128), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.ForeignKeyConstraint(['character_id'], ['characters.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_game_event_logs_id'), 'game_event_logs', ['id'], unique=False)
    op.create_index(op.f('ix_game_event_logs_user_id'), 'game_event_logs', ['user_id'], unique=False)
    op.create_index(op.f('ix_game_event_logs_character_id'), 'game_event_logs', ['character_id'], unique=False)
    op.create_index(op.f('ix_game_event_logs_event_type'), 'game_event_logs', ['event_type'], unique=False)
    op.create_index(op.f('ix_game_event_logs_session_id'), 'game_event_logs', ['session_id'], unique=False)
    op.create_index(op.f('ix_game_event_logs_zone_id'), 'game_event_logs', ['zone_id'], unique=False)
    op.create_index(op.f('ix_game_event_logs_created_at'), 'game_event_logs', ['created_at'], unique=False)
    op.create_index(op.f('ix_game_event_logs_is_suspicious'), 'game_event_logs', ['is_suspicious'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_game_event_logs_is_suspicious'), table_name='game_event_logs')
    op.drop_index(op.f('ix_game_event_logs_created_at'), table_name='game_event_logs')
    op.drop_index(op.f('ix_game_event_logs_zone_id'), table_name='game_event_logs')
    op.drop_index(op.f('ix_game_event_logs_session_id'), table_name='game_event_logs')
    op.drop_index(op.f('ix_game_event_logs_event_type'), table_name='game_event_logs')
    op.drop_index(op.f('ix_game_event_logs_character_id'), table_name='game_event_logs')
    op.drop_index(op.f('ix_game_event_logs_user_id'), table_name='game_event_logs')
    op.drop_index(op.f('ix_game_event_logs_id'), table_name='game_event_logs')
    op.drop_table('game_event_logs')
