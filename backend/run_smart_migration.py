#!/usr/bin/env python3
"""
Smart World Tree v2.1 Migration
Checks what already exists and only adds what's missing
"""
import sqlite3

def column_exists(cursor, table, column):
    cursor.execute(f"PRAGMA table_info({table})")
    columns = [row[1] for row in cursor.fetchall()]
    return column in columns

def table_exists(cursor, table):
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,))
    return cursor.fetchone() is not None

def main():
    conn = sqlite3.connect('socialauth.db')
    cursor = conn.cursor()

    print("=" * 60)
    print("World Tree v2.1 Smart Migration")
    print("=" * 60)

    # Define all new columns for seed_plots
    seed_plot_columns = [
        ("is_origin_champion", "BOOLEAN DEFAULT 0 NOT NULL"),
        ("champion_since", "DATETIME"),
        ("is_decaying", "BOOLEAN DEFAULT 0 NOT NULL"),
        ("decay_complete_at", "DATETIME"),
        ("migration_expires", "DATETIME"),
        ("original_chunk_id", "INTEGER"),
        ("tree_rank", "INTEGER DEFAULT 0 NOT NULL"),
        ("tree_health", "INTEGER DEFAULT 0 NOT NULL"),
        ("tree_max_health", "INTEGER DEFAULT 0 NOT NULL"),
        ("guild_name", "VARCHAR(128)"),
        ("faction", "VARCHAR(32) DEFAULT 'individual' NOT NULL"),
        ("upgrade_started_at", "DATETIME"),
        ("upgrade_target_rank", "INTEGER"),
        ("last_watered", "DATETIME"),
        ("times_watered", "INTEGER DEFAULT 0 NOT NULL"),
        ("growth_bonus_accumulated", "FLOAT DEFAULT 0.0 NOT NULL"),
        ("allow_public_binding", "BOOLEAN DEFAULT 0 NOT NULL"),
        ("warehouse_safe_gold", "INTEGER DEFAULT 0 NOT NULL"),
        ("warehouse_safe_wood", "INTEGER DEFAULT 0 NOT NULL"),
        ("warehouse_safe_stone", "INTEGER DEFAULT 0 NOT NULL"),
        ("warehouse_safe_gems", "INTEGER DEFAULT 0 NOT NULL"),
        ("warehouse_overflow_gold", "INTEGER DEFAULT 0 NOT NULL"),
        ("warehouse_overflow_wood", "INTEGER DEFAULT 0 NOT NULL"),
        ("warehouse_overflow_stone", "INTEGER DEFAULT 0 NOT NULL"),
        ("warehouse_overflow_gems", "INTEGER DEFAULT 0 NOT NULL"),
        ("claimed_mine_ids", "TEXT"),
        ("defense_window_hour", "INTEGER DEFAULT 20 NOT NULL"),
        ("defense_window_timezone_offset", "INTEGER DEFAULT 0 NOT NULL"),
    ]

    # Add missing columns to seed_plots
    print("\n[1/6] Checking seed_plots columns...")
    added_count = 0
    for col_name, col_def in seed_plot_columns:
        if not column_exists(cursor, 'seed_plots', col_name):
            try:
                cursor.execute(f"ALTER TABLE seed_plots ADD COLUMN {col_name} {col_def}")
                print(f"  [+] Added column: {col_name}")
                added_count += 1
            except sqlite3.OperationalError as e:
                print(f"  [SKIP] {col_name}: {e}")
        else:
            print(f"  [OK] Column already exists: {col_name}")

    print(f"[SUCCESS] Added {added_count} new columns to seed_plots")

    # Backfill original_owner_id
    if column_exists(cursor, 'seed_plots', 'original_owner_id'):
        cursor.execute("UPDATE seed_plots SET original_owner_id = owner_id WHERE original_owner_id IS NULL AND owner_id IS NOT NULL")
        print("[SUCCESS] Backfilled original_owner_id from owner_id")

    # Create indexes
    print("\n[2/6] Creating indexes...")
    indexes = [
        ("ix_seed_plots_original_owner_id", "seed_plots", "original_owner_id"),
        ("ix_seed_plots_current_guild_id", "seed_plots", "current_guild_id"),
        ("ix_seed_plots_is_origin_champion", "seed_plots", "is_origin_champion"),
        ("ix_seed_plots_tree_rank", "seed_plots", "tree_rank"),
        ("ix_seed_plots_faction", "seed_plots", "faction"),
    ]
    for idx_name, table, column in indexes:
        try:
            cursor.execute(f"CREATE INDEX {idx_name} ON {table} ({column})")
            print(f"  [+] Created index: {idx_name}")
        except sqlite3.OperationalError:
            print(f"  [OK] Index already exists: {idx_name}")

    # Create new tables
    print("\n[3/6] Creating resource_mines table...")
    if not table_exists(cursor, 'resource_mines'):
        cursor.execute("""
            CREATE TABLE resource_mines (
                id INTEGER PRIMARY KEY,
                shard_id VARCHAR(32) NOT NULL,
                chunk_id INTEGER NOT NULL,
                mine_type VARCHAR(16) NOT NULL,
                position_x FLOAT NOT NULL,
                position_y FLOAT NOT NULL,
                owner_tree_id INTEGER,
                last_collected DATETIME,
                last_collector VARCHAR(64),
                quick_collect_count INTEGER DEFAULT 0 NOT NULL,
                resources_accumulated INTEGER DEFAULT 0 NOT NULL,
                created_at DATETIME NOT NULL,
                FOREIGN KEY(owner_tree_id) REFERENCES seed_plots(id)
            )
        """)
        cursor.execute("CREATE INDEX ix_resource_mines_shard_id ON resource_mines (shard_id)")
        cursor.execute("CREATE INDEX ix_resource_mines_chunk_id ON resource_mines (chunk_id)")
        cursor.execute("CREATE INDEX ix_resource_mines_owner_tree_id ON resource_mines (owner_tree_id)")
        cursor.execute("CREATE INDEX ix_resource_mines_mine_type ON resource_mines (mine_type)")
        print("  [+] Created resource_mines table with indexes")
    else:
        print("  [OK] resource_mines table already exists")

    print("\n[4/6] Creating seed_plot_buildings table...")
    if not table_exists(cursor, 'seed_plot_buildings'):
        cursor.execute("""
            CREATE TABLE seed_plot_buildings (
                id INTEGER PRIMARY KEY,
                seed_plot_id INTEGER NOT NULL,
                building_type VARCHAR(32) NOT NULL,
                position_slot VARCHAR(1) NOT NULL,
                health INTEGER DEFAULT 1000 NOT NULL,
                max_health INTEGER DEFAULT 1000 NOT NULL,
                is_protected BOOLEAN DEFAULT 0 NOT NULL,
                is_active BOOLEAN DEFAULT 1 NOT NULL,
                activation_cost INTEGER DEFAULT 0 NOT NULL,
                original_cost INTEGER NOT NULL,
                created_at DATETIME NOT NULL,
                destroyed_at DATETIME,
                activated_at DATETIME,
                vendor_inventory TEXT,
                vendor_prices TEXT,
                total_sales INTEGER DEFAULT 0 NOT NULL,
                shrine_buff_type VARCHAR(32),
                FOREIGN KEY(seed_plot_id) REFERENCES seed_plots(id)
            )
        """)
        cursor.execute("CREATE INDEX ix_seed_plot_buildings_seed_plot_id ON seed_plot_buildings (seed_plot_id)")
        cursor.execute("CREATE INDEX ix_seed_plot_buildings_building_type ON seed_plot_buildings (building_type)")
        cursor.execute("CREATE INDEX ix_seed_plot_buildings_is_active ON seed_plot_buildings (is_active)")
        print("  [+] Created seed_plot_buildings table with indexes")
    else:
        print("  [OK] seed_plot_buildings table already exists")

    print("\n[5/6] Creating bane_stones table...")
    if not table_exists(cursor, 'bane_stones'):
        cursor.execute("""
            CREATE TABLE bane_stones (
                id INTEGER PRIMARY KEY,
                shard_id VARCHAR(32) NOT NULL,
                target_tree_id INTEGER NOT NULL,
                attacker_guild_id VARCHAR(64) NOT NULL,
                health INTEGER DEFAULT 50000 NOT NULL,
                max_health INTEGER DEFAULT 50000 NOT NULL,
                planted_at DATETIME NOT NULL,
                window_start DATETIME,
                window_end DATETIME,
                is_active BOOLEAN DEFAULT 0 NOT NULL,
                outcome VARCHAR(16),
                FOREIGN KEY(target_tree_id) REFERENCES seed_plots(id)
            )
        """)
        cursor.execute("CREATE INDEX ix_bane_stones_shard_id ON bane_stones (shard_id)")
        cursor.execute("CREATE INDEX ix_bane_stones_target_tree_id ON bane_stones (target_tree_id)")
        cursor.execute("CREATE INDEX ix_bane_stones_attacker_guild_id ON bane_stones (attacker_guild_id)")
        cursor.execute("CREATE INDEX ix_bane_stones_is_active ON bane_stones (is_active)")
        print("  [+] Created bane_stones table with indexes")
    else:
        print("  [OK] bane_stones table already exists")

    print("\n[6/6] Creating seasonal_rankings table...")
    if not table_exists(cursor, 'seasonal_rankings'):
        cursor.execute("""
            CREATE TABLE seasonal_rankings (
                id INTEGER PRIMARY KEY,
                shard_id VARCHAR(32) NOT NULL,
                tree_id INTEGER NOT NULL,
                guild_id VARCHAR(64) NOT NULL,
                total_contribution INTEGER DEFAULT 0 NOT NULL,
                total_kills INTEGER DEFAULT 0 NOT NULL,
                total_boss_kills INTEGER DEFAULT 0 NOT NULL,
                total_waterings INTEGER DEFAULT 0 NOT NULL,
                weeks_participated INTEGER DEFAULT 0 NOT NULL,
                weeks_won INTEGER DEFAULT 0 NOT NULL,
                highest_rank_achieved INTEGER DEFAULT 0 NOT NULL,
                first_contribution DATETIME,
                last_contribution DATETIME,
                FOREIGN KEY(tree_id) REFERENCES seed_plots(id)
            )
        """)
        cursor.execute("CREATE INDEX ix_seasonal_rankings_shard_id ON seasonal_rankings (shard_id)")
        cursor.execute("CREATE INDEX ix_seasonal_rankings_tree_id ON seasonal_rankings (tree_id)")
        cursor.execute("CREATE INDEX ix_seasonal_rankings_guild_id ON seasonal_rankings (guild_id)")
        cursor.execute("CREATE INDEX ix_seasonal_rankings_total_contribution ON seasonal_rankings (total_contribution)")
        print("  [+] Created seasonal_rankings table with indexes")
    else:
        print("  [OK] seasonal_rankings table already exists")

    # Add boss_kills to world_tree_contributions
    print("\n[7/7] Adding boss_kills column...")
    if not column_exists(cursor, 'world_tree_contributions', 'boss_kills'):
        cursor.execute("ALTER TABLE world_tree_contributions ADD COLUMN boss_kills INTEGER DEFAULT 0 NOT NULL")
        print("  [+] Added boss_kills column to world_tree_contributions")
    else:
        print("  [OK] boss_kills column already exists")

    conn.commit()
    conn.close()

    print("\n" + "=" * 60)
    print("[SUCCESS] World Tree v2.1 migration completed!")
    print("=" * 60)

if __name__ == '__main__':
    main()
