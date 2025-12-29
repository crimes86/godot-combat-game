"""
Community Contribution Service

Handles:
- Platform mapping submissions
- Rarity dispute submissions
- Voting with expert-gating
- Auto-approval at vote threshold
- Reward tier checks and unlocking
- Leaderboard calculations
"""
import json
import os
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import func, desc

from app.models import (
    CommunityContribution,
    ContributionVote,
    ContributorProfile,
    User,
    AchievementCredit,
    Achievement,
    ChatMessage,
)


# Reward tier thresholds and definitions
REWARD_TIERS = {
    "archivist": {
        "threshold": 5,
        "title": "Archivist",
        "title_color": "#99ccff",  # Light blue
        "badge": None,
        "cape": None,
        "aura": None,
        "role": None,
    },
    "lorekeeper": {
        "threshold": 25,
        "title": "Lorekeeper",
        "title_color": "#cc99ff",  # Light purple
        "badge": "lorekeeper_badge",
        "cape": None,
        "aura": None,
        "role": None,
    },
    "curator": {
        "threshold": 100,
        "title": "Curator",
        "title_color": "#ffcc66",  # Gold
        "badge": "curator_badge",
        "cape": "curator_cape",
        "aura": "curator_aura",
        "role": "curator",
    },
}

# Chat room routing by rarity
RARITY_TO_ROOM = {
    "common": "newcomers",
    "uncommon": "newcomers",
    "rare": "rising",
    "epic": "veterans",
    "legendary": "legends",
}


def get_or_create_contributor_profile(db: Session, user_id: int) -> ContributorProfile:
    """Get or create a contributor profile for a user."""
    profile = db.query(ContributorProfile).filter(
        ContributorProfile.user_id == user_id
    ).first()

    if not profile:
        profile = ContributorProfile(
            user_id=user_id,
            total_approved=0,
            mappings_approved=0,
            disputes_approved=0,
            total_votes_cast=0,
            helpful_votes=0,
            rewards_claimed=[],
            rewards_available=[],
            contributor_role="contributor",
        )
        db.add(profile)
        db.commit()
        db.refresh(profile)

    return profile


MAX_SUBMISSIONS_PER_DAY = 20
MIN_REASON_LENGTH = 10
MAX_REASON_LENGTH = 500


def _check_submission_rate_limit(db: Session, user_id: int) -> bool:
    """Check if user has exceeded daily submission limit."""
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    count = db.query(CommunityContribution).filter(
        CommunityContribution.user_id == user_id,
        CommunityContribution.created_at >= today_start,
    ).count()
    return count < MAX_SUBMISSIONS_PER_DAY


def _validate_reason(reason: str) -> str:
    """Validate and sanitize reason text."""
    reason = reason.strip()
    if len(reason) < MIN_REASON_LENGTH:
        raise ValueError(f"Reason must be at least {MIN_REASON_LENGTH} characters")
    if len(reason) > MAX_REASON_LENGTH:
        raise ValueError(f"Reason must be at most {MAX_REASON_LENGTH} characters")
    return reason


