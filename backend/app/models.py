from sqlalchemy import create_engine, Column, Integer, String, ForeignKey, JSON, DateTime, UniqueConstraint, Boolean, Float, Text
from sqlalchemy.orm import relationship, sessionmaker, Mapped, mapped_column
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
from .database import Base 

class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, index=True)
    is_admin = Column(Boolean, default=False, nullable=False)  # Bypass cooldowns, testing features

    # Relationships
    provider_accounts = relationship("ProviderAccount", back_populates="user")
    achievement_credits = relationship("AchievementCredit", back_populates="user")
    wallet_accounts = relationship("WalletAccount", back_populates="user")

class ProviderAccount(Base):
    __tablename__ = 'provider_accounts'
    __table_args__ = (
        UniqueConstraint("provider_name", "provider_user_id", name="uq_provider_profile"),
    )

    id = Column(Integer, primary_key=True, index=True)
    provider_name = Column(String)
    provider_user_id = Column(String)
    user_id = Column(Integer, ForeignKey('users.id'))
    profile_data = Column(JSON, nullable=True)
    # Soft-delete flag & timestamp
    is_active = Column(Boolean, nullable=False, default=True)
    unclaimed_at = Column(DateTime, nullable=True)
    access_token = Column(String, nullable=True)
    last_sync_at = Column(DateTime, nullable=True)  # For sync cooldown (15 min)

    # Relationships
    user = relationship("User", back_populates="provider_accounts")
    achievement_credits = relationship("AchievementCredit", back_populates="provider_account")



class Achievement(Base):
    __tablename__ = 'achievements'
    id = Column(Integer, primary_key=True, index=True)
    app_id = Column(String, index=True)
    api_name = Column(String, index=True)
    name = Column(String)
    rarity_tier = Column(String, default="Common")
    display_name = Column(String)
    description = Column(String)
    icon_url = Column(String)
    icon_gray_url = Column(String)
    hidden = Column(Boolean, default=False)
    default_value = Column(Integer, default=0)
    percent = Column(Float, nullable=True)
    effort_score = Column(Float, default=0)
    effort_auto = Column(Boolean, default=True)
    effort_notes = Column(Text, nullable=True)
    # relationships...

    # Relationships
    achievement_credits = relationship("AchievementCredit", back_populates="achievement")

    __table_args__ = (
        UniqueConstraint('app_id', 'api_name', name='unique_game_achievement'),
    )

class AchievementCredit(Base):
    """
    Tracks achievement credits with anti-exploit protection.

    Key fields for global claim tracking:
    - provider_name + provider_user_id: Permanent identifier (survives unlink/relink)
    - is_original_claim: True if this user was FIRST to claim this achievement

    Only original claims count toward Mantle tier and can be forged.
    Re-claimed achievements display on provider card only.
    """
    __tablename__ = 'achievement_credits'
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'))
    provider_account_id = Column(Integer, ForeignKey('provider_accounts.id'), nullable=True)
    achievement_id = Column(Integer, ForeignKey('achievements.id'))
    date_credited = Column(DateTime, default=datetime.utcnow)  # When added to Mantle
    unlocked_at = Column(DateTime, nullable=True)  # Original unlock time from provider

    # Anti-exploit: Global claim tracking (permanent, survives unlink/relink)
    provider_name = Column(String, nullable=False, index=True)       # "steam", "battlenet"
    provider_user_id = Column(String, nullable=False, index=True)    # Permanent provider ID
    is_original_claim = Column(Boolean, nullable=False, default=True)  # False = display only

    # Blizzard (WoW) support:
    character_name = Column(String, nullable=True, index=True)  # e.g., "thrall"
    realm_slug = Column(String, nullable=True, index=True)      # e.g., "illidan"

    # Relationships
    user = relationship("User", back_populates="achievement_credits")
    provider_account = relationship("ProviderAccount", back_populates="achievement_credits")
    achievement = relationship("Achievement", back_populates="achievement_credits")

    __table_args__ = (
        # Global uniqueness: One claim per provider identity + achievement
        UniqueConstraint(
            'provider_name', 'provider_user_id', 'achievement_id', 'character_name', 'realm_slug',
            name='unique_global_achievement_claim'
        ),
    )


class Game(Base):
    __tablename__ = 'games'
    id = Column(Integer, primary_key=True)
    provider_account_id = Column(Integer, ForeignKey('provider_accounts.id'), index=True)
    app_id = Column(String, index=True)
    name = Column(String)
    box_art_url = Column(String)

    provider_account = relationship("ProviderAccount")
    # You can add a relationship to achievements if you want.

    __table_args__ = (
        UniqueConstraint('provider_account_id', 'app_id', name='unique_provider_game'),
    )

class UserAchievement(Base):
    __tablename__ = 'user_achievements'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'))
    provider_account_id = Column(Integer, ForeignKey('provider_accounts.id'))
    game_id = Column(Integer, ForeignKey('games.id'))
    achievement_id = Column(Integer, ForeignKey('achievements.id'))
    is_unlocked = Column(Boolean, default=False)
    unlock_time = Column(DateTime, nullable=True)

    user = relationship("User")
    provider_account = relationship("ProviderAccount")
    game = relationship("Game")
    achievement = relationship("Achievement")

    __table_args__ = (
        UniqueConstraint('user_id', 'provider_account_id', 'game_id', 'achievement_id', name='uq_user_achievement_status'),
    )


