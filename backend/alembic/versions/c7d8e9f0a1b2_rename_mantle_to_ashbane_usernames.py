"""rename_mantle_to_ashbane_usernames

Revision ID: c7d8e9f0a1b2
Revises: bc9250799915
Create Date: 2025-12-17 12:00:00.000000

Renames all existing usernames from 'mantle-xxxxx' to 'ashbane-xxxxx'
and 'Ashbane-xxxxx' to 'ashbane-xxxxx' for brand consistency (lowercase).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c7d8e9f0a1b2'
down_revision: Union[str, None] = 'bc9250799915'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Rename mantle- and Ashbane- usernames to ashbane-"""
    # First rename mantle- to ashbane-
    op.execute(
        "UPDATE users SET username = REPLACE(username, 'mantle-', 'ashbane-') "
        "WHERE username LIKE 'mantle-%'"
    )
    # Then normalize Ashbane- (capital A) to ashbane- (lowercase)
    op.execute(
        "UPDATE users SET username = REPLACE(username, 'Ashbane-', 'ashbane-') "
        "WHERE username LIKE 'Ashbane-%'"
    )


def downgrade() -> None:
    """Revert ashbane- usernames back to Ashbane-"""
    op.execute(
        "UPDATE users SET username = REPLACE(username, 'ashbane-', 'Ashbane-') "
        "WHERE username LIKE 'ashbane-%'"
    )