def submit_platform_mapping(
    db: Session,
    user_id: int,
    game_key: str,
    steam_api_name: str,
    target_platform: str,
    target_api_name: str,
    game_name: str,
    achievement_name: str,
    reason: str,
) -> Tuple[CommunityContribution, Optional[ChatMessage]]:
    """
    Submit a cross-platform achievement mapping contribution.

    Expert-gating: User must have achievements from at least one of the platforms.
    """
    # Rate limiting
    if not _check_submission_rate_limit(db, user_id):
        raise ValueError(f"Daily submission limit ({MAX_SUBMISSIONS_PER_DAY}) reached. Try again tomorrow.")

    # Validate reason
    reason = _validate_reason(reason)

    # Check expert-gating
    has_steam = db.query(AchievementCredit).filter(
        AchievementCredit.user_id == user_id,
        AchievementCredit.provider_name == "steam",
        AchievementCredit.is_original_claim == True,
    ).first() is not None

    has_target = db.query(AchievementCredit).filter(
        AchievementCredit.user_id == user_id,
        AchievementCredit.provider_name == target_platform,
        AchievementCredit.is_original_claim == True,
    ).first() is not None

    user = db.query(User).filter(User.id == user_id).first()
    is_curator = user and user.contributor_role == "curator"

    if not is_curator and not has_steam and not has_target:
        raise ValueError(f"Must have achievements from Steam or {target_platform} to submit mappings")

    # Create contribution
    contribution = CommunityContribution(
        contribution_type="platform_mapping",
        user_id=user_id,
        data={
            "game_key": game_key,
            "steam_api_name": steam_api_name,
            "target_platform": target_platform,
            "target_api_name": target_api_name,
            "game_name": game_name,
            "achievement_name": achievement_name,
        },
        reason=reason,
        votes_up=0,
        votes_down=0,
        votes_threshold=5,
        status="pending",
        created_at=datetime.utcnow(),
        expires_at=datetime.utcnow() + timedelta(days=7),
    )
    db.add(contribution)
    db.commit()
    db.refresh(contribution)

    # Post to chat (newcomers room for mappings)
    chat_message = _post_contribution_to_chat(
        db, contribution, user, "rising"
    )

    # Update profile
    profile = get_or_create_contributor_profile(db, user_id)
    if not profile.first_contribution_at:
        profile.first_contribution_at = datetime.utcnow()
    profile.last_contribution_at = datetime.utcnow()
    db.commit()

    # Auto-approve if curator
    if is_curator:
        _auto_approve_contribution(db, contribution)

    return contribution, chat_message


def submit_rarity_dispute(
    db: Session,
    user_id: int,
    achievement_id: int,
    suggested_rarity: str,
    reason: str,
) -> Tuple[CommunityContribution, Optional[ChatMessage]]:
    """
    Submit a rarity dispute contribution.

    Expert-gating: User must have the achievement being disputed.
    """
    # Rate limiting
    if not _check_submission_rate_limit(db, user_id):
        raise ValueError(f"Daily submission limit ({MAX_SUBMISSIONS_PER_DAY}) reached. Try again tomorrow.")

    # Validate reason
    reason = _validate_reason(reason)

    # Validate rarity value
    valid_rarities = ["common", "uncommon", "rare", "epic", "legendary"]
    if suggested_rarity.lower() not in valid_rarities:
        raise ValueError(f"Invalid rarity. Must be one of: {', '.join(valid_rarities)}")

    # Get achievement
    achievement = db.query(Achievement).filter(Achievement.id == achievement_id).first()
    if not achievement:
        raise ValueError("Achievement not found")

    # Check expert-gating
    has_achievement = db.query(AchievementCredit).filter(
        AchievementCredit.user_id == user_id,
        AchievementCredit.achievement_id == achievement_id,
        AchievementCredit.is_original_claim == True,
    ).first() is not None

    user = db.query(User).filter(User.id == user_id).first()
    is_curator = user and user.contributor_role == "curator"

    if not is_curator and not has_achievement:
        raise ValueError("Must have the achievement to dispute its rarity")

    # Determine current rarity from effort score
    current_rarity = achievement.rarity_tier or "common"

    # Create contribution
    contribution = CommunityContribution(
        contribution_type="rarity_dispute",
        user_id=user_id,
        data={
            "achievement_id": achievement_id,
            "achievement_name": achievement.display_name or achievement.name,
            "game_app_id": achievement.app_id,
            "current_rarity": current_rarity.lower(),
            "suggested_rarity": suggested_rarity.lower(),
            "current_effort_score": achievement.effort_score,
        },
        reason=reason,
        votes_up=0,
        votes_down=0,
        votes_threshold=5,
        status="pending",
        created_at=datetime.utcnow(),
        expires_at=datetime.utcnow() + timedelta(days=7),
    )
    db.add(contribution)
    db.commit()
    db.refresh(contribution)

    # Post to appropriate chat room based on rarity
    room = RARITY_TO_ROOM.get(suggested_rarity.lower(), "newcomers")
    chat_message = _post_contribution_to_chat(db, contribution, user, room)

    # Update profile
    profile = get_or_create_contributor_profile(db, user_id)
    if not profile.first_contribution_at:
        profile.first_contribution_at = datetime.utcnow()
    profile.last_contribution_at = datetime.utcnow()
    db.commit()

    # Auto-approve if curator
    if is_curator:
        _auto_approve_contribution(db, contribution)

    return contribution, chat_message


