#!/usr/bin/env python3
"""
Cleanup orphaned forged items from the database.
Usage: python scripts/cleanup_orphaned_item.py
"""

import sqlite3
import os

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "socialauth.db")

def main():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        # Find all forged items
        cursor.execute("SELECT id, item_id, wallet_account_id FROM forged_achievements ORDER BY id")
        items = cursor.fetchall()

        print(f"\n=== All Forged Items in Database ({len(items)} total) ===\n")

        orphans = []
        for item_id_db, item_id, wallet_id in items:
            # Check if it's an elden-related orphan
            is_orphan = "elden" in item_id.lower() and item_id != "elden_lord_helm"

            status = " [ORPHAN - will delete]" if is_orphan else ""
            print(f"  ID: {item_id_db} | item_id: {item_id} | wallet: {wallet_id}{status}")

            if is_orphan:
                orphans.append((item_id_db, item_id))

        if not orphans:
            print("\n✓ No orphaned elden items found.")
            return

        print(f"\n=== Found {len(orphans)} orphaned item(s) ===")
        confirm = input("\nDelete these orphaned items? (yes/no): ")

        if confirm.lower() == "yes":
            for db_id, item_id in orphans:
                print(f"  Deleting: {item_id} (ID: {db_id})")
                # Delete associated weapon_stats first (foreign key)
                cursor.execute("DELETE FROM weapon_stats WHERE forged_achievement_id = ?", (db_id,))
                # Delete the forged achievement
                cursor.execute("DELETE FROM forged_achievements WHERE id = ?", (db_id,))
            conn.commit()
            print("\n✓ Orphaned items deleted successfully!")
        else:
            print("\n✗ Cancelled - no changes made.")

    finally:
        conn.close()

if __name__ == "__main__":
    main()
