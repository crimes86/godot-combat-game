"""make achievement_credit_id nullable for debug forges

Revision ID: 16047a42763b
Revises: f3456789012c
Create Date: 2025-12-28 02:33:43.460123

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '16047a42763b'
down_revision: Union[str, None] = 'f3456789012c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column('forged_achievements', 'achievement_credit_id',
                    existing_type=sa.Integer(),
                    nullable=True)


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column('forged_achievements', 'achievement_credit_id',
                    existing_type=sa.Integer(),
                    nullable=False)