def vote_on_contribution(
    db: Session,
    user_id: int,
    contribution_id: int,
    vote: int,  # 1 = agree, -1 = disagree
) -> Tuple[ContributionVote, bool]:
    """
    Vote on a contribution.

    Returns: (vote, was_approved) - was_approved is True if this vote triggered approval
    """
    contribution = db.query(CommunityContribution).filter(
        CommunityContribution.id == contribution_id,
        CommunityContribution.status == "pending",
    ).first()

    if not contribution:
        raise ValueError("Contribution not found or not pending")

    # Block self-voting
    if contribution.user_id == user_id:
        raise ValueError("Cannot vote on your own contribution")

    # Check if already voted
    existing_vote = db.query(ContributionVote).filter(
        ContributionVote.contribution_id == contribution_id,
        ContributionVote.user_id == user_id,
    ).first()

    if existing_vote:
        raise ValueError("Already voted on this contribution")

    # Check expert-gating
    user = db.query(User).filter(User.id == user_id).first()
    is_curator = user and user.contributor_role == "curator"

    if not is_curator:
        can_vote = _check_vote_eligibility(db, user_id, contribution)
        if not can_vote:
            raise ValueError("Not eligible to vote on this contribution")

    # Determine vote weight (curators get 3x)
    weight = 3 if is_curator else 1

    # Create vote
    vote_record = ContributionVote(
        contribution_id=contribution_id,
        user_id=user_id,
        vote=vote,
        weight=weight,
        voted_at=datetime.utcnow(),
    )
    db.add(vote_record)

    # Update contribution vote counts (weighted)
    if vote > 0:
        contribution.votes_up = (contribution.votes_up or 0) + weight
    else:
        contribution.votes_down = (contribution.votes_down or 0) + weight

    # Update voter's profile
    voter_profile = get_or_create_contributor_profile(db, user_id)
    voter_profile.total_votes_cast = (voter_profile.total_votes_cast or 0) + 1

    db.commit()

    # Check for auto-approval
    was_approved = False
    net_votes = (contribution.votes_up or 0) - (contribution.votes_down or 0)
    if net_votes >= contribution.votes_threshold:
        _auto_approve_contribution(db, contribution)
        was_approved = True

        # Update helpful_votes for all who voted agree
        agree_votes = db.query(ContributionVote).filter(
            ContributionVote.contribution_id == contribution_id,
            ContributionVote.vote > 0,
        ).all()
        for v in agree_votes:
            profile = get_or_create_contributor_profile(db, v.user_id)
            profile.helpful_votes = (profile.helpful_votes or 0) + 1
        db.commit()

    return vote_record, was_approved


def _check_vote_eligibility(db: Session, user_id: int, contribution: CommunityContribution) -> bool:
    """Check if user is eligible to vote based on expert-gating rules."""
    if contribution.contribution_type == "platform_mapping":
        data = contribution.data
        target_platform = data.get("target_platform", "")

        # Must have achievements from Steam or target platform
        has_steam = db.query(AchievementCredit).filter(
            AchievementCredit.user_id == user_id,
            AchievementCredit.provider_name == "steam",
            AchievementCredit.is_original_claim == True,
        ).first() is not None

        has_target = db.query(AchievementCredit).filter(
            AchievementCredit.user_id == user_id,
            AchievementCredit.provider_name == target_platform,
            AchievementCredit.is_original_claim == True,
        ).first() is not None

        return has_steam or has_target

    elif contribution.contribution_type == "rarity_dispute":
        data = contribution.data
        achievement_id = data.get("achievement_id")

        # Must have the achievement
        return db.query(AchievementCredit).filter(
            AchievementCredit.user_id == user_id,
            AchievementCredit.achievement_id == achievement_id,
            AchievementCredit.is_original_claim == True,
        ).first() is not None

    return False


