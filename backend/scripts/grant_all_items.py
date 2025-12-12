"""
Grant all forge items to a user for testing.

Usage:
    python scripts/grant_all_items.py                    # Lists users, prompts for selection
    python scripts/grant_all_items.py --username kevin   # Grants to specific user
    python scripts/grant_all_items.py --user-id 1        # Grants to user by ID

Creates ForgedAchievement records for every item in items.json.
Safe to run multiple times (skips existing items).
"""

import sys
import os
import argparse
import hashlib
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import SessionLocal
from app.models import User, WalletAccount, ForgedAchievement
from app.services.item_forge_service import get_items


def get_or_create_wallet(db, user):
    """Get or create a test wallet for the user."""
    wallet = db.query(WalletAccount).filter(
        WalletAccount.user_id == user.id
    ).first()

    if not wallet:
        wallet = WalletAccount(
            user_id=user.id,
            wallet_address=f"0xtest{'0' * 34}{user.id:04d}",
            chain_id=137,
            linked_at=datetime.utcnow(),
        )
        db.add(wallet)
        db.flush()
        print(f"  Created test wallet: {wallet.wallet_address}")

    return wallet


def grant_all_items(db, user):
    """Grant all items from catalog to user."""
    # Grant admin status
    if not user.is_admin:
        user.is_admin = True
        print(f"  Granted admin status to {user.username}")

    # Get or create wallet
    wallet = get_or_create_wallet(db, user)

    # Load items
    items = get_items()
    print(f"\nFound {len(items)} items in catalog")

    granted = []
    skipped = []

    for idx, item in enumerate(items):
        item_id = item.get("item_id", f"item_{idx}")

        # Check if already granted
        existing = db.query(ForgedAchievement).filter(
            ForgedAchievement.wallet_account_id == wallet.id,
            ForgedAchievement.item_id == item_id
        ).first()

        if existing:
            # Update existing items to be claimed if they weren't
            if not existing.claimed_in_game_at:
                existing.claimed_in_game_at = datetime.utcnow()
                existing.bridge_status = "in_game"
                granted.append(item_id + " (updated)")
            else:
                skipped.append(item_id)
            continue

        # Generate unique token_id
        token_hash = hashlib.md5(f"test:{user.id}:{item_id}".encode()).hexdigest()
        test_token_id = int(token_hash[:8], 16)

        # Create forged record - auto-claimed to game inventory for testing
        forge_record = ForgedAchievement(
            achievement_credit_id=None,  # No real achievement
            wallet_account_id=wallet.id,
            token_id=test_token_id,
            contract_address="0x0000000000000000000000000000000000000000",
            chain_id=137,
            tx_hash=f"0xtest{idx:060d}",
            item_type=item.get("item_type", "weapon"),
            weapon_type=item.get("weapon_type"),
            item_id=item_id,
            item_name=item.get("item_name", item_id.replace("_", " ").title()),
            item_rarity=item.get("base_rarity", "common"),
            effect_intensity=0.7,
            effect_name=item.get("visuals", {}).get("effect", "standard_particles"),
            glow_color=item.get("visuals", {}).get("glow_color", "#888888"),
            effort_tier="Notable",
            vintage_years=0,
            is_secret=False,
            # Auto-claim to game for testing
            claimed_in_game_at=datetime.utcnow(),
            bridge_status="in_game",
        )
        db.add(forge_record)
        granted.append(item_id)

    db.commit()

    return granted, skipped


def list_users(db):
    """List all users in the database."""
    users = db.query(User).all()
    if not users:
        print("No users found in database.")
        return []

    print("\nAvailable users:")
    print("-" * 50)
    for u in users:
        admin_str = " [ADMIN]" if u.is_admin else ""
        print(f"  ID: {u.id:3d}  Username: {u.username}{admin_str}")
    print("-" * 50)
    return users


def main():
    parser = argparse.ArgumentParser(description="Grant all forge items to a user")
    parser.add_argument("--username", "-u", help="Username to grant items to")
    parser.add_argument("--user-id", "-i", type=int, help="User ID to grant items to")
    args = parser.parse_args()

    db = SessionLocal()

    try:
        user = None

        if args.user_id:
            user = db.query(User).filter(User.id == args.user_id).first()
            if not user:
                print(f"Error: No user found with ID {args.user_id}")
                sys.exit(1)
        elif args.username:
            user = db.query(User).filter(User.username == args.username).first()
            if not user:
                print(f"Error: No user found with username '{args.username}'")
                sys.exit(1)
        else:
            # List users and prompt for selection
            users = list_users(db)
            if not users:
                sys.exit(1)

            try:
                user_id_input = input("\nEnter user ID to grant items to: ").strip()
                user_id = int(user_id_input)
                user = db.query(User).filter(User.id == user_id).first()
                if not user:
                    print(f"Error: No user found with ID {user_id}")
                    sys.exit(1)
            except ValueError:
                print("Error: Invalid user ID")
                sys.exit(1)

        print(f"\nGranting all items to: {user.username} (ID: {user.id})")

        granted, skipped = grant_all_items(db, user)

        print(f"\nResults:")
        print(f"  Granted: {len(granted)} items")
        print(f"  Skipped: {len(skipped)} items (already owned)")

        if granted:
            print(f"\nNewly granted items:")
            for item_id in granted[:10]:
                print(f"    - {item_id}")
            if len(granted) > 10:
                print(f"    ... and {len(granted) - 10} more")

        print(f"\nDone! Items are now available in Godot.")

    finally:
        db.close()


if __name__ == "__main__":
    main()
