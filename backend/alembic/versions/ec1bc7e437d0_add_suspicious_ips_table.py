"""add_suspicious_ips_table

Revision ID: ec1bc7e437d0
Revises: f2345678901b
Create Date: 2025-12-26 19:17:11.886143

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ec1bc7e437d0'
down_revision: Union[str, None] = 'f2345678901b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create suspicious_ips table for tracking scanner/bot IPs."""
    op.create_table(
        'suspicious_ips',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('ip_address', sa.String(45), nullable=False, index=True),
        sa.Column('detection_type', sa.String(32), nullable=False),
        sa.Column('threat_level', sa.String(16), default='low'),
        sa.Column('hit_count', sa.Integer(), default=1),
        sa.Column('paths_hit', sa.JSON(), nullable=True),
        sa.Column('user_agents', sa.JSON(), nullable=True),
        sa.Column('first_seen', sa.DateTime(), index=True),
        sa.Column('last_seen', sa.DateTime()),
        sa.Column('is_blocked', sa.Boolean(), default=False),
        sa.Column('notes', sa.Text(), nullable=True),
    )


def downgrade() -> None:
    """Drop suspicious_ips table."""
    op.drop_table('suspicious_ips')
