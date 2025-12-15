"""add last_credited_count to provider accounts

Revision ID: bc9250799915
Revises: 6bc663495cc4
Create Date: 2025-12-14 17:24:51.694202

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'bc9250799915'
down_revision: Union[str, None] = '6bc663495cc4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('provider_accounts', sa.Column('last_credited_count', sa.Integer(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('provider_accounts', 'last_credited_count')
