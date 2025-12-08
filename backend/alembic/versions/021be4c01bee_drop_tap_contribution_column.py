"""drop_tap_contribution_column

Revision ID: 021be4c01bee
Revises: 5e6cf000cc3c
Create Date: 2025-12-07 12:02:46.772629

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '021be4c01bee'
down_revision: Union[str, None] = '5e6cf000cc3c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Remove deprecated TAP contribution column (replaced by effort_score system)."""
    op.drop_column('provider_accounts', 'tap_contribution')


def downgrade() -> None:
    """Restore tap_contribution column."""
    op.add_column('provider_accounts', sa.Column('tap_contribution', sa.Integer(), nullable=False, server_default='0'))
