"""add_appearance_data_to_users

Revision ID: 4b8d2e1f3a6c
Revises: 3a7f8b2c1e9d
Create Date: 2025-12-10 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4b8d2e1f3a6c'
down_revision: Union[str, None] = '3a7f8b2c1e9d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add appearance_data JSON column to users table for Armory character preview."""
    op.add_column('users', sa.Column('appearance_data', sa.JSON(), nullable=True))


def downgrade() -> None:
    """Remove appearance_data column from users table."""
    op.drop_column('users', 'appearance_data')