class Session(Base):
    """Secure session tokens for user authentication"""
    __tablename__ = 'sessions'
    id = Column(Integer, primary_key=True, index=True)
    token = Column(String(64), unique=True, index=True, nullable=False)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)

    user = relationship("User")


class WalletAccount(Base):
    """
    Linked crypto wallet for NFT minting.
    Users can optionally connect a wallet to forge achievements into tokens.
    """
    __tablename__ = 'wallet_accounts'
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    wallet_address = Column(String(42), unique=True, index=True, nullable=False)  # 0x + 40 hex chars
    chain_id = Column(Integer, default=8453)  # Default to Base mainnet
    linked_at = Column(DateTime, default=datetime.utcnow)

    # SIWE nonce for authentication (rotated on each sign-in)
    current_nonce = Column(String(32), nullable=True)
    nonce_expires_at = Column(DateTime, nullable=True)

    user = relationship("User", back_populates="wallet_accounts")

    __table_args__ = (
        UniqueConstraint('user_id', 'chain_id', name='unique_wallet_per_chain'),
    )


class ForgedAchievement(Base):
    """
    Tracks achievements that have been minted as NFTs.
    Links achievement credit -> on-chain token -> in-game item.

    Item stats are computed at forge time and stored immutably.
    Godot fetches these pre-computed items directly.
    """
    __tablename__ = 'forged_achievements'
    id = Column(Integer, primary_key=True, index=True)
    achievement_credit_id = Column(Integer, ForeignKey('achievement_credits.id'), unique=True, nullable=False)
    wallet_account_id = Column(Integer, ForeignKey('wallet_accounts.id'), nullable=False)

    # On-chain data
    token_id = Column(Integer, nullable=False)  # NFT token ID on contract
    contract_address = Column(String(42), nullable=False)
    chain_id = Column(Integer, nullable=False)
    tx_hash = Column(String(66), nullable=False)  # 0x + 64 hex chars

    forged_at = Column(DateTime, default=datetime.utcnow)

    # Item identity (deterministic from achievement)
    item_type = Column(String(32), nullable=True)       # "weapon", "armor", "shield", "accessory"
    weapon_type = Column(String(32), nullable=True)     # "sword", "katana", "greatsword" (null for non-weapons)
    item_id = Column(String(64), nullable=True)         # Maps to ForgeItemDB key: "coiled_sword"
    item_name = Column(String(128), nullable=True)      # Display: "Veteran's Coiled Sword"
    item_rarity = Column(String(16), nullable=True)     # From achievement.rarity_tier

    # Computed visual intensity (from effort_score)
    effect_intensity = Column(Float, nullable=True)     # 0.0-1.0, controls particle/glow strength
    effect_name = Column(String(32), nullable=True)     # "ember_trail", "void_particles"
    glow_color = Column(String(7), nullable=True)       # "#ff6a00" (from game theme)

    # Bonus metadata (for display, not gameplay)
    effort_tier = Column(String(16), nullable=True)     # "Exceptional", "Superior", etc.
    vintage_years = Column(Integer, nullable=True)      # Years since unlock (for "Ancient" prefix)
    is_secret = Column(Boolean, nullable=True)          # From achievement.hidden

    # Relationships
    achievement_credit = relationship("AchievementCredit")
    wallet_account = relationship("WalletAccount")


class Friendship(Base):
    """
    Friend relationships between users.

    Status flow:
    - pending: Request sent, awaiting response
    - accepted: Both users are friends
    - declined: Request was declined (can be deleted or kept for history)
    - blocked: User blocked the other (prevents future requests)
    """
    __tablename__ = 'friendships'

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)  # Who sent request
    friend_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)  # Who receives request
    status = Column(String(20), nullable=False, default='pending')  # pending, accepted, declined, blocked
    created_at = Column(DateTime, default=datetime.utcnow)
    accepted_at = Column(DateTime, nullable=True)

    # Relationships
    user = relationship("User", foreign_keys=[user_id], backref="sent_friend_requests")
    friend = relationship("User", foreign_keys=[friend_id], backref="received_friend_requests")

    __table_args__ = (
        # Prevent duplicate requests in same direction
        UniqueConstraint('user_id', 'friend_id', name='unique_friendship_request'),
    )


class ChatMessage(Base):
    """
    Chat messages for tiered chat rooms.

    Rooms are based on Mantle tier:
    - newcomers: Initiate, Bronze
    - rising: Silver, Gold
    - veterans: Platinum, Diamond
    - legends: Legendary, Mythic
    - global: Activity feed (system messages for unlocks, forges)
    """
    __tablename__ = 'chat_messages'

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)  # Null for system messages
    room = Column(String(32), nullable=False, index=True)  # newcomers, rising, veterans, legends, global
    content = Column(Text, nullable=False)
    message_type = Column(String(20), default='chat')  # chat, unlock, forge, system
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    # For unlock/forge messages - link to the achievement
    achievement_credit_id = Column(Integer, ForeignKey('achievement_credits.id'), nullable=True)

    # Relationships
    user = relationship("User")
    achievement_credit = relationship("AchievementCredit")