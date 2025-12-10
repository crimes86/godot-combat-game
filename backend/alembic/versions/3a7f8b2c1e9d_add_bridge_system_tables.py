"""add_bridge_system_tables

Revision ID: 3a7f8b2c1e9d
Revises: 2cf60fac46f9
Create Date: 2025-12-09 14:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3a7f8b2c1e9d'
down_revision: Union[str, None] = '2cf60fac46f9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add bridge system columns and tables."""
    # Add bridge columns to forged_achievements
    op.add_column('forged_achievements', sa.Column('bridge_status', sa.String(20), nullable=True, server_default='in_game'))
    op.add_column('forged_achievements', sa.Column('bridge_requested_at', sa.DateTime(), nullable=True))
    op.add_column('forged_achievements', sa.Column('bridge_completed_at', sa.DateTime(), nullable=True))
    op.add_column('forged_achievements', sa.Column('external_owner_wallet', sa.String(42), nullable=True))

    # Create indexes for bridge columns
    op.create_index('ix_forged_achievements_bridge_status', 'forged_achievements', ['bridge_status'])
    op.create_index('ix_forged_achievements_external_owner_wallet', 'forged_achievements', ['external_owner_wallet'])

    # Create bridge_transactions table
    op.create_table(
        'bridge_transactions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('forged_achievement_id', sa.Integer(), nullable=False),
        sa.Column('transaction_type', sa.String(20), nullable=False),
        sa.Column('from_user_id', sa.Integer(), nullable=True),
        sa.Column('to_user_id', sa.Integer(), nullable=True),
        sa.Column('from_wallet', sa.String(42), nullable=True),
        sa.Column('to_wallet', sa.String(42), nullable=True),
        sa.Column('tx_hash', sa.String(66), nullable=True),
        sa.Column('requested_at', sa.DateTime(), nullable=True),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
        sa.Column('status', sa.String(20), nullable=True, server_default='pending'),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['forged_achievement_id'], ['forged_achievements.id'], ),
        sa.ForeignKeyConstraint(['from_user_id'], ['users.id'], ),
        sa.ForeignKeyConstraint(['to_user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_bridge_transactions_id', 'bridge_transactions', ['id'])
    op.create_index('ix_bridge_transactions_forged_achievement_id', 'bridge_transactions', ['forged_achievement_id'])
    op.create_index('ix_bridge_transactions_requested_at', 'bridge_transactions', ['requested_at'])
    op.create_index('ix_bridge_transactions_status', 'bridge_transactions', ['status'])


def downgrade() -> None:
    """Remove bridge system columns and tables."""
    # Drop bridge_transactions table
    op.drop_index('ix_bridge_transactions_status', 'bridge_transactions')
    op.drop_index('ix_bridge_transactions_requested_at', 'bridge_transactions')
    op.drop_index('ix_bridge_transactions_forged_achievement_id', 'bridge_transactions')
    op.drop_index('ix_bridge_transactions_id', 'bridge_transactions')
    op.drop_table('bridge_transactions')

    # Drop bridge column indexes
    op.drop_index('ix_forged_achievements_external_owner_wallet', 'forged_achievements')
    op.drop_index('ix_forged_achievements_bridge_status', 'forged_achievements')

    # Drop bridge columns from forged_achievements
    op.drop_column('forged_achievements', 'external_owner_wallet')
    op.drop_column('forged_achievements', 'bridge_completed_at')
    op.drop_column('forged_achievements', 'bridge_requested_at')
    op.drop_column('forged_achievements', 'bridge_status')
