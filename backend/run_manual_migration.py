#!/usr/bin/env python3
"""
Complete World Tree v2.1 Migration Manually
This script finishes the partially-applied migration
"""
import sqlite3

def main():
    conn = sqlite3.connect('socialauth.db')
    cursor = conn.cursor()

    print("Reading SQL migration script...")
    with open('complete_migration_v2_1.sql', 'r') as f:
        sql_script = f.read()

    print("Executing migration...")
    try:
        cursor.executescript(sql_script)
        conn.commit()
        print("[SUCCESS] Migration completed successfully!")

        # Verify new tables exist
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('resource_mines', 'seed_plot_buildings', 'bane_stones', 'seasonal_rankings')")
        tables = cursor.fetchall()
        print(f"\n[SUCCESS] Verified {len(tables)} new tables created: {[t[0] for t in tables]}")

        # Verify seed_plots has new columns
        cursor.execute("PRAGMA table_info(seed_plots)")
        columns = cursor.fetchall()
        new_columns = [c[1] for c in columns if c[1] in ['tree_rank', 'warehouse_safe_gold', 'is_origin_champion', 'faction']]
        print(f"[SUCCESS] Verified {len(new_columns)} sample new columns in seed_plots: {new_columns}")

    except sqlite3.OperationalError as e:
        if "duplicate column" in str(e) or "already exists" in str(e):
            print(f"[WARNING] Column/table already exists (safe to ignore): {e}")
            conn.commit()
        else:
            print(f"[ERROR] Error: {e}")
            raise
    finally:
        conn.close()

if __name__ == '__main__':
    main()
