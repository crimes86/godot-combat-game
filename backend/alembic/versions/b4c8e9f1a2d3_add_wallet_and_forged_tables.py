"""add wallet and forged achievement tables

Revision ID: b4c8e9f1a2d3
Revises: 3683c9c30dcf
Create Date: 2025-12-06

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b4c8e9f1a2d3'
down_revision: Union[str, None] = '3683c9c30dcf'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add wallet_accounts and forged_achievements tables."""
    from sqlalchemy import inspect

    bind = op.get_bind()
    inspector = inspect(bind)
    existing_tables = inspector.get_table_names()

    # Wallet accounts table
    if 'wallet_accounts' not in existing_tables:
        op.create_table('wallet_accounts',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('wallet_address', sa.String(42), nullable=False),
            sa.Column('chain_id', sa.Integer(), nullable=False, server_default='8453'),
            sa.Column('linked_at', sa.DateTime(), nullable=True),
            sa.Column('current_nonce', sa.String(32), nullable=True),
            sa.Column('nonce_expires_at', sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(['user_id'], ['users.id']),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('user_id', 'chain_id', name='unique_wallet_per_chain'),
        )
        op.create_index('ix_wallet_accounts_id', 'wallet_accounts', ['id'], unique=False)
        op.create_index('ix_wallet_accounts_wallet_address', 'wallet_accounts', ['wallet_address'], unique=True)

    # Forged achievements table
    if 'forged_achievements' not in existing_tables:
        op.create_table('forged_achievements',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('achievement_credit_id', sa.Integer(), nullable=False),
            sa.Column('wallet_account_id', sa.Integer(), nullable=False),
            sa.Column('token_id', sa.Integer(), nullable=False),
            sa.Column('contract_address', sa.String(42), nullable=False),
            sa.Column('chain_id', sa.Integer(), nullable=False),
            sa.Column('tx_hash', sa.String(66), nullable=False),
            sa.Column('forged_at', sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(['achievement_credit_id'], ['achievement_credits.id']),
            sa.ForeignKeyConstraint(['wallet_account_id'], ['wallet_accounts.id']),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('achievement_credit_id', name='unique_forged_achievement'),
        )
        op.create_index('ix_forged_achievements_id', 'forged_achievements', ['id'], unique=False)


def downgrade() -> None:
    """Remove wallet and forged tables."""
    op.drop_index('ix_forged_achievements_id', table_name='forged_achievements')
    op.drop_table('forged_achievements')
    op.drop_index('ix_wallet_accounts_wallet_address', table_name='wallet_accounts')
    op.drop_index('ix_wallet_accounts_id', table_name='wallet_accounts')
    op.drop_table('wallet_accounts')
