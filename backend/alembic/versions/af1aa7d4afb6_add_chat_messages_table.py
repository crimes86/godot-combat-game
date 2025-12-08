"""add_chat_messages_table

Revision ID: af1aa7d4afb6
Revises: a3dcbc1f1b56
Create Date: 2025-12-08 00:58:43.469995

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'af1aa7d4afb6'
down_revision: Union[str, None] = 'a3dcbc1f1b56'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create chat_messages table for tiered chat rooms."""
    op.create_table(
        'chat_messages',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True, index=True),
        sa.Column('room', sa.String(32), nullable=False, index=True),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('message_type', sa.String(20), server_default='chat'),
        sa.Column('created_at', sa.DateTime(), server_default=sa.func.now(), index=True),
        sa.Column('achievement_credit_id', sa.Integer(), sa.ForeignKey('achievement_credits.id'), nullable=True),
    )


def downgrade() -> None:
    """Drop chat_messages table."""
    op.drop_table('chat_messages')
