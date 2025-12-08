"""Add effort scoring columns to achievements

Revision ID: a6a32e5e4c8b
Revises: 73ef66a227f8
Create Date: 2025-06-07 13:05:02.265458

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a6a32e5e4c8b'
down_revision: Union[str, None] = '73ef66a227f8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.add_column('achievements', sa.Column('effort_score', sa.Float(), nullable=False, server_default='0'))
    op.add_column('achievements', sa.Column('effort_auto', sa.Boolean(), nullable=False, server_default='1'))
    op.add_column('achievements', sa.Column('effort_notes', sa.Text(), nullable=True))

def downgrade():
    op.drop_column('achievements', 'effort_notes')
    op.drop_column('achievements', 'effort_auto')
    op.drop_column('achievements', 'effort_score')