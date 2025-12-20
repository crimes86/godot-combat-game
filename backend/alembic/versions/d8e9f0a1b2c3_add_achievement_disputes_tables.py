"""add_achievement_disputes_tables

Revision ID: d8e9f0a1b2c3
Revises: c7d8e9f0a1b2
Create Date: 2025-12-18 10:00:00.000000

Adds tables for community-driven achievement rarity disputes.
Players can dispute classifications, which are broadcast to the
appropriate tier chat room for peer review and voting.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd8e9f0a1b2c3'
down_revision: Union[str, None] = 'c7d8e9f0a1b2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create achievement_disputes and dispute_votes tables."""
    # Achievement disputes table
    op.create_table(
        'achievement_disputes',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('achievement_id', sa.Integer(), sa.ForeignKey('achievements.id'), nullable=False, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('chat_message_id', sa.Integer(), sa.ForeignKey('chat_messages.id'), nullable=True, index=True),

        # Current classification snapshot
        sa.Column('current_effort_score', sa.Float(), nullable=False),
        sa.Column('current_rarity', sa.String(16), nullable=False),
        sa.Column('scoring_method', sa.String(32), nullable=True),
        sa.Column('scoring_input', sa.String(64), nullable=True),

        # Suggested classification
        sa.Column('suggested_rarity', sa.String(16), nullable=False),
        sa.Column('reason', sa.Text(), nullable=False),

        # Voting
        sa.Column('votes_up', sa.Integer(), server_default='0'),
        sa.Column('votes_down', sa.Integer(), server_default='0'),
        sa.Column('votes_threshold', sa.Integer(), server_default='5'),

        # Status
        sa.Column('status', sa.String(16), nullable=False, server_default='pending', index=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.func.now(), index=True),
        sa.Column('expires_at', sa.DateTime(), nullable=True),
        sa.Column('resolved_at', sa.DateTime(), nullable=True),

        # Admin override
        sa.Column('admin_notes', sa.Text(), nullable=True),
        sa.Column('resolved_by_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=True),
    )

    # Dispute votes table
    op.create_table(
        'dispute_votes',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('dispute_id', sa.Integer(), sa.ForeignKey('achievement_disputes.id'), nullable=False, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False, index=True),
        sa.Column('vote', sa.Integer(), nullable=False),  # 1 = agree, -1 = disagree
        sa.Column('voted_at', sa.DateTime(), server_default=sa.func.now()),
        sa.UniqueConstraint('dispute_id', 'user_id', name='unique_dispute_vote'),
    )


def downgrade() -> None:
    """Drop dispute tables."""
    op.drop_table('dispute_votes')
    op.drop_table('achievement_disputes')
