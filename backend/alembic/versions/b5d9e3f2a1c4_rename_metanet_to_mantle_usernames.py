"""rename_metanet_to_mantle_usernames

Revision ID: b5d9e3f2a1c4
Revises: 8f4e2a1b3c5d
Create Date: 2025-12-08 22:00:00.000000

Renames all existing usernames from 'metanet-xxxxx' to 'mantle-xxxxx'
for brand consistency.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b5d9e3f2a1c4'
down_revision: Union[str, None] = '8f4e2a1b3c5d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Rename metanet- usernames to mantle-"""
    # Use raw SQL to update usernames
    # SQLite uses REPLACE(), works for simple prefix swap
    op.execute(
        "UPDATE users SET username = REPLACE(username, 'metanet-', 'mantle-') "
        "WHERE username LIKE 'metanet-%'"
    )


def downgrade() -> None:
    """Revert mantle- usernames back to metanet-"""
    op.execute(
        "UPDATE users SET username = REPLACE(username, 'mantle-', 'metanet-') "
        "WHERE username LIKE 'mantle-%'"
    )
