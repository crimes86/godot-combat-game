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


class DeviceCode(Base):
    """
    Device authentication codes for Godot client login flow.

    Replaces in-memory storage to survive server restarts.
    Codes expire after 10 minutes.
    """
    __tablename__ = 'device_codes'

    id = Column(Integer, primary_key=True, index=True)
    device_code = Column(String(64), unique=True, index=True, nullable=False)
    expires_at = Column(DateTime, nullable=False)

    # Set when user authenticates in browser
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    username = Column(String, nullable=True)
    session_token = Column(String, nullable=True)

    # Beta verification (if beta gate is enabled)
    beta_verified = Column(Boolean, default=False)

    # Timestamp
    created_at = Column(DateTime, default=datetime.utcnow)


class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, index=True)
    is_admin = Column(Boolean, default=False, nullable=False)  # Bypass cooldowns, testing features
    appearance_data = Column(JSON, nullable=True)  # Character appearance for Armory preview

    # Contributor cosmetics (earned via community contributions)
    active_title = Column(String(64), nullable=True)      # "Archivist", "Lorekeeper", "Curator"
    active_badges = Column(JSON, default=list)            # ["lorekeeper_badge", "curator_badge"]
    contributor_role = Column(String(32), nullable=True)  # "curator" = special permissions

    # Relationships
    provider_accounts = relationship("ProviderAccount", back_populates="user")
    achievement_credits = relationship("AchievementCredit", back_populates="user")
    wallet_accounts = relationship("WalletAccount", back_populates="user")
    contributor_profile = relationship("ContributorProfile", back_populates="user", uselist=False)

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
    refresh_token = Column(String, nullable=True)  # OAuth refresh token
    token_expires_at = Column(DateTime, nullable=True)  # When access_token expires
    last_sync_at = Column(DateTime, nullable=True)  # For sync cooldown (15 min)
    last_credited_count = Column(Integer, nullable=True, default=0)  # Number of new achievements from last sync

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

    Only original claims count toward Ashbane tier and can be forged.
    Re-claimed achievements display on provider card only.
    """
    __tablename__ = 'achievement_credits'
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'))
    provider_account_id = Column(Integer, ForeignKey('provider_accounts.id'), nullable=True)
    achievement_id = Column(Integer, ForeignKey('achievements.id'))
    date_credited = Column(DateTime, default=datetime.utcnow)  # When added to Ashbane
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
    """Secure session tokens for user authentication.

    Tokens are stored as SHA-256 hashes for security - a DB leak won't
    expose session tokens that could be used for account takeover.
    """
    __tablename__ = 'sessions'
    id = Column(Integer, primary_key=True, index=True)
    token_hash = Column(String(64), unique=True, index=True, nullable=False)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)

    user = relationship("User")

    @staticmethod
    def hash_token(token: str) -> str:
        """Hash a session token using SHA-256."""
        import hashlib
        return hashlib.sha256(token.encode()).hexdigest()


class UserActivity(Base):
    """
    Tracks user journey and interactions for analytics and debugging.

    Activity types:
    - auth: login, logout, session_refresh
    - provider: connect, disconnect, sync, sync_error
    - tapestry: view, map_open, map_submit, vote
    - contribution: submit, approve, reject
    - dispute: create, vote, resolve
    - forge: item_forge, item_trade
    - navigation: page_view
    """
    __tablename__ = 'user_activities'

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True, index=True)  # Nullable for pre-login events

    # Activity classification
    category = Column(String(32), nullable=False, index=True)  # auth, provider, tapestry, etc.
    action = Column(String(64), nullable=False, index=True)    # login, connect, view, etc.

    # Context data (JSON for flexibility)
    details = Column(JSON, nullable=True)  # provider_name, game_key, achievement_id, etc.

    # Request context (for debugging/security)
    ip_address = Column(String(45), nullable=True)  # IPv6 max length
    user_agent = Column(String(512), nullable=True)

    # Timing
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    # Optional: duration for timed activities (e.g., how long mapping took)
    duration_ms = Column(Integer, nullable=True)

    # Success/failure tracking
    success = Column(Boolean, default=True)
    error_message = Column(String(512), nullable=True)


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

    # === THE TAPESTRY (Cross-Platform Provenance) ===
    # All items are "Threaded from the Tapestry" - a magical weave connecting heroic deeds.
    # Provider colors create subtle visual accents (rim glow) without explicit naming.
    source_provider = Column(String(32), nullable=True)     # "steam", "xbox", "psn", etc.
    provider_accent_color = Column(String(7), nullable=True)  # "#107C10" (provider's brand color)

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

    # === SOFT DELETE (Destroyed Items) ===
    destroyed_at = Column(DateTime, nullable=True, index=True)  # When item was destroyed
    destroyed_reason = Column(String(50), nullable=True)  # player_delete, vendor_sale, dropped_decay
    destroyed_by_user_id = Column(Integer, ForeignKey('users.id'), nullable=True)  # Who destroyed it
    previous_owner_id = Column(Integer, ForeignKey('users.id'), nullable=True)  # Owner before destruction

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
    zone_id = Column(String(32), nullable=True)         # dreadland, cursed_lands, etc.
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

    Rooms are based on Ashbane tier:
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

    # === ANTI-CHEAT FLAGS ===
    suspicious_flags = Column(Integer, default=0)  # Bitmask of detected anomalies
    suspicious_score = Column(Float, default=0.0)  # Cumulative suspicion score (0-100)
    is_flagged = Column(Boolean, default=False)  # True if needs manual review
    flagged_at = Column(DateTime, nullable=True)
    review_notes = Column(Text, nullable=True)  # Admin notes on review

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


class SuspiciousActivity(Base):
    """
    Telemetry log for suspicious weapon stat activity.
    Used to detect cheaters and build ban evidence.

    Anomaly types (suspicious_type):
    - rate_exceeded: Too many updates in time window
    - impossible_ratio: Stats violate game logic (crits > hits)
    - spike_detected: Single update with impossible gains
    - ip_mismatch: Update from different IP mid-session
    - time_travel: Client timestamp in future or far past
    - stat_regression: Attempt to decrease a stat (blocked but logged)
    """
    __tablename__ = 'suspicious_activities'

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)
    weapon_stats_id = Column(Integer, ForeignKey('weapon_stats.id'), nullable=True, index=True)
    forged_achievement_id = Column(Integer, ForeignKey('forged_achievements.id'), nullable=True, index=True)

    # What triggered the flag
    suspicious_type = Column(String(32), nullable=False, index=True)
    severity = Column(String(16), nullable=False, default='low')  # low, medium, high, critical

    # Evidence snapshot
    details = Column(JSON, nullable=True)  # Full context of the suspicious activity
    old_value = Column(JSON, nullable=True)  # Stats before update
    new_value = Column(JSON, nullable=True)  # Stats client tried to set
    delta = Column(JSON, nullable=True)  # Computed difference

    # Request metadata
    client_ip = Column(String(45), nullable=True)
    user_agent = Column(String(256), nullable=True)
    client_timestamp = Column(DateTime, nullable=True)  # What client claimed
    server_timestamp = Column(DateTime, default=datetime.utcnow, index=True)

    # Session tracking
    session_id = Column(String(64), nullable=True)  # Track across updates

    # Action taken
    action_taken = Column(String(32), default='logged')  # logged, blocked, banned

    # Relationships
    user = relationship("User")
    weapon_stats = relationship("WeaponStats")
    forged_achievement = relationship("ForgedAchievement")


class SuspiciousIP(Base):
    """
    Tracks IPs exhibiting scanner/bot behavior.

    Detection triggers:
    - Multiple 404s in short window (vulnerability scanning)
    - Known attack paths (/wp-admin, /phpmyadmin, etc.)
    - Rapid requests without session
    """
    __tablename__ = 'suspicious_ips'

    id = Column(Integer, primary_key=True, index=True)
    ip_address = Column(String(45), nullable=False, index=True)  # IPv4 or IPv6

    # Detection info
    detection_type = Column(String(32), nullable=False)  # scanner, brute_force, bot
    threat_level = Column(String(16), default='low')  # low, medium, high

    # Activity summary
    hit_count = Column(Integer, default=1)  # Total suspicious requests
    paths_hit = Column(JSON, nullable=True)  # List of paths requested
    user_agents = Column(JSON, nullable=True)  # User agents seen

    # Timing
    first_seen = Column(DateTime, default=datetime.utcnow, index=True)
    last_seen = Column(DateTime, default=datetime.utcnow)

    # Action
    is_blocked = Column(Boolean, default=False)  # For future IP blocking
    notes = Column(Text, nullable=True)  # Manual notes


class SeedPlot(Base):
    """
    Player-claimable territories that trigger chunk expansion.

    Each edge chunk has one seed plot. When both edge plots are claimed,
    the world expands by adding new chunks on both sides.

    States:
    - unclaimed: Available for claiming
    - claimed: Owned by a player, receiving contributions
    - abandoned: No contributions for 7 days
    - decaying: In 3-day warning period before chunk removal
    """
    __tablename__ = 'seed_plots'

    id = Column(Integer, primary_key=True, index=True)
    shard_id = Column(String(32), nullable=False, index=True)
    chunk_id = Column(Integer, nullable=False, index=True)
    position_x = Column(Float, nullable=False)
    position_y = Column(Float, nullable=False)

    # Ownership
    owner_id = Column(Integer, ForeignKey('users.id'), nullable=True, index=True)
    claimed_at = Column(DateTime, nullable=True)
    last_contribution_at = Column(DateTime, nullable=True)

    # State tracking
    state = Column(String(16), nullable=False, default='unclaimed', index=True)
    claim_cost = Column(Integer, nullable=False, default=1000)

    # Statistics
    total_gold_contributed = Column(Integer, default=0)
    total_wood_contributed = Column(Integer, default=0)
    total_stone_contributed = Column(Integer, default=0)
    total_kills = Column(Integer, default=0)
    total_time_minutes = Column(Integer, default=0)
    contribution_score = Column(Integer, default=0)

    # Decay tracking
    abandoned_at = Column(DateTime, nullable=True)
    decay_warning_sent = Column(Boolean, default=False)

    # World Tree v2.1 features
    # Fix #1: Dual ownership
    original_owner_id = Column(Integer, ForeignKey('users.id'), nullable=True, index=True)
    last_ownership_transfer = Column(DateTime, nullable=True)
    current_guild_id = Column(String(64), nullable=True, index=True)
    last_guild_change = Column(DateTime, nullable=True)

    # Fix #2: Champion migration
    is_origin_champion = Column(Boolean, default=False, index=True)
    champion_since = Column(DateTime, nullable=True)
    is_decaying = Column(Boolean, default=False)
    decay_complete_at = Column(DateTime, nullable=True)
    migration_expires = Column(DateTime, nullable=True)
    original_chunk_id = Column(Integer, nullable=True)

    # Tree ranks
    tree_rank = Column(Integer, default=0, index=True)
    tree_health = Column(Integer, default=0)
    tree_max_health = Column(Integer, default=0)

    # Guild/faction
    guild_name = Column(String(128), nullable=True)
    faction = Column(String(32), default='individual', index=True)

    # Upgrade system
    upgrade_started_at = Column(DateTime, nullable=True)
    upgrade_target_rank = Column(Integer, nullable=True)

    # Watering
    last_watered = Column(DateTime, nullable=True)
    times_watered = Column(Integer, default=0)
    growth_bonus_accumulated = Column(Float, default=0.0)

    # Respawn binding
    allow_public_binding = Column(Boolean, default=False)

    # Warehouse (Fix #6)
    warehouse_safe_gold = Column(Integer, default=0)
    warehouse_safe_wood = Column(Integer, default=0)
    warehouse_safe_stone = Column(Integer, default=0)
    warehouse_safe_gems = Column(Integer, default=0)
    warehouse_overflow_gold = Column(Integer, default=0)
    warehouse_overflow_wood = Column(Integer, default=0)
    warehouse_overflow_stone = Column(Integer, default=0)
    warehouse_overflow_gems = Column(Integer, default=0)

    # Resource mines
    claimed_mine_ids = Column(Text, nullable=True)  # JSON array of mine IDs

    # Bane defense (Fix #10)
    defense_window_hour = Column(Integer, default=20)
    defense_window_timezone_offset = Column(Integer, default=0)

    # Relationships
    owner = relationship("User", foreign_keys=[owner_id])
    original_owner = relationship("User", foreign_keys=[original_owner_id])
    world_tree_rankings = relationship("WorldTreeRanking", back_populates="seed_plot")
    world_tree_contributions = relationship("WorldTreeContribution", back_populates="seed_plot")
    buildings = relationship("SeedPlotBuilding", back_populates="seed_plot", cascade="all, delete-orphan")
    resource_mines = relationship("ResourceMine", back_populates="owner_tree")
    bane_stones = relationship("BaneStone", back_populates="target_tree")

    __table_args__ = (
        # One seed plot per chunk per shard
        UniqueConstraint('shard_id', 'chunk_id', name='unique_seed_plot_per_chunk'),
    )


class ActiveChunk(Base):
    """
    Tracks which chunks are currently loaded on each shard.

    Chunk types:
    - origin: Permanent chunks (-1, 0, 1) connected to campfire
    - dynamic: Player-expanded chunks, can be removed if seed plots decay
    """
    __tablename__ = 'active_chunks'

    id = Column(Integer, primary_key=True, index=True)
    shard_id = Column(String(32), nullable=False, index=True)
    chunk_id = Column(Integer, nullable=False, index=True)
    chunk_type = Column(String(16), nullable=False)  # origin, dynamic
    created_at = Column(DateTime, default=datetime.utcnow)
    player_count = Column(Integer, default=0)
    is_loaded = Column(Boolean, default=True)

    __table_args__ = (
        # One chunk per shard
        UniqueConstraint('shard_id', 'chunk_id', name='unique_chunk_per_shard'),
    )


class WorldTreeRanking(Base):
    """
    Weekly rankings for World Tree competition.

    Top seed plot each week gets promoted to Chunk -1 (West Origin)
    becoming the prestigious "World Tree" with special benefits.

    Rankings calculated every Sunday midnight UTC.
    """
    __tablename__ = 'world_tree_rankings'

    id = Column(Integer, primary_key=True, index=True)
    shard_id = Column(String(32), nullable=False, index=True)
    week_number = Column(Integer, nullable=False, index=True)
    week_start = Column(DateTime, nullable=False)
    week_end = Column(DateTime, nullable=False)

    # Winner info
    seed_plot_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=False, index=True)
    owner_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)
    total_score = Column(Integer, nullable=False)
    rank = Column(Integer, nullable=False)

    # Status
    is_active = Column(Boolean, default=True, index=True)
    promoted_to_origin = Column(Boolean, default=False)
    promoted_at = Column(DateTime, nullable=True)

    # Blockchain integration
    blockchain_record_id = Column(Integer, nullable=True)
    blockchain_tx_hash = Column(String(66), nullable=True)
    recorded_on_chain_at = Column(DateTime, nullable=True)

    # Ban tracking
    owner_banned_until = Column(DateTime, nullable=True)

    # Relationships
    seed_plot = relationship("SeedPlot", back_populates="world_tree_rankings")
    owner = relationship("User")

    __table_args__ = (
        # One ranking per shard per week
        UniqueConstraint('shard_id', 'week_number', name='unique_ranking_per_week'),
    )


class WorldTreeContribution(Base):
    """
    Player contributions to seed plots for World Tree competition.

    Tracks all resources contributed, kills performed, and time spent
    at each seed plot during a week. Used for ranking and rewards.

    Top 10 contributors get "World Tree Champion" title and bonuses.
    """
    __tablename__ = 'world_tree_contributions'

    id = Column(Integer, primary_key=True, index=True)
    seed_plot_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)
    week_number = Column(Integer, nullable=False, index=True)

    # Contribution breakdown
    gold_contributed = Column(Integer, default=0)
    wood_contributed = Column(Integer, default=0)
    stone_contributed = Column(Integer, default=0)
    gems_contributed = Column(Integer, default=0)
    kills = Column(Integer, default=0)
    boss_kills = Column(Integer, default=0)  # World Tree v2.1 - Fix #11
    time_minutes = Column(Integer, default=0)

    # Score
    contribution_score = Column(Integer, default=0, index=True)
    rank = Column(Integer, nullable=True)

    # Rewards
    rewards_claimed = Column(Boolean, default=False)
    rewards_claimed_at = Column(DateTime, nullable=True)

    # Timestamps
    first_contribution_at = Column(DateTime, default=datetime.utcnow)
    last_contribution_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    seed_plot = relationship("SeedPlot", back_populates="world_tree_contributions")
    user = relationship("User")


class ResourceMine(Base):
    """
    Resource mines that can be claimed by seed plot owners.

    Implements active collection system (Fix #7):
    - 30-minute cooldown between collections
    - Quick collect with diminishing returns (100% -> 80% -> 64%)
    - Resources accumulate over time
    """
    __tablename__ = 'resource_mines'

    id = Column(Integer, primary_key=True, index=True)
    shard_id = Column(String(32), nullable=False, index=True)
    chunk_id = Column(Integer, nullable=False, index=True)
    mine_type = Column(String(16), nullable=False, index=True)  # "gold", "stone", "wood", "gems"
    position_x = Column(Float, nullable=False)
    position_y = Column(Float, nullable=False)

    # Ownership
    owner_tree_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=True, index=True)

    # Active collection tracking (Fix #7)
    last_collected = Column(DateTime, nullable=True)
    last_collector = Column(String(64), nullable=True)
    quick_collect_count = Column(Integer, default=0)

    # Accumulated resources
    resources_accumulated = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    owner_tree = relationship("SeedPlot", back_populates="resource_mines")


class SeedPlotBuilding(Base):
    """
    Buildings placed on seed plots (unlocked at tree rank 1+).

    Building types:
    - Campfire: Free respawn point
    - Warehouse: Protected resource storage (Fix #6)
    - Vendor: Sells potions/gear
    - Shrine: Provides buffs
    - Smithy: Repairs equipment
    - Fortress: Defensive structure

    Migration behavior (Fix #2):
    - Buildings migrate with tree to origin chunk
    - Start inactive, require 50% reactivation cost
    """
    __tablename__ = 'seed_plot_buildings'

    id = Column(Integer, primary_key=True, index=True)
    seed_plot_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=False, index=True)
    building_type = Column(String(32), nullable=False, index=True)
    position_slot = Column(String(1), nullable=False)  # A-F

    # Health
    health = Column(Integer, default=1000)
    max_health = Column(Integer, default=1000)

    # Protection
    is_protected = Column(Boolean, default=False)

    # Migration (Fix #2)
    is_active = Column(Boolean, default=True, index=True)
    activation_cost = Column(Integer, default=0)
    original_cost = Column(Integer, nullable=False)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    destroyed_at = Column(DateTime, nullable=True)
    activated_at = Column(DateTime, nullable=True)

    # Vendor data
    vendor_inventory = Column(Text, nullable=True)  # JSON
    vendor_prices = Column(Text, nullable=True)  # JSON
    total_sales = Column(Integer, default=0)

    # Shrine data
    shrine_buff_type = Column(String(32), nullable=True)

    # Relationships
    seed_plot = relationship("SeedPlot", back_populates="buildings")


class BaneStone(Base):
    """
    Siege warfare system - any tree can be attacked (Fix #5, #10).

    Mechanics:
    - Plant cost: 50k gold
    - 50k HP, must be destroyed during 1-hour defense window
    - Defense window scheduled by defender (default 8pm their timezone)
    - Success: Attacker claims tree, defender gets 7-day migration period
    - Failure: Bane stone destroyed, defender keeps tree

    Universal Bane (Fix #5): Not limited to champion, any tree can be sieged
    """
    __tablename__ = 'bane_stones'

    id = Column(Integer, primary_key=True, index=True)
    shard_id = Column(String(32), nullable=False, index=True)
    target_tree_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=False, index=True)
    attacker_guild_id = Column(String(64), nullable=False, index=True)

    # Health
    health = Column(Integer, default=50000)
    max_health = Column(Integer, default=50000)

    # Timeline (Fix #10 - Scheduled windows)
    planted_at = Column(DateTime, default=datetime.utcnow)
    window_start = Column(DateTime, nullable=True)
    window_end = Column(DateTime, nullable=True)

    # Status
    is_active = Column(Boolean, default=False, index=True)
    outcome = Column(String(16), nullable=True)  # "attacker_won", "defender_won", "expired"

    # Relationships
    target_tree = relationship("SeedPlot", back_populates="bane_stones")


class AchievementDispute(Base):
    """
    Player-submitted disputes about achievement rarity classifications.

    Disputes are broadcast to the appropriate tier chat room for peer review:
    - Common/Uncommon → newcomers room
    - Rare → rising room
    - Epic → veterans room
    - Legendary → legends room

    Status flow:
    - pending: Awaiting community votes
    - approved: Enough votes to change, achievement updated
    - rejected: Community disagreed or admin rejected
    - expired: No action taken within voting window
    """
    __tablename__ = 'achievement_disputes'

    id = Column(Integer, primary_key=True, index=True)
    achievement_id = Column(Integer, ForeignKey('achievements.id'), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)
    chat_message_id = Column(Integer, ForeignKey('chat_messages.id'), nullable=True, index=True)

    # Current classification (snapshot at dispute time)
    current_effort_score = Column(Float, nullable=False)
    current_rarity = Column(String(16), nullable=False)
    scoring_method = Column(String(32), nullable=True)  # "global_percent", "gamerscore", "points", etc.
    scoring_input = Column(String(64), nullable=True)   # "16.2%", "100 gamerscore", etc.

    # Suggested classification
    suggested_rarity = Column(String(16), nullable=False)  # Common, Uncommon, Rare, Epic, Legendary
    reason = Column(Text, nullable=False)  # Player's explanation

    # Voting
    votes_up = Column(Integer, default=0)      # Agree with suggested change
    votes_down = Column(Integer, default=0)    # Disagree, keep current
    votes_threshold = Column(Integer, default=5)  # Votes needed to auto-approve

    # Status
    status = Column(String(16), nullable=False, default='pending', index=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    expires_at = Column(DateTime, nullable=True)  # 7 days from creation
    resolved_at = Column(DateTime, nullable=True)

    # Admin override (optional)
    admin_notes = Column(Text, nullable=True)
    resolved_by_id = Column(Integer, ForeignKey('users.id'), nullable=True)

    # Relationships
    achievement = relationship("Achievement")
    user = relationship("User", foreign_keys=[user_id])
    chat_message = relationship("ChatMessage")
    resolved_by = relationship("User", foreign_keys=[resolved_by_id])
    votes = relationship("DisputeVote", back_populates="dispute")


class DisputeVote(Base):
    """
    Individual votes on achievement disputes.

    Only players who have unlocked the achievement can vote,
    ensuring expertise-based peer review.
    """
    __tablename__ = 'dispute_votes'

    id = Column(Integer, primary_key=True, index=True)
    dispute_id = Column(Integer, ForeignKey('achievement_disputes.id'), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)

    vote = Column(Integer, nullable=False)  # 1 = agree (change rarity), -1 = disagree (keep current)
    voted_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    dispute = relationship("AchievementDispute", back_populates="votes")
    user = relationship("User")

    __table_args__ = (
        # One vote per user per dispute
        UniqueConstraint('dispute_id', 'user_id', name='unique_dispute_vote'),
    )


class GameLog(Base):
    """
    Client-side game logs sent from Godot clients.

    Used for debugging, analytics, and monitoring.
    Logs are batched and sent periodically (every 5 seconds).
    Only INFO+ logs are sent (DEBUG stays client-side only).
    """
    __tablename__ = 'game_logs'

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True, index=True)
    session_id = Column(String(36), nullable=True, index=True)  # UUID per game session
    device_id = Column(String(36), nullable=True, index=True)   # Persistent per device

    level = Column(Integer, nullable=False)  # 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
    category = Column(String(32), nullable=True, index=True)
    message = Column(Text, nullable=False)

    client_timestamp = Column(DateTime, nullable=True)  # When client generated log
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    client_version = Column(String(16), nullable=True)
    platform = Column(String(16), nullable=True)  # Windows, Linux, Android, Web
    is_host = Column(Boolean, default=False)  # Was this client hosting?
    ip_address = Column(String(45), nullable=True)  # For abuse tracking

    # Relationships
    user = relationship("User", backref="game_logs")


class SeasonalRanking(Base):
    """
    All-time leaderboard tracking cumulative tree performance (Fix #9).

    Tracks:
    - Total contributions across all weeks
    - Total kills and boss kills
    - Weeks participated vs weeks won
    - Highest rank achieved (0-7)

    Purpose: Provides historical context and long-term progression tracking
    """
    __tablename__ = 'seasonal_rankings'

    id = Column(Integer, primary_key=True, index=True)
    shard_id = Column(String(32), nullable=False, index=True)
    tree_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=False, index=True)
    guild_id = Column(String(64), nullable=False, index=True)

    # All-time stats
    total_contribution = Column(Integer, default=0, index=True)
    total_kills = Column(Integer, default=0)
    total_boss_kills = Column(Integer, default=0)
    total_waterings = Column(Integer, default=0)
    weeks_participated = Column(Integer, default=0)
    weeks_won = Column(Integer, default=0)

    # Milestones
    highest_rank_achieved = Column(Integer, default=0)
    first_contribution = Column(DateTime, nullable=True)
    last_contribution = Column(DateTime, nullable=True)

    # Relationships
    tree = relationship("SeedPlot")


# =============================================================================
# COMMUNITY CONTRIBUTION SYSTEM
# =============================================================================
# Enables players to submit cross-platform achievement mappings and rarity
# disputes, earning Ashbane-native titles, badges, and cosmetics.

class CommunityContribution(Base):
    """
    Unified table for all community contributions.

    Contribution types:
    - platform_mapping: Cross-platform achievement ID mappings
    - rarity_dispute: Achievement rarity score disputes

    Status flow:
    - pending: Awaiting community votes
    - approved: Reached vote threshold, changes applied
    - rejected: Community disagreed or admin rejected
    - expired: No action taken within 7 days
    """
    __tablename__ = 'community_contributions'

    id = Column(Integer, primary_key=True, index=True)
    contribution_type = Column(String(32), nullable=False, index=True)  # "platform_mapping", "rarity_dispute"
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)
    chat_message_id = Column(Integer, ForeignKey('chat_messages.id'), nullable=True)

    # Type-specific data stored as JSON
    # For platform_mapping: {game_key, steam_api_name, target_platform, target_api_name, game_name, achievement_name}
    # For rarity_dispute: {achievement_id, current_rarity, suggested_rarity, current_effort_score, scoring_method}
    data = Column(JSON, nullable=False)
    reason = Column(Text, nullable=False)  # Player's explanation

    # Voting
    votes_up = Column(Integer, default=0)       # Agree with contribution
    votes_down = Column(Integer, default=0)     # Disagree
    votes_threshold = Column(Integer, default=5)  # Votes needed to auto-approve

    # Status
    status = Column(String(16), nullable=False, default='pending', index=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    expires_at = Column(DateTime, nullable=True)  # 7 days from creation
    resolved_at = Column(DateTime, nullable=True)

    # Admin/moderation
    admin_notes = Column(Text, nullable=True)
    resolved_by_id = Column(Integer, ForeignKey('users.id'), nullable=True)

    # Credit display (shown on forged items, mapping entries)
    credit_display = Column(String(64), nullable=True)  # "Contributed by username"

    # Relationships
    user = relationship("User", foreign_keys=[user_id])
    chat_message = relationship("ChatMessage")
    resolved_by = relationship("User", foreign_keys=[resolved_by_id])
    votes = relationship("ContributionVote", back_populates="contribution", cascade="all, delete-orphan")


class ContributionVote(Base):
    """
    Individual votes on community contributions.

    Expert-gating rules:
    - Platform mappings: Must have achievements from at least one platform
    - Rarity disputes: Must have the achievement being disputed
    - Curator role: Can vote on anything with 3x weight
    """
    __tablename__ = 'contribution_votes'

    id = Column(Integer, primary_key=True, index=True)
    contribution_id = Column(Integer, ForeignKey('community_contributions.id'), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)

    vote = Column(Integer, nullable=False)  # 1 = agree, -1 = disagree
    weight = Column(Integer, default=1)     # 3 for curators
    voted_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    contribution = relationship("CommunityContribution", back_populates="votes")
    user = relationship("User")

    __table_args__ = (
        # One vote per user per contribution
        UniqueConstraint('contribution_id', 'user_id', name='unique_contribution_vote'),
    )


class ContributorProfile(Base):
    """
    Tracks contributor statistics and unlocked rewards.

    Reward tiers (approved contributions):
    - 5: Archivist (title)
    - 25: Lorekeeper (title + badge)
    - 100: Curator (title + badge + cape + aura + curator role)

    Curator perks:
    - 3x vote weight
    - Auto-approve own submissions
    - Access to moderation panel
    """
    __tablename__ = 'contributor_profiles'

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), unique=True, nullable=False, index=True)

    # Approved contribution counts
    total_approved = Column(Integer, default=0, index=True)
    mappings_approved = Column(Integer, default=0)
    disputes_approved = Column(Integer, default=0)

    # Voting stats
    total_votes_cast = Column(Integer, default=0)
    helpful_votes = Column(Integer, default=0)  # Votes on contributions that were approved

    # Rewards tracking
    rewards_claimed = Column(JSON, default=list)    # ["archivist_title", "lorekeeper_badge"]
    rewards_available = Column(JSON, default=list)  # Rewards ready to claim

    # Role (synced to User.contributor_role)
    contributor_role = Column(String(32), default='contributor')  # "contributor", "curator"

    # Leaderboard
    leaderboard_rank = Column(Integer, nullable=True, index=True)

    # Timestamps
    first_contribution_at = Column(DateTime, nullable=True)
    last_contribution_at = Column(DateTime, nullable=True)

    # Relationships
    user = relationship("User", back_populates="contributor_profile")


class UserFeedback(Base):
    """
    User feedback submissions.
    Simple free-form text feedback from the glowing navbar button.
    """
    __tablename__ = 'user_feedback'

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True, index=True)  # Nullable for anonymous

    # Feedback content
    message = Column(Text, nullable=False)
    page_url = Column(String(500), nullable=True)  # Where they were when they submitted
    user_agent = Column(String(500), nullable=True)  # Browser info

    # Status tracking
    status = Column(String(20), default='new', index=True)  # new, reviewed, actioned, archived
    admin_notes = Column(Text, nullable=True)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    reviewed_at = Column(DateTime, nullable=True)

    # Relationships
    user = relationship("User", backref="feedback_submissions")


class PendingGameDiscovery(Base):
    """
    Tracks games discovered during achievement syncs that aren't in platform_mappings.json.

    When a user syncs achievements from a game we haven't seen before, it gets
    logged here for admin review. Admin can then research cross-platform availability
    and add it to the Tapestry if applicable.

    Status flow:
    - pending: Newly discovered, awaiting admin review
    - researching: Admin is looking into cross-platform availability
    - added: Game was added to platform_mappings.json
    - rejected: Game not suitable for Tapestry (single-platform exclusive, etc.)
    - no_items: Game has no forge-eligible achievements
    """
    __tablename__ = 'pending_game_discoveries'

    id = Column(Integer, primary_key=True, index=True)

    # Discovery source
    discovered_by_user_id = Column(Integer, ForeignKey('users.id'), nullable=True, index=True)
    source_provider = Column(String(32), nullable=False, index=True)  # steam, xbox, psn, etc.

    # Game identification
    provider_game_id = Column(String(128), nullable=False, index=True)  # Steam app_id, Xbox title_id, etc.
    game_name = Column(String(256), nullable=False)

    # Discovery metadata
    achievement_count = Column(Integer, default=0)  # How many achievements this game has
    sample_achievements = Column(JSON, nullable=True)  # First 5 achievement names for context

    # Cross-platform research (filled by admin)
    cross_platform_notes = Column(Text, nullable=True)  # Admin's research notes
    available_on_steam = Column(Boolean, nullable=True)
    available_on_xbox = Column(Boolean, nullable=True)
    available_on_psn = Column(Boolean, nullable=True)
    steam_app_id = Column(String(32), nullable=True)
    xbox_title_id = Column(String(64), nullable=True)
    psn_np_id = Column(String(64), nullable=True)

    # Forge eligibility
    has_forge_items = Column(Boolean, nullable=True)  # Does this game have forge-eligible achievements?
    forge_item_count = Column(Integer, nullable=True)  # How many items if added

    # Cross-platform auto-detection
    # When same game is discovered from multiple providers, they share a match_id
    cross_platform_match_id = Column(Integer, nullable=True, index=True)
    is_cross_platform = Column(Boolean, default=False, index=True)  # True if detected on multiple platforms

    # Status tracking
    status = Column(String(20), default='pending', index=True)
    priority = Column(Integer, default=0)  # Higher = more users have this game, cross-platform = +100
    discovery_count = Column(Integer, default=1)  # How many users have synced this game

    # Timestamps
    first_discovered_at = Column(DateTime, default=datetime.utcnow, index=True)
    last_seen_at = Column(DateTime, default=datetime.utcnow)
    reviewed_at = Column(DateTime, nullable=True)

    # Admin handling
    reviewed_by_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    admin_notes = Column(Text, nullable=True)

    # Relationships
    discovered_by = relationship("User", foreign_keys=[discovered_by_user_id])
    reviewed_by = relationship("User", foreign_keys=[reviewed_by_id])


# =============================================================================
# TOKEN ENCRYPTION (automatic via SQLAlchemy events)
# =============================================================================
# Encrypts access_token and refresh_token on write, decrypts on load.
# Handles legacy unencrypted tokens gracefully during migration.

from sqlalchemy import event

def _encrypt_tokens_on_set(target, value, oldvalue, initiator):
    """Encrypt token before storing in database."""
    if value is None or value == oldvalue:
        return value
    try:
        from app.services.crypto_service import encrypt_token, is_encrypted
        # Don't re-encrypt already encrypted values
        if is_encrypted(value):
            return value
        return encrypt_token(value)
    except Exception:
        # If encryption fails, store plaintext (shouldn't happen in prod)
        return value

def _setup_token_encryption():
    """Set up event listeners for token encryption."""
    event.listen(ProviderAccount.access_token, 'set', _encrypt_tokens_on_set, retval=True)
    event.listen(ProviderAccount.refresh_token, 'set', _encrypt_tokens_on_set, retval=True)

# Initialize encryption listeners
_setup_token_encryption()


def get_decrypted_token(provider_account, token_attr: str = "access_token") -> str:
    """
    Get decrypted token from a ProviderAccount.
    
    Use this instead of directly accessing .access_token or .refresh_token
    to ensure proper decryption.
    
    Args:
        provider_account: ProviderAccount instance
        token_attr: "access_token" or "refresh_token"
    
    Returns:
        Decrypted token string, or None if not set
    """
    from app.services.crypto_service import decrypt_token
    raw_value = getattr(provider_account, token_attr, None)
    return decrypt_token(raw_value)
