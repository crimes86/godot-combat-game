"""add_global_claim_tracking_to_achievement_credits

Revision ID: 7f27b3649bad
Revises: b4c8e9f1a2d3
Create Date: 2025-12-06 01:37:19.130265

Anti-exploit migration: Adds global claim tracking to prevent achievement duplication
when users unlink/relink provider accounts.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7f27b3649bad'
down_revision: Union[str, None] = 'b4c8e9f1a2d3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    Add global claim tracking fields to achievement_credits.

    This prevents the dupe exploit where users unlink a provider,
    create a new account, and re-claim the same achievements.
    """
    # 1. Add new columns (nullable first for backfill)
    op.add_column('achievement_credits', sa.Column('provider_name', sa.String(), nullable=True))
    op.add_column('achievement_credits', sa.Column('provider_user_id', sa.String(), nullable=True))
    op.add_column('achievement_credits', sa.Column('is_original_claim', sa.Boolean(), nullable=True))

    # 2. Backfill from provider_accounts table
    # For SQLite (no UPDATE FROM), we use a subquery approach
    connection = op.get_bind()

    # Backfill provider_name and provider_user_id from linked provider_account
    connection.execute(sa.text("""
        UPDATE achievement_credits
        SET provider_name = (
            SELECT provider_name FROM provider_accounts
            WHERE provider_accounts.id = achievement_credits.provider_account_id
        ),
        provider_user_id = (
            SELECT provider_user_id FROM provider_accounts
            WHERE provider_accounts.id = achievement_credits.provider_account_id
        ),
        is_original_claim = 1
    """))

    # 3. Handle any orphaned credits (provider_account deleted) - mark as original but use placeholder
    # These are legacy orphans that we'll treat as original claims
    connection.execute(sa.text("""
        UPDATE achievement_credits
        SET provider_name = 'unknown',
            provider_user_id = 'orphan_' || CAST(id AS TEXT),
            is_original_claim = 1
        WHERE provider_name IS NULL
    """))

    # 4. Make columns NOT NULL now that backfill is complete
    # SQLite doesn't support ALTER COLUMN, so we need to recreate for strict NOT NULL
    # For now, we'll rely on application logic to enforce NOT NULL on new inserts
    # The columns are populated, but SQLite can't change nullability easily

    # 5. Create indexes for performance
    op.create_index('ix_achievement_credits_provider_name', 'achievement_credits', ['provider_name'])
    op.create_index('ix_achievement_credits_provider_user_id', 'achievement_credits', ['provider_user_id'])
    op.create_index('ix_achievement_credits_is_original_claim', 'achievement_credits', ['is_original_claim'])

    # 6. Drop old constraint and create new one
    # Note: SQLite doesn't support DROP CONSTRAINT, so for SQLite we skip this
    # The new constraint will be enforced by application logic
    # For PostgreSQL in production, uncomment these:
    # op.drop_constraint('unique_credit_per_provider_achievement_character', 'achievement_credits', type_='unique')
    # op.create_unique_constraint(
    #     'unique_global_achievement_claim',
    #     'achievement_credits',
    #     ['provider_name', 'provider_user_id', 'achievement_id', 'character_name', 'realm_slug']
    # )


def downgrade() -> None:
    """Remove global claim tracking fields."""
    op.drop_index('ix_achievement_credits_is_original_claim', 'achievement_credits')
    op.drop_index('ix_achievement_credits_provider_user_id', 'achievement_credits')
    op.drop_index('ix_achievement_credits_provider_name', 'achievement_credits')
    op.drop_column('achievement_credits', 'is_original_claim')
    op.drop_column('achievement_credits', 'provider_user_id')
    op.drop_column('achievement_credits', 'provider_name')
