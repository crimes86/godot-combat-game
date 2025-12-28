"""change token_id to bigint

Revision ID: 378f0826126e
Revises: 16047a42763b
Create Date: 2025-12-28 02:35:18.029026

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '378f0826126e'
down_revision: Union[str, None] = '16047a42763b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column('forged_achievements', 'token_id',
                    existing_type=sa.Integer(),
                    type_=sa.BigInteger(),
                    existing_nullable=True)


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column('forged_achievements', 'token_id',
                    existing_type=sa.BigInteger(),
                    type_=sa.Integer(),
                    existing_nullable=True)
