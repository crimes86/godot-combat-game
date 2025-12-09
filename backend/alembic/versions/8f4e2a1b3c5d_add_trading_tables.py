"""add_trading_tables

Revision ID: 8f4e2a1b3c5d
Revises: 553291eade53
Create Date: 2025-12-08 18:30:00.000000

Adds trading system tables:
- Trading fields on forged_achievements (current_owner_id, trade_count, etc.)
- item_trades table (trade history log)
- trade_listings table (chat auction listings)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '8f4e2a1b3c5d'
down_revision: Union[str, None] = '553291eade53'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add trading tables and columns."""

    # Add trading columns to forged_achievements (SQLite-compatible batch mode)
    with op.batch_alter_table('forged_achievements') as batch_op:
        batch_op.add_column(sa.Column('current_owner_id', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('owned_since', sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column('trade_count', sa.Integer(), nullable=True, server_default='0'))
        batch_op.add_column(sa.Column('last_trade_at', sa.DateTime(), nullable=True))
        batch_op.create_index('ix_forged_achievements_current_owner_id', ['current_owner_id'])

    # Create item_trades table
    op.create_table(
        'item_trades',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('forged_item_id', sa.Integer(), sa.ForeignKey('forged_achievements.id'), nullable=False, index=True),
        sa.Column('from_user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('to_user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('traded_at', sa.DateTime(), nullable=False, index=True),
        sa.Column('price_gold', sa.Integer(), nullable=True),
        sa.Column('tax_applied', sa.Integer(), nullable=True, server_default='0'),
        sa.Column('trade_type', sa.String(20), nullable=True, server_default='direct'),
        sa.Column('chain_tx_hash', sa.String(66), nullable=True),
        sa.Column('chain_recorded_at', sa.DateTime(), nullable=True),
    )

    # Create trade_listings table
    op.create_table(
        'trade_listings',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('forged_item_id', sa.Integer(), sa.ForeignKey('forged_achievements.id'), nullable=False, index=True),
        sa.Column('seller_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('listing_type', sa.String(10), nullable=True, server_default='sell'),
        sa.Column('price_gold', sa.Integer(), nullable=False),
        sa.Column('message', sa.String(256), nullable=True),
        sa.Column('zone_id', sa.String(32), nullable=True),
        sa.Column('position_x', sa.Float(), nullable=True),
        sa.Column('position_y', sa.Float(), nullable=True),
        sa.Column('posted_at', sa.DateTime(), nullable=False, index=True),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.UniqueConstraint('forged_item_id', 'seller_id', name='unique_item_listing'),
    )


def downgrade() -> None:
    """Remove trading tables and columns."""

    # Drop trade_listings table
    op.drop_table('trade_listings')

    # Drop item_trades table
    op.drop_table('item_trades')

    # Remove trading columns from forged_achievements (SQLite-compatible batch mode)
    with op.batch_alter_table('forged_achievements') as batch_op:
        batch_op.drop_index('ix_forged_achievements_current_owner_id')
        batch_op.drop_column('last_trade_at')
        batch_op.drop_column('trade_count')
        batch_op.drop_column('owned_since')
        batch_op.drop_column('current_owner_id')
