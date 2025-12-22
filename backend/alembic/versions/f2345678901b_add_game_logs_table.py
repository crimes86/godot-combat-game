"""add game_logs table

Revision ID: f2345678901b
Revises: e1234567890a
Create Date: 2025-01-01 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f2345678901b'
down_revision = 'e1234567890a'
branch_labels = None
depends_on = None


def upgrade():
    """Create game_logs table for client-side telemetry."""
    op.create_table('game_logs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('session_id', sa.String(36), nullable=True),
        sa.Column('device_id', sa.String(36), nullable=True),
        sa.Column('level', sa.Integer(), nullable=False),
        sa.Column('category', sa.String(32), nullable=True),
        sa.Column('message', sa.Text(), nullable=False),
        sa.Column('client_timestamp', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.func.now(), nullable=True),
        sa.Column('client_version', sa.String(16), nullable=True),
        sa.Column('platform', sa.String(16), nullable=True),
        sa.Column('is_host', sa.Boolean(), nullable=True, default=False),
        sa.Column('ip_address', sa.String(45), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    # Create indexes for common query patterns
    op.create_index(op.f('ix_game_logs_user_id'), 'game_logs', ['user_id'], unique=False)
    op.create_index(op.f('ix_game_logs_session_id'), 'game_logs', ['session_id'], unique=False)
    op.create_index(op.f('ix_game_logs_device_id'), 'game_logs', ['device_id'], unique=False)
    op.create_index(op.f('ix_game_logs_category'), 'game_logs', ['category'], unique=False)
    op.create_index(op.f('ix_game_logs_created_at'), 'game_logs', ['created_at'], unique=False)


def downgrade():
    """Drop game_logs table."""
    op.drop_index(op.f('ix_game_logs_created_at'), table_name='game_logs')
    op.drop_index(op.f('ix_game_logs_category'), table_name='game_logs')
    op.drop_index(op.f('ix_game_logs_device_id'), table_name='game_logs')
    op.drop_index(op.f('ix_game_logs_session_id'), table_name='game_logs')
    op.drop_index(op.f('ix_game_logs_user_id'), table_name='game_logs')
    op.drop_table('game_logs')
