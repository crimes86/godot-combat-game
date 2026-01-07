"""rename_guest_to_local_account

Revision ID: 3b6f65a6c311
Revises: 1718512c17ab
Create Date: 2026-01-06 22:31:21.531707

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3b6f65a6c311'
down_revision: Union[str, None] = '1718512c17ab'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column('users', 'is_guest', new_column_name='is_local_account')
    op.alter_column('users', 'recovery_code_hash', new_column_name='password_hash')


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column('users', 'is_local_account', new_column_name='is_guest')
    op.alter_column('users', 'password_hash', new_column_name='recovery_code_hash')
