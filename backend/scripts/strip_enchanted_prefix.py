#!/usr/bin/env python3
"""
Strip the "Enchanted " prefix from existing forged item names.

The "Enchanted" rarity prefix was disabled but items forged before
the change still have it in their item_name. This script removes it.

Usage:
    cd backend
    python scripts/strip_enchanted_prefix.py

Add --dry-run to preview changes without modifying the database.
"""

import sys
import os
import re

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.models import ForgedAchievement

# Old rarity prefixes that should be stripped
# These were disabled but may exist in old item names
OLD_RARITY_PREFIXES = [
    "Enchanted",  # Was: Rare
    "Mystical",   # May have been Epic
    "Mythic",     # May have been Legendary
]


def main():
    dry_run = "--dry-run" in sys.argv

    # Get database URL from environment or use default
    database_url = os.getenv("DATABASE_URL", "sqlite:///./socialauth.db")

    print(f"Connecting to database: {database_url[:50]}...")
    engine = create_engine(database_url)
    Session = sessionmaker(bind=engine)
    session = Session()

    try:
        # Find all forged items
        items = session.query(ForgedAchievement).all()
        print(f"Found {len(items)} forged items")

        updated_count = 0

        for item in items:
            if not item.item_name:
                continue

            original_name = item.item_name
            new_name = original_name

            # Check each prefix and remove if found at start
            for prefix in OLD_RARITY_PREFIXES:
                pattern = rf"^{re.escape(prefix)}\s+"
                if re.match(pattern, new_name):
                    new_name = re.sub(pattern, "", new_name)
                    break  # Only remove one prefix

            if new_name != original_name:
                print(f"  [{item.id}] '{original_name}' -> '{new_name}'")
                if not dry_run:
                    item.item_name = new_name
                updated_count += 1

        if updated_count > 0:
            if dry_run:
                print(f"\nDRY RUN: Would update {updated_count} items")
                print("Run without --dry-run to apply changes")
            else:
                session.commit()
                print(f"\nUpdated {updated_count} items successfully")
        else:
            print("\nNo items needed updating")

    except Exception as e:
        print(f"Error: {e}")
        session.rollback()
        raise
    finally:
        session.close()


if __name__ == "__main__":
    main()
