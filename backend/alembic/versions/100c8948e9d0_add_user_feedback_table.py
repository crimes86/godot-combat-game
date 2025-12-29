"""add_user_feedback_table

Revision ID: 100c8948e9d0
Revises: 7fc969ea9b0b
Create Date: 2025-12-29 03:47:24.985299

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '100c8948e9d0'
down_revision: Union[str, None] = '7fc969ea9b0b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create user_feedback table."""
    op.create_table(
        'user_feedback',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True, index=True),
        sa.Column('message', sa.Text(), nullable=False),
        sa.Column('page_url', sa.String(500), nullable=True),
        sa.Column('user_agent', sa.String(500), nullable=True),
        sa.Column('status', sa.String(20), default='new', index=True),
        sa.Column('admin_notes', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True, index=True),
        sa.Column('reviewed_at', sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    """Drop user_feedback table."""
    op.drop_table('user_feedback')
