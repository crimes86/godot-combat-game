"""add device_codes table

Revision ID: e1234567890a
Revises: d8e9f0a1b2c3
Create Date: 2025-01-01 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'e1234567890a'
down_revision = 'd8e9f0a1b2c3'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('device_codes',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('device_code', sa.String(64), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('username', sa.String(), nullable=True),
        sa.Column('session_token', sa.String(), nullable=True),
        sa.Column('beta_verified', sa.Boolean(), nullable=True, default=False),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_device_codes_device_code'), 'device_codes', ['device_code'], unique=True)
    op.create_index(op.f('ix_device_codes_id'), 'device_codes', ['id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_device_codes_id'), table_name='device_codes')
    op.drop_index(op.f('ix_device_codes_device_code'), table_name='device_codes')
    op.drop_table('device_codes')
