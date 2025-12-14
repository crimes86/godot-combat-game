-- Complete World Tree v2.1 Migration Manually
-- Run this script to finish the migration that was partially applied

-- Add remaining columns to seed_plots (check first 4 are already there)
ALTER TABLE seed_plots ADD COLUMN is_origin_champion BOOLEAN DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN champion_since DATETIME;
ALTER TABLE seed_plots ADD COLUMN is_decaying BOOLEAN DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN decay_complete_at DATETIME;
ALTER TABLE seed_plots ADD COLUMN migration_expires DATETIME;
ALTER TABLE seed_plots ADD COLUMN original_chunk_id INTEGER;

ALTER TABLE seed_plots ADD COLUMN tree_rank INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN tree_health INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN tree_max_health INTEGER DEFAULT 0 NOT NULL;

ALTER TABLE seed_plots ADD COLUMN guild_name VARCHAR(128);
ALTER TABLE seed_plots ADD COLUMN faction VARCHAR(32) DEFAULT 'individual' NOT NULL;

ALTER TABLE seed_plots ADD COLUMN upgrade_started_at DATETIME;
ALTER TABLE seed_plots ADD COLUMN upgrade_target_rank INTEGER;

ALTER TABLE seed_plots ADD COLUMN last_watered DATETIME;
ALTER TABLE seed_plots ADD COLUMN times_watered INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN growth_bonus_accumulated FLOAT DEFAULT 0.0 NOT NULL;

ALTER TABLE seed_plots ADD COLUMN allow_public_binding BOOLEAN DEFAULT 0 NOT NULL;

ALTER TABLE seed_plots ADD COLUMN warehouse_safe_gold INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN warehouse_safe_wood INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN warehouse_safe_stone INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN warehouse_safe_gems INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN warehouse_overflow_gold INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN warehouse_overflow_wood INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN warehouse_overflow_stone INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN warehouse_overflow_gems INTEGER DEFAULT 0 NOT NULL;

ALTER TABLE seed_plots ADD COLUMN claimed_mine_ids TEXT;

ALTER TABLE seed_plots ADD COLUMN defense_window_hour INTEGER DEFAULT 20 NOT NULL;
ALTER TABLE seed_plots ADD COLUMN defense_window_timezone_offset INTEGER DEFAULT 0 NOT NULL;

-- Backfill original_owner_id if needed
UPDATE seed_plots SET original_owner_id = owner_id WHERE original_owner_id IS NULL AND owner_id IS NOT NULL;

-- Create indexes
CREATE INDEX ix_seed_plots_original_owner_id ON seed_plots (original_owner_id);
CREATE INDEX ix_seed_plots_current_guild_id ON seed_plots (current_guild_id);
CREATE INDEX ix_seed_plots_is_origin_champion ON seed_plots (is_origin_champion);
CREATE INDEX ix_seed_plots_tree_rank ON seed_plots (tree_rank);
CREATE INDEX ix_seed_plots_faction ON seed_plots (faction);

-- Create resource_mines table
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
);

CREATE INDEX ix_resource_mines_shard_id ON resource_mines (shard_id);
CREATE INDEX ix_resource_mines_chunk_id ON resource_mines (chunk_id);
CREATE INDEX ix_resource_mines_owner_tree_id ON resource_mines (owner_tree_id);
CREATE INDEX ix_resource_mines_mine_type ON resource_mines (mine_type);

-- Create seed_plot_buildings table
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
);

CREATE INDEX ix_seed_plot_buildings_seed_plot_id ON seed_plot_buildings (seed_plot_id);
CREATE INDEX ix_seed_plot_buildings_building_type ON seed_plot_buildings (building_type);
CREATE INDEX ix_seed_plot_buildings_is_active ON seed_plot_buildings (is_active);

-- Create bane_stones table
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
);

CREATE INDEX ix_bane_stones_shard_id ON bane_stones (shard_id);
CREATE INDEX ix_bane_stones_target_tree_id ON bane_stones (target_tree_id);
CREATE INDEX ix_bane_stones_attacker_guild_id ON bane_stones (attacker_guild_id);
CREATE INDEX ix_bane_stones_is_active ON bane_stones (is_active);

-- Create seasonal_rankings table
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
);

CREATE INDEX ix_seasonal_rankings_shard_id ON seasonal_rankings (shard_id);
CREATE INDEX ix_seasonal_rankings_tree_id ON seasonal_rankings (tree_id);
CREATE INDEX ix_seasonal_rankings_guild_id ON seasonal_rankings (guild_id);
CREATE INDEX ix_seasonal_rankings_total_contribution ON seasonal_rankings (total_contribution);

-- Add boss_kills to world_tree_contributions
ALTER TABLE world_tree_contributions ADD COLUMN boss_kills INTEGER DEFAULT 0 NOT NULL;
