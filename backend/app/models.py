from sqlalchemy import create_engine, Column, Integer, String, ForeignKey, JSON, DateTime, UniqueConstraint, Boolean, Float, Text
from sqlalchemy.orm import relationship, sessionmaker, Mapped, mapped_column
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
from enum import Enum
from .database import Base


class BridgeStatus(str, Enum):
    """Bridge status for forged items moving between game and external wallets."""
    IN_GAME = "in_game"           # In platform wallet, usable in Dreadland
    BRIDGING_OUT = "bridging_out" # Cooldown period (48h), not tradeable
    BRIDGED = "bridged"           # In external wallet, not usable in-game
    BRIDGING_IN = "bridging_in"   # Being transferred back to platform 

class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, index=True)
    is_admin = Column(Boolean, default=False, nullable=False)  # Bypass cooldowns, testing features
    appearance_data = Column(JSON, nullable=True)  # Character appearance for Armory preview

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
    provider_username = Column(String, nullable=True)  # Display name from provider (e.g., Discord username)
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

    Trading: Items are tradeable with provenance tracking.
    """
    __tablename__ = 'forged_achievements'
    id = Column(Integer, primary_key=True, index=True)
    achievement_credit_id = Column(Integer, ForeignKey('achievement_credits.id'), unique=True, nullable=True)  # Nullable for test-granted items
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

    # === TRADING & PROVENANCE ===
    # Original forger is always the wallet_account_id owner at forge time
    current_owner_id = Column(Integer, ForeignKey('users.id'), nullable=True, index=True)  # Current owner (null = original forger)
    owned_since = Column(DateTime, nullable=True)       # When current owner acquired it
    trade_count = Column(Integer, default=0)            # Number of times traded
    last_trade_at = Column(DateTime, nullable=True)     # For 24h cooldown check

    # === IN-GAME CLAIM TRACKING ===
    # Prevents duping - once claimed in game, can't be claimed again
    claimed_in_game_at = Column(DateTime, nullable=True)  # When added to in-game inventory

    # === BRIDGE SYSTEM ===
    # Tracks movement between in-game (platform wallet) and external wallets (OpenSea)
    bridge_status = Column(String(20), default='in_game', index=True)  # in_game, bridging_out, bridged, bridging_in
    bridge_requested_at = Column(DateTime, nullable=True)  # When bridge-out was requested (48h cooldown starts)
    bridge_completed_at = Column(DateTime, nullable=True)  # When bridge actually completed
    external_owner_wallet = Column(String(42), nullable=True, index=True)  # External wallet if bridged out

    # Relationships
    achievement_credit = relationship("AchievementCredit")
    wallet_account = relationship("WalletAccount")
    current_owner = relationship("User", foreign_keys=[current_owner_id])
    trades = relationship("ItemTrade", back_populates="forged_item")


class ItemTrade(Base):
    """
    Append-only log of all forged item trades.
    Used for provenance display and trade history.
    """
    __tablename__ = 'item_trades'

    id = Column(Integer, primary_key=True, index=True)
    forged_item_id = Column(Integer, ForeignKey('forged_achievements.id'), nullable=False, index=True)

    from_user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    to_user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    traded_at = Column(DateTime, default=datetime.utcnow, index=True)

    # Trade details
    price_gold = Column(Integer, nullable=True)         # Gold amount (if any)
    tax_applied = Column(Integer, default=0)            # 5% tax amount
    trade_type = Column(String(20), default='direct')   # direct, gift

    # On-chain recording (batched)
    chain_tx_hash = Column(String(66), nullable=True)   # Filled when batch submitted
    chain_recorded_at = Column(DateTime, nullable=True)

    # Relationships
    forged_item = relationship("ForgedAchievement", back_populates="trades")
    from_user = relationship("User", foreign_keys=[from_user_id])
    to_user = relationship("User", foreign_keys=[to_user_id])


class TradeListing(Base):
    """
    Active trade listings from chat auctions.
    Ephemeral - listings expire after 30 minutes.
    """
    __tablename__ = 'trade_listings'

    id = Column(Integer, primary_key=True, index=True)
    forged_item_id = Column(Integer, ForeignKey('forged_achievements.id'), nullable=False, index=True)
    seller_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)

    listing_type = Column(String(10), default='sell')   # sell, buy (WTS vs WTB)
    price_gold = Column(Integer, nullable=False)
    message = Column(String(256), nullable=True)        # Custom message from seller

    # Location for "find seller" feature
    zone_id = Column(String(32), nullable=True)         # wasteland, cursed_lands, etc.
    position_x = Column(Float, nullable=True)
    position_y = Column(Float, nullable=True)

    posted_at = Column(DateTime, default=datetime.utcnow, index=True)
    expires_at = Column(DateTime, nullable=False)       # 30 min from posted_at

    # Relationships
    forged_item = relationship("ForgedAchievement")
    seller = relationship("User")

    __table_args__ = (
        # One active listing per item per seller
        UniqueConstraint('forged_item_id', 'seller_id', name='unique_item_listing'),
    )


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


class WeaponStats(Base):
    """
    Combat biography for forged weapons.
    Tracks kills, crits, damage, and all combat history.
    Virgin weapons (0/0/0/0) are pristine collectors' items.
    Stats can never be reset - that's the point.
    """
    __tablename__ = 'weapon_stats'

    id = Column(Integer, primary_key=True, index=True)
    forged_achievement_id = Column(Integer, ForeignKey('forged_achievements.id'), unique=True, nullable=False, index=True)

    # === CORE KILL STATS ===
    kills_total = Column(Integer, default=0)
    kills_by_type = Column(JSON, default=dict)  # {"skeleton": 42, "wolf": 15}
    kills_elite = Column(Integer, default=0)
    kills_boss = Column(Integer, default=0)
    kills_pvp = Column(Integer, default=0)  # Future PvP kills

    # === DAMAGE STATS ===
    damage_total = Column(Integer, default=0)
    damage_max_hit = Column(Integer, default=0)
    damage_overkill = Column(Integer, default=0)

    # === CRITICAL HIT STATS ===
    crits_landed = Column(Integer, default=0)
    hits_total = Column(Integer, default=0)
    weakpoints_destroyed = Column(Integer, default=0)
    chain_max_reached = Column(Integer, default=0)

    # === USAGE STATS ===
    swings_total = Column(Integer, default=0)
    shots_fired = Column(Integer, default=0)
    bursts_fired = Column(Integer, default=0)
    time_equipped_seconds = Column(Integer, default=0)
    sessions_equipped = Column(Integer, default=0)

    # === NEGATIVE STATS (Virgin Weapon Value) ===
    deaths_equipped = Column(Integer, default=0)
    misses_total = Column(Integer, default=0)
    battles_lost = Column(Integer, default=0)
    show_negative_stats = Column(Boolean, default=True)  # Toggleable visibility

    # === MILESTONE TIMESTAMPS ===
    first_equipped_at = Column(DateTime, nullable=True)
    first_kill_at = Column(DateTime, nullable=True)
    first_crit_at = Column(DateTime, nullable=True)
    milestone_100_kills_at = Column(DateTime, nullable=True)
    milestone_1000_kills_at = Column(DateTime, nullable=True)
    milestone_10000_kills_at = Column(DateTime, nullable=True)

    # === INFINITE LEVEL SYSTEM ===
    level = Column(Integer, default=0)
    experience = Column(Integer, default=0)

    # === PER-WEAPON ACHIEVEMENTS ===
    achievements = Column(JSON, default=list)  # ["FIRST_BLOOD", "CENTURION"]

    # === SYNC TRACKING ===
    last_synced_at = Column(DateTime, nullable=True)
    last_synced_from_ip = Column(String(45), nullable=True)

    # Relationships
    forged_achievement = relationship("ForgedAchievement", backref="weapon_stats_record")


class BridgeTransaction(Base):
    """
    Tracks all bridge operations for audit/debugging.

    Records bridge-out requests, confirmations, bridge-in operations,
    and external transfers detected by the indexer.
    """
    __tablename__ = 'bridge_transactions'

    id = Column(Integer, primary_key=True, index=True)
    forged_achievement_id = Column(Integer, ForeignKey('forged_achievements.id'), nullable=False, index=True)

    # Transaction type: 'bridge_out', 'bridge_in', 'external_transfer'
    transaction_type = Column(String(20), nullable=False)

    # User tracking (null for external-only transfers)
    from_user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    to_user_id = Column(Integer, ForeignKey('users.id'), nullable=True)

    # Wallet addresses
    from_wallet = Column(String(42), nullable=True)
    to_wallet = Column(String(42), nullable=True)

    # Blockchain data
    tx_hash = Column(String(66), nullable=True)  # 0x + 64 hex chars

    # Timing
    requested_at = Column(DateTime, default=datetime.utcnow, index=True)
    completed_at = Column(DateTime, nullable=True)

    # Status: 'pending', 'completed', 'failed', 'cancelled'
    status = Column(String(20), default='pending', index=True)

    # Error info if failed
    error_message = Column(Text, nullable=True)

    # Relationships
    forged_achievement = relationship("ForgedAchievement")
    from_user = relationship("User", foreign_keys=[from_user_id])
    to_user = relationship("User", foreign_keys=[to_user_id])