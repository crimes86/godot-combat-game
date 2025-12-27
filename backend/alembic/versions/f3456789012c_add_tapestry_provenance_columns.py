"""Add Tapestry provenance columns to forged_achievements

Revision ID: f3456789012c
Revises: ec1bc7e437d0
Create Date: 2024-12-27

Adds source_provider and provider_accent_color columns to ForgedAchievement
for cross-platform provenance tracking ("The Tapestry" system).
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f3456789012c'
down_revision = 'ec1bc7e437d0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add source_provider column (which platform the achievement was earned on)
    op.add_column('forged_achievements',
        sa.Column('source_provider', sa.String(32), nullable=True)
    )

    # Add provider_accent_color column (visual accent color for rim glow)
    op.add_column('forged_achievements',
        sa.Column('provider_accent_color', sa.String(7), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('forged_achievements', 'provider_accent_color')
    op.drop_column('forged_achievements', 'source_provider')