def _auto_approve_contribution(db: Session, contribution: CommunityContribution):
    """Auto-approve a contribution and apply changes."""
    contribution.status = "approved"
    contribution.resolved_at = datetime.utcnow()

    # Get submitter
    user = db.query(User).filter(User.id == contribution.user_id).first()
    contribution.credit_display = f"Contributed by {user.username}" if user else None

    # Update contributor profile
    profile = get_or_create_contributor_profile(db, contribution.user_id)
    profile.total_approved = (profile.total_approved or 0) + 1

    if contribution.contribution_type == "platform_mapping":
        profile.mappings_approved = (profile.mappings_approved or 0) + 1
        _apply_platform_mapping(db, contribution)
    elif contribution.contribution_type == "rarity_dispute":
        profile.disputes_approved = (profile.disputes_approved or 0) + 1
        _apply_rarity_dispute(db, contribution)

    # Check for new reward unlocks
    _check_reward_unlocks(db, contribution.user_id)

    db.commit()


def _apply_platform_mapping(db: Session, contribution: CommunityContribution):
    """Apply an approved platform mapping to platform_mappings.json."""
    data = contribution.data

    # Load platform_mappings.json
    mappings_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
        "data", "platform_mappings.json"
    )

    try:
        with open(mappings_path, "r") as f:
            mappings = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        mappings = {"games": {}}

    game_key = data["game_key"]
    steam_api_name = data["steam_api_name"]
    target_platform = data["target_platform"]
    target_api_name = data["target_api_name"]
    game_name = data["game_name"]
    achievement_name = data["achievement_name"]

    # Initialize structure if needed
    if "games" not in mappings:
        mappings["games"] = {}
    if game_key not in mappings["games"]:
        mappings["games"][game_key] = {
            "name": game_name,
            "achievements": {}
        }
    if "achievements" not in mappings["games"][game_key]:
        mappings["games"][game_key]["achievements"] = {}
    if steam_api_name not in mappings["games"][game_key]["achievements"]:
        mappings["games"][game_key]["achievements"][steam_api_name] = {
            "name": achievement_name,
        }

    # Add the mapping
    mappings["games"][game_key]["achievements"][steam_api_name][target_platform] = target_api_name

    # Add contributor credit
    if "contributed_by" not in mappings["games"][game_key]["achievements"][steam_api_name]:
        mappings["games"][game_key]["achievements"][steam_api_name]["contributed_by"] = []

    user = db.query(User).filter(User.id == contribution.user_id).first()
    if user and user.username not in mappings["games"][game_key]["achievements"][steam_api_name]["contributed_by"]:
        mappings["games"][game_key]["achievements"][steam_api_name]["contributed_by"].append(user.username)

    # Save
    with open(mappings_path, "w") as f:
        json.dump(mappings, f, indent=2)


def _apply_rarity_dispute(db: Session, contribution: CommunityContribution):
    """Apply an approved rarity dispute to the achievement."""
    data = contribution.data
    achievement_id = data["achievement_id"]
    suggested_rarity = data["suggested_rarity"]

    achievement = db.query(Achievement).filter(Achievement.id == achievement_id).first()
    if achievement:
        achievement.rarity_tier = suggested_rarity.capitalize()
        db.commit()


