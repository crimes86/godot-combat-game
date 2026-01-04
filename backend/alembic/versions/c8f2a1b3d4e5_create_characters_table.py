"""Create characters table for vendor purchase validation

Revision ID: c8f2a1b3d4e5
Revises: 1af0e83df1e1
Create Date: 2026-01-03

Adds Character model to store per-character gold and inventory,
enabling server-side vendor purchase validation.
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'c8f2a1b3d4e5'
down_revision = '1af0e83df1e1'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'characters',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(64), nullable=False),
        sa.Column('level', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('gold', sa.Integer(), nullable=False, server_default='100'),
        sa.Column('character_data', sa.JSON(), nullable=False, server_default='{}'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('last_played_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'name', name='unique_character_name_per_user')
    )
    op.create_index(op.f('ix_characters_id'), 'characters', ['id'], unique=False)
    op.create_index(op.f('ix_characters_user_id'), 'characters', ['user_id'], unique=False)
    op.create_index(op.f('ix_characters_is_active'), 'characters', ['is_active'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_characters_is_active'), table_name='characters')
    op.drop_index(op.f('ix_characters_user_id'), table_name='characters')
    op.drop_index(op.f('ix_characters_id'), table_name='characters')
    op.drop_table('characters')
