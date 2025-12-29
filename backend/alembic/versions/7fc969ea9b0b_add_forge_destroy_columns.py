"""add_forge_destroy_columns

Revision ID: 7fc969ea9b0b
Revises: 32ef49652a56
Create Date: 2025-12-29 03:27:19.683806

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7fc969ea9b0b'
down_revision: Union[str, None] = '32ef49652a56'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add soft-delete columns for destroyed forged items."""
    op.add_column('forged_achievements', sa.Column('destroyed_at', sa.DateTime(), nullable=True))
    op.add_column('forged_achievements', sa.Column('destroyed_reason', sa.String(50), nullable=True))
    op.add_column('forged_achievements', sa.Column('destroyed_by_user_id', sa.Integer(), nullable=True))
    op.add_column('forged_achievements', sa.Column('previous_owner_id', sa.Integer(), nullable=True))

    # Index for finding destroyed items (for admin restore)
    op.create_index('ix_forged_achievements_destroyed', 'forged_achievements', ['destroyed_at'])


def downgrade() -> None:
    """Remove soft-delete columns."""
    op.drop_index('ix_forged_achievements_destroyed', table_name='forged_achievements')
    op.drop_column('forged_achievements', 'previous_owner_id')
    op.drop_column('forged_achievements', 'destroyed_by_user_id')
    op.drop_column('forged_achievements', 'destroyed_reason')
    op.drop_column('forged_achievements', 'destroyed_at')
