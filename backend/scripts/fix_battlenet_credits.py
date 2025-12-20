"""
Fix incorrectly credited achievements - removes non-Blizzard games from Battle.net credits.
"""
import sqlite3
import os

# Database path
DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'socialauth.db')

# Blizzard game app_id prefixes (these are valid for Battle.net)
BLIZZARD_PREFIXES = ('wow', 'd3', 'sc2', 'ow', 'hs', 'hots', 'w3', 'bnet')

def main():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # First, let's see what's incorrectly credited
    print("\n=== Finding incorrectly credited achievements ===\n")

    cursor.execute("""
        SELECT ac.id, a.display_name, a.app_id, pa.provider_name, pa.provider_user_id
        FROM achievement_credits ac
        JOIN achievements a ON ac.achievement_id = a.id
        JOIN provider_accounts pa ON ac.provider_account_id = pa.id
        WHERE pa.provider_name = 'battlenet'
    """)

    rows = cursor.fetchall()
    to_delete = []

    for row in rows:
        credit_id, display_name, app_id, provider_name, provider_user_id = row
        app_id_lower = (app_id or '').lower()

        # Check if this is NOT a Blizzard game
        is_blizzard = any(app_id_lower.startswith(prefix) for prefix in BLIZZARD_PREFIXES)

        if not is_blizzard and app_id:
            to_delete.append(credit_id)
            print(f"  [INVALID] {display_name} (app_id: {app_id}) - credited to {provider_name}")

    if not to_delete:
        print("  No incorrectly credited achievements found!")
        conn.close()
        return

    print(f"\n=== Found {len(to_delete)} invalid credits ===")

    confirm = input("\nDelete these invalid credits? (yes/no): ").strip().lower()

    if confirm == 'yes':
        cursor.execute(f"""
            DELETE FROM achievement_credits
            WHERE id IN ({','.join('?' * len(to_delete))})
        """, to_delete)
        conn.commit()
        print(f"\n✓ Deleted {cursor.rowcount} invalid achievement credits.")
    else:
        print("\nAborted. No changes made.")

    conn.close()

if __name__ == "__main__":
    main()
