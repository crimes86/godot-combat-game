"""add_friendships_table

Revision ID: a3dcbc1f1b56
Revises: 021be4c01bee
Create Date: 2025-12-07 12:34:38.891722

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a3dcbc1f1b56'
down_revision: Union[str, None] = '021be4c01bee'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create friendships table for social features."""
    op.create_table(
        'friendships',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('friend_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('status', sa.String(20), nullable=False, server_default='pending'),
        sa.Column('created_at', sa.DateTime(), server_default=sa.func.now()),
        sa.Column('accepted_at', sa.DateTime(), nullable=True),
        sa.UniqueConstraint('user_id', 'friend_id', name='unique_friendship_request'),
    )


def downgrade() -> None:
    """Drop friendships table."""
    op.drop_table('friendships')
