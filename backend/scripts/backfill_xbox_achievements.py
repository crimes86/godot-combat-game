#!/usr/bin/env python3
"""
One-time script to backfill ALL Xbox achievements for all games a user owns.

This fetches achievement data even for games where the user hasn't earned any,
which populates the Achievement table for cross-platform matching in the Tapestry.

Usage:
    python scripts/backfill_xbox_achievements.py
"""
import asyncio
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import SessionLocal
from app.models import Achievement, ProviderAccount, PendingGameDiscovery
from app.services.effort_scoring import compute_xbox_effort, compute_rarity_from_effort
from app.services.crypto_service import decrypt_token
import httpx
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OPENXBL_API_BASE = "https://xbl.io/api/v2"


async def fetch_all_xbox_achievements():
    """Fetch ALL achievements for ALL Xbox games the user owns."""
    db = SessionLocal()

    try:
        # Get active Xbox accounts
        xbox_accounts = db.query(ProviderAccount).filter(
            ProviderAccount.provider_name == "xbox",
            ProviderAccount.is_active == True
        ).all()

        if not xbox_accounts:
            logger.error("No active Xbox accounts found")
            return

        for account in xbox_accounts:
            logger.info(f"Processing Xbox account: {account.provider_user_id}")

            token = decrypt_token(account.access_token)
            if not token:
                logger.error(f"No token for account {account.id}")
                continue

            xuid = account.provider_user_id

            headers = {
                "X-Authorization": token,
                "X-Contract": "100",
                "Accept": "application/json",
            }

            # Get all titles
            async with httpx.AsyncClient() as client:
                resp = await client.get(
                    f"{OPENXBL_API_BASE}/achievements",
                    headers=headers,
                    timeout=30.0
                )

                if resp.status_code != 200:
                    logger.error(f"Failed to fetch titles: {resp.status_code}")
                    continue

                data = resp.json()
                titles = data.get("titles", [])

                logger.info(f"Found {len(titles)} titles to process")

                total_achievements_stored = 0
                games_processed = 0

                for title in titles:
                    title_id = str(title.get("titleId", ""))
                    title_name = title.get("name", f"Xbox Game {title_id}")

                    # Check existing achievement count
                    existing_count = db.query(Achievement).filter(
                        Achievement.app_id == title_id
                    ).count()

                    achievement_summary = title.get("achievement", {})
                    total_possible = achievement_summary.get("totalAchievements", 0) if isinstance(achievement_summary, dict) else 0

                    if existing_count >= total_possible and total_possible > 0:
                        logger.info(f"Skipping {title_name}: already have {existing_count}/{total_possible} achievements")
                        continue

                    if total_possible == 0:
                        logger.info(f"Skipping {title_name}: no achievements")
                        continue

                    # Fetch individual achievements for this title
                    logger.info(f"Fetching achievements for: {title_name} ({total_possible} total)")

                    try:
                        ach_resp = await client.get(
                            f"{OPENXBL_API_BASE}/achievements/player/{xuid}/{title_id}",
                            headers=headers,
                            timeout=30.0
                        )

                        if ach_resp.status_code != 200:
                            logger.warning(f"Failed to fetch achievements for {title_name}: {ach_resp.status_code}")
                            continue

                        ach_data = ach_resp.json()
                        achievements = ach_data.get("achievements", [])

                        stored = 0
                        sample_names = []

                        for ach in achievements:
                            ach_id = str(ach.get("id", ""))
                            ach_name = ach.get("name", f"Achievement {ach_id}")
                            ach_desc = ach.get("description", "")

                            # Collect sample names for discovery update
                            if len(sample_names) < 5:
                                sample_names.append(ach_name)

                            # Get gamerscore
                            try:
                                gamerscore = int(ach.get("rewards", [{}])[0].get("value", 0)) if ach.get("rewards") else 0
                            except (ValueError, TypeError):
                                gamerscore = 0

                            # Rarity
                            rarity_data = ach.get("rarity", {})
                            rarity_percent = None
                            if isinstance(rarity_data, dict):
                                try:
                                    rarity_percent = float(rarity_data.get("currentPercentage", 0))
                                    if rarity_percent == 0:
                                        rarity_percent = None
                                except (ValueError, TypeError):
                                    pass

                            effort_score = compute_xbox_effort(gamerscore=gamerscore, global_percent=rarity_percent)
                            rarity_tier = compute_rarity_from_effort(effort_score)

                            # Icon
                            icon_url = None
                            media_assets = ach.get("mediaAssets", [])
                            if media_assets:
                                icon_url = media_assets[0].get("url")

                            # Upsert achievement
                            db_ach = db.query(Achievement).filter_by(
                                app_id=title_id,
                                api_name=ach_id
                            ).first()

                            if not db_ach:
                                db_ach = Achievement(
                                    app_id=title_id,
                                    api_name=ach_id,
                                    name=ach_name,
                                    display_name=ach_name,
                                    description=ach_desc,
                                    icon_url=icon_url,
                                    effort_score=effort_score,
                                    effort_auto=True,
                                    rarity_tier=rarity_tier,
                                )
                                db.add(db_ach)
                                stored += 1
                            else:
                                # Update if needed
                                if icon_url and not db_ach.icon_url:
                                    db_ach.icon_url = icon_url

                        db.commit()

                        # Update discovery with sample achievements
                        discovery = db.query(PendingGameDiscovery).filter(
                            PendingGameDiscovery.source_provider == "xbox",
                            PendingGameDiscovery.provider_game_id == title_id
                        ).first()

                        if discovery and sample_names:
                            discovery.sample_achievements = sample_names
                            discovery.achievement_count = len(achievements)
                            db.commit()

                        if stored > 0:
                            logger.info(f"  Stored {stored} new achievements for {title_name}")
                            total_achievements_stored += stored

                        games_processed += 1

                        # Rate limiting - OpenXBL has 150 req/hour on free tier
                        await asyncio.sleep(0.5)

                    except Exception as e:
                        logger.error(f"Error fetching {title_name}: {e}")
                        continue

                logger.info(f"\n=== COMPLETE ===")
                logger.info(f"Games processed: {games_processed}")
                logger.info(f"Total achievements stored: {total_achievements_stored}")

    finally:
        db.close()


if __name__ == "__main__":
    asyncio.run(fetch_all_xbox_achievements())