def _check_reward_unlocks(db: Session, user_id: int):
    """Check if user has unlocked new reward tiers."""
    profile = get_or_create_contributor_profile(db, user_id)
    user = db.query(User).filter(User.id == user_id).first()

    total = profile.total_approved or 0
    claimed = profile.rewards_claimed or []
    available = profile.rewards_available or []

    for tier_id, tier_info in REWARD_TIERS.items():
        if total >= tier_info["threshold"]:
            if tier_id not in claimed and tier_id not in available:
                available.append(tier_id)

    profile.rewards_available = available

    # Auto-grant curator role if threshold reached
    if total >= REWARD_TIERS["curator"]["threshold"]:
        profile.contributor_role = "curator"
        if user:
            user.contributor_role = "curator"

    db.commit()


def claim_reward(db: Session, user_id: int, reward_id: str) -> Dict[str, Any]:
    """Claim an available reward."""
    profile = get_or_create_contributor_profile(db, user_id)
    user = db.query(User).filter(User.id == user_id).first()

    available = profile.rewards_available or []
    claimed = profile.rewards_claimed or []

    if reward_id not in available:
        raise ValueError("Reward not available")

    if reward_id in claimed:
        raise ValueError("Reward already claimed")

    tier_info = REWARD_TIERS.get(reward_id)
    if not tier_info:
        raise ValueError("Unknown reward tier")

    # Move to claimed
    available.remove(reward_id)
    claimed.append(reward_id)
    profile.rewards_available = available
    profile.rewards_claimed = claimed

    # Apply cosmetics to user
    if user:
        if tier_info.get("title"):
            user.active_title = tier_info["title"]

        badges = user.active_badges or []
        if tier_info.get("badge") and tier_info["badge"] not in badges:
            badges.append(tier_info["badge"])
            user.active_badges = badges

        if tier_info.get("role"):
            user.contributor_role = tier_info["role"]
            profile.contributor_role = tier_info["role"]

    db.commit()

    return {
        "reward_id": reward_id,
        "title": tier_info.get("title"),
        "badge": tier_info.get("badge"),
        "cape": tier_info.get("cape"),
        "aura": tier_info.get("aura"),
        "role": tier_info.get("role"),
    }


def get_pending_contributions(
    db: Session,
    contribution_type: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
) -> List[Dict[str, Any]]:
    """Get pending contributions for voting."""
    query = db.query(CommunityContribution).filter(
        CommunityContribution.status == "pending",
        CommunityContribution.expires_at > datetime.utcnow(),
    )

    if contribution_type:
        query = query.filter(CommunityContribution.contribution_type == contribution_type)

    contributions = query.order_by(
        desc(CommunityContribution.created_at)
    ).offset(offset).limit(limit).all()

    return [_contribution_to_dict(c) for c in contributions]


def get_contribution(db: Session, contribution_id: int) -> Optional[Dict[str, Any]]:
    """Get a single contribution by ID."""
    contribution = db.query(CommunityContribution).filter(
        CommunityContribution.id == contribution_id
    ).first()

    if not contribution:
        return None

    return _contribution_to_dict(contribution)


def get_contributor_profile(db: Session, user_id: int) -> Dict[str, Any]:
    """Get contributor profile and stats."""
    profile = get_or_create_contributor_profile(db, user_id)
    user = db.query(User).filter(User.id == user_id).first()

    return {
        "user_id": user_id,
        "username": user.username if user else None,
        "total_approved": profile.total_approved or 0,
        "mappings_approved": profile.mappings_approved or 0,
        "disputes_approved": profile.disputes_approved or 0,
        "total_votes_cast": profile.total_votes_cast or 0,
        "helpful_votes": profile.helpful_votes or 0,
        "rewards_claimed": profile.rewards_claimed or [],
        "rewards_available": profile.rewards_available or [],
        "contributor_role": profile.contributor_role or "contributor",
        "leaderboard_rank": profile.leaderboard_rank,
        "active_title": user.active_title if user else None,
        "active_badges": user.active_badges or [] if user else [],
        "first_contribution_at": profile.first_contribution_at.isoformat() if profile.first_contribution_at else None,
        "last_contribution_at": profile.last_contribution_at.isoformat() if profile.last_contribution_at else None,
    }


