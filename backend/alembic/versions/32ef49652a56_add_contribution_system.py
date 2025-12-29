"""add_contribution_system

Revision ID: 32ef49652a56
Revises: 378f0826126e
Create Date: 2025-12-28 23:22:56.518313

Adds:
- CommunityContribution table for platform mappings and rarity disputes
- ContributionVote table for voting
- ContributorProfile table for tracking stats and rewards
- User columns for contributor cosmetics (active_title, active_badges, contributor_role)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '32ef49652a56'
down_revision: Union[str, None] = '378f0826126e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add community contribution system tables and user columns."""

    # Create contributor_profiles table
    op.create_table('contributor_profiles',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('total_approved', sa.Integer(), nullable=True, default=0),
        sa.Column('mappings_approved', sa.Integer(), nullable=True, default=0),
        sa.Column('disputes_approved', sa.Integer(), nullable=True, default=0),
        sa.Column('total_votes_cast', sa.Integer(), nullable=True, default=0),
        sa.Column('helpful_votes', sa.Integer(), nullable=True, default=0),
        sa.Column('rewards_claimed', sa.JSON(), nullable=True),
        sa.Column('rewards_available', sa.JSON(), nullable=True),
        sa.Column('contributor_role', sa.String(length=32), nullable=True, default='contributor'),
        sa.Column('leaderboard_rank', sa.Integer(), nullable=True),
        sa.Column('first_contribution_at', sa.DateTime(), nullable=True),
        sa.Column('last_contribution_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id')
    )
    op.create_index(op.f('ix_contributor_profiles_id'), 'contributor_profiles', ['id'], unique=False)
    op.create_index(op.f('ix_contributor_profiles_leaderboard_rank'), 'contributor_profiles', ['leaderboard_rank'], unique=False)
    op.create_index(op.f('ix_contributor_profiles_total_approved'), 'contributor_profiles', ['total_approved'], unique=False)
    op.create_index(op.f('ix_contributor_profiles_user_id'), 'contributor_profiles', ['user_id'], unique=True)

    # Create community_contributions table
    op.create_table('community_contributions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('contribution_type', sa.String(length=32), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('chat_message_id', sa.Integer(), nullable=True),
        sa.Column('data', sa.JSON(), nullable=False),
        sa.Column('reason', sa.Text(), nullable=False),
        sa.Column('votes_up', sa.Integer(), nullable=True, default=0),
        sa.Column('votes_down', sa.Integer(), nullable=True, default=0),
        sa.Column('votes_threshold', sa.Integer(), nullable=True, default=5),
        sa.Column('status', sa.String(length=16), nullable=False, default='pending'),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('expires_at', sa.DateTime(), nullable=True),
        sa.Column('resolved_at', sa.DateTime(), nullable=True),
        sa.Column('admin_notes', sa.Text(), nullable=True),
        sa.Column('resolved_by_id', sa.Integer(), nullable=True),
        sa.Column('credit_display', sa.String(length=64), nullable=True),
        sa.ForeignKeyConstraint(['chat_message_id'], ['chat_messages.id'], ),
        sa.ForeignKeyConstraint(['resolved_by_id'], ['users.id'], ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_community_contributions_contribution_type'), 'community_contributions', ['contribution_type'], unique=False)
    op.create_index(op.f('ix_community_contributions_created_at'), 'community_contributions', ['created_at'], unique=False)
    op.create_index(op.f('ix_community_contributions_id'), 'community_contributions', ['id'], unique=False)
    op.create_index(op.f('ix_community_contributions_status'), 'community_contributions', ['status'], unique=False)
    op.create_index(op.f('ix_community_contributions_user_id'), 'community_contributions', ['user_id'], unique=False)

    # Create contribution_votes table
    op.create_table('contribution_votes',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('contribution_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('vote', sa.Integer(), nullable=False),
        sa.Column('weight', sa.Integer(), nullable=True, default=1),
        sa.Column('voted_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['contribution_id'], ['community_contributions.id'], ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('contribution_id', 'user_id', name='unique_contribution_vote')
    )
    op.create_index(op.f('ix_contribution_votes_contribution_id'), 'contribution_votes', ['contribution_id'], unique=False)
    op.create_index(op.f('ix_contribution_votes_id'), 'contribution_votes', ['id'], unique=False)
    op.create_index(op.f('ix_contribution_votes_user_id'), 'contribution_votes', ['user_id'], unique=False)

    # Add contributor columns to users table
    op.add_column('users', sa.Column('active_title', sa.String(length=64), nullable=True))
    op.add_column('users', sa.Column('active_badges', sa.JSON(), nullable=True))
    op.add_column('users', sa.Column('contributor_role', sa.String(length=32), nullable=True))


def downgrade() -> None:
    """Remove community contribution system."""

    # Remove user columns
    op.drop_column('users', 'contributor_role')
    op.drop_column('users', 'active_badges')
    op.drop_column('users', 'active_title')

    # Drop contribution_votes
    op.drop_index(op.f('ix_contribution_votes_user_id'), table_name='contribution_votes')
    op.drop_index(op.f('ix_contribution_votes_id'), table_name='contribution_votes')
    op.drop_index(op.f('ix_contribution_votes_contribution_id'), table_name='contribution_votes')
    op.drop_table('contribution_votes')

    # Drop community_contributions
    op.drop_index(op.f('ix_community_contributions_user_id'), table_name='community_contributions')
    op.drop_index(op.f('ix_community_contributions_status'), table_name='community_contributions')
    op.drop_index(op.f('ix_community_contributions_id'), table_name='community_contributions')
    op.drop_index(op.f('ix_community_contributions_created_at'), table_name='community_contributions')
    op.drop_index(op.f('ix_community_contributions_contribution_type'), table_name='community_contributions')
    op.drop_table('community_contributions')

    # Drop contributor_profiles
    op.drop_index(op.f('ix_contributor_profiles_user_id'), table_name='contributor_profiles')
    op.drop_index(op.f('ix_contributor_profiles_total_approved'), table_name='contributor_profiles')
    op.drop_index(op.f('ix_contributor_profiles_leaderboard_rank'), table_name='contributor_profiles')
    op.drop_index(op.f('ix_contributor_profiles_id'), table_name='contributor_profiles')
    op.drop_table('contributor_profiles')
