#!/usr/bin/env python3
"""
Cleanup script for old game logs.
Run daily via cron to prevent storage bloat.

Usage:
    python scripts/cleanup_old_logs.py [--days 30] [--dry-run]
"""
import sys
import os
import argparse
from datetime import datetime, timedelta

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import SessionLocal
from app.models import GameLog
from sqlalchemy import delete


def cleanup_logs(days: int = 30, dry_run: bool = False) -> int:
    """Delete game logs older than specified days."""
    cutoff = datetime.utcnow() - timedelta(days=days)

    db = SessionLocal()
    try:
        # Count logs to be deleted
        count = db.query(GameLog).filter(GameLog.created_at < cutoff).count()

        if count == 0:
            print(f"No logs older than {days} days found.")
            return 0

        if dry_run:
            print(f"[DRY RUN] Would delete {count} logs older than {days} days (before {cutoff})")
            return count

        # Delete old logs
        result = db.execute(
            delete(GameLog).where(GameLog.created_at < cutoff)
        )
        db.commit()

        deleted = result.rowcount
        print(f"Deleted {deleted} logs older than {days} days (before {cutoff})")
        return deleted

    finally:
        db.close()


def main():
    parser = argparse.ArgumentParser(description="Clean up old game logs")
    parser.add_argument("--days", type=int, default=30, help="Delete logs older than N days (default: 30)")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be deleted without actually deleting")
    args = parser.parse_args()

    cleanup_logs(days=args.days, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
