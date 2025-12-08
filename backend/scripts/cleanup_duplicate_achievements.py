"""
One-time script to clean up duplicate Battle.net achievements.

Duplicates were created when app_id="wow" was added to the lookup filter,
causing achievements with app_id=None to not be found.

This script:
1. Finds duplicate achievements by api_name
2. Keeps the one with app_id="wow" (or the one with most credits)
3. Moves credits from duplicates to the kept achievement
4. Deletes duplicate achievements
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import SessionLocal
from app.models import Achievement, AchievementCredit
from sqlalchemy import func
from collections import defaultdict

def cleanup_duplicates():
    db = SessionLocal()

    try:
        # Find all achievements that might be WoW achievements (no app_id or app_id="wow")
        all_achs = db.query(Achievement).filter(
            (Achievement.app_id == None) |
            (Achievement.app_id == "") |
            (Achievement.app_id == "wow")
        ).all()

        # Group by api_name
        by_api_name = defaultdict(list)
        for ach in all_achs:
            by_api_name[ach.api_name].append(ach)

        # Find duplicates
        duplicates = {k: v for k, v in by_api_name.items() if len(v) > 1}

        print(f"Found {len(duplicates)} api_names with duplicates")

        total_merged = 0
        total_credits_moved = 0
        total_deleted = 0

        for api_name, achs in duplicates.items():
            # Prefer the one with app_id="wow", otherwise the one with most credits
            achs_with_wow = [a for a in achs if a.app_id == "wow"]

            if achs_with_wow:
                keep = achs_with_wow[0]
            else:
                # Keep the one with most credits
                keep = max(achs, key=lambda a: db.query(AchievementCredit).filter_by(achievement_id=a.id).count())

            # Move credits from other achievements to keep
            for ach in achs:
                if ach.id == keep.id:
                    continue

                # Get credits pointing to this duplicate
                credits = db.query(AchievementCredit).filter_by(achievement_id=ach.id).all()

                for credit in credits:
                    # Check if there's already a credit for this user/provider/achievement combo
                    existing = db.query(AchievementCredit).filter_by(
                        user_id=credit.user_id,
                        provider_account_id=credit.provider_account_id,
                        achievement_id=keep.id
                    ).first()

                    if existing:
                        # Delete the duplicate credit
                        db.delete(credit)
                    else:
                        # Move credit to the kept achievement
                        credit.achievement_id = keep.id
                        total_credits_moved += 1

                # Delete the duplicate achievement
                db.delete(ach)
                total_deleted += 1

            # Ensure the kept achievement has app_id="wow"
            if keep.app_id != "wow":
                keep.app_id = "wow"

            total_merged += 1

        db.commit()

        print(f"\nCleanup complete:")
        print(f"  - Merged {total_merged} duplicate achievement groups")
        print(f"  - Moved {total_credits_moved} credits")
        print(f"  - Deleted {total_deleted} duplicate achievements")

        # Also delete any orphaned credits (pointing to deleted achievements)
        orphaned = db.query(AchievementCredit).filter(
            ~AchievementCredit.achievement_id.in_(
                db.query(Achievement.id)
            )
        ).count()

        if orphaned > 0:
            print(f"  - Found {orphaned} orphaned credits (would need separate cleanup)")

    finally:
        db.close()


if __name__ == "__main__":
    print("Cleaning up duplicate Battle.net achievements...")
    cleanup_duplicates()