def get_leaderboard(db: Session, limit: int = 25) -> List[Dict[str, Any]]:
    """Get top contributors leaderboard."""
    profiles = db.query(ContributorProfile).filter(
        ContributorProfile.total_approved > 0
    ).order_by(
        desc(ContributorProfile.total_approved)
    ).limit(limit).all()

    result = []
    for i, profile in enumerate(profiles, 1):
        # Update rank
        profile.leaderboard_rank = i

        user = db.query(User).filter(User.id == profile.user_id).first()
        result.append({
            "rank": i,
            "user_id": profile.user_id,
            "username": user.username if user else "Unknown",
            "total_approved": profile.total_approved or 0,
            "mappings_approved": profile.mappings_approved or 0,
            "disputes_approved": profile.disputes_approved or 0,
            "contributor_role": profile.contributor_role or "contributor",
            "active_title": user.active_title if user else None,
        })

    db.commit()
    return result


def get_user_contributions(
    db: Session,
    user_id: int,
    status: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
) -> List[Dict[str, Any]]:
    """Get contributions submitted by a user."""
    query = db.query(CommunityContribution).filter(
        CommunityContribution.user_id == user_id
    )

    if status:
        query = query.filter(CommunityContribution.status == status)

    contributions = query.order_by(
        desc(CommunityContribution.created_at)
    ).offset(offset).limit(limit).all()

    return [_contribution_to_dict(c) for c in contributions]


def _contribution_to_dict(contribution: CommunityContribution) -> Dict[str, Any]:
    """Convert contribution to dictionary."""
    return {
        "id": contribution.id,
        "contribution_type": contribution.contribution_type,
        "user_id": contribution.user_id,
        "data": contribution.data,
        "reason": contribution.reason,
        "votes_up": contribution.votes_up or 0,
        "votes_down": contribution.votes_down or 0,
        "votes_threshold": contribution.votes_threshold or 5,
        "net_votes": (contribution.votes_up or 0) - (contribution.votes_down or 0),
        "status": contribution.status,
        "created_at": contribution.created_at.isoformat() if contribution.created_at else None,
        "expires_at": contribution.expires_at.isoformat() if contribution.expires_at else None,
        "resolved_at": contribution.resolved_at.isoformat() if contribution.resolved_at else None,
        "credit_display": contribution.credit_display,
    }


def _post_contribution_to_chat(
    db: Session,
    contribution: CommunityContribution,
    user: User,
    room: str,
) -> Optional[ChatMessage]:
    """Post a contribution to the appropriate chat room."""
    if contribution.contribution_type == "platform_mapping":
        data = contribution.data
        content = (
            f"[MAPPING] {user.username} suggests: "
            f"{data.get('game_name', 'Unknown')} - {data.get('achievement_name', 'Unknown')} "
            f"maps to {data.get('target_platform', 'Unknown')}: {data.get('target_api_name', 'Unknown')}"
        )
    elif contribution.contribution_type == "rarity_dispute":
        data = contribution.data
        content = (
            f"[DISPUTE] {user.username} suggests: "
            f"{data.get('achievement_name', 'Unknown')} should be "
            f"{data.get('suggested_rarity', 'Unknown')} (currently {data.get('current_rarity', 'Unknown')})"
        )
    else:
        return None

    message = ChatMessage(
        user_id=user.id,
        room=room,
        content=content,
        message_type="contribution",
        created_at=datetime.utcnow(),
    )
    db.add(message)
    db.commit()
    db.refresh(message)

    # Link message to contribution
    contribution.chat_message_id = message.id
    db.commit()

    return message


def expire_old_contributions(db: Session) -> int:
    """Expire contributions past their expiry date. Returns count expired."""
    expired = db.query(CommunityContribution).filter(
        CommunityContribution.status == "pending",
        CommunityContribution.expires_at < datetime.utcnow(),
    ).all()

    count = 0
    for contribution in expired:
        contribution.status = "expired"
        contribution.resolved_at = datetime.utcnow()
        count += 1

    db.commit()
    return count
