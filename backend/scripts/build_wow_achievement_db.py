"""
One-time script to build a complete WoW achievement database.

Fetches all 8000+ achievements from Blizzard API and saves them as a static JSON lookup.
This takes ~2-3 minutes due to API calls, but only needs to run once per WoW patch.

Output: app/data/wow_achievements.json
"""

import httpx
import json
import os
import asyncio
from datetime import datetime

TOKEN_URL = "https://oauth.battle.net/token"
API_BASE = "https://us.api.blizzard.com"


async def get_access_token(client_id: str, client_secret: str) -> str:
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            TOKEN_URL,
            data={"grant_type": "client_credentials"},
            auth=(client_id, client_secret)
        )
        resp.raise_for_status()
        return resp.json()["access_token"]


async def fetch_achievement_index(token: str) -> list:
    """Get list of all achievement IDs."""
    headers = {"Authorization": f"Bearer {token}"}
    url = f"{API_BASE}/data/wow/achievement/index"
    params = {"namespace": "static-us", "locale": "en_US"}

    async with httpx.AsyncClient() as client:
        resp = await client.get(url, headers=headers, params=params)
        resp.raise_for_status()
        data = resp.json()
        return [a["id"] for a in data.get("achievements", [])]


async def fetch_achievement_categories(token: str) -> dict:
    """Get achievement categories for classification."""
    headers = {"Authorization": f"Bearer {token}"}
    url = f"{API_BASE}/data/wow/achievement-category/index"
    params = {"namespace": "static-us", "locale": "en_US"}

    async with httpx.AsyncClient() as client:
        resp = await client.get(url, headers=headers, params=params)
        if resp.status_code == 200:
            data = resp.json()
            # Build category lookup
            categories = {}
            for cat in data.get("categories", []) + data.get("root_categories", []):
                categories[cat["id"]] = cat.get("name", "Unknown")
            return categories
        return {}


async def fetch_achievement_batch(client: httpx.AsyncClient, token: str, ach_ids: list) -> list:
    """Fetch a batch of achievements concurrently."""
    headers = {"Authorization": f"Bearer {token}"}
    params = {"namespace": "static-us", "locale": "en_US"}

    async def fetch_one(ach_id):
        try:
            url = f"{API_BASE}/data/wow/achievement/{ach_id}"
            resp = await client.get(url, headers=headers, params=params)
            if resp.status_code == 200:
                return resp.json()
            return None
        except Exception as e:
            print(f"Error fetching {ach_id}: {e}")
            return None

    tasks = [fetch_one(ach_id) for ach_id in ach_ids]
    return await asyncio.gather(*tasks)


async def fetch_media_batch(client: httpx.AsyncClient, token: str, ach_ids: list) -> dict:
    """Fetch icon URLs for a batch of achievements."""
    headers = {"Authorization": f"Bearer {token}"}
    params = {"namespace": "static-us", "locale": "en_US"}

    async def fetch_icon(ach_id):
        try:
            url = f"{API_BASE}/data/wow/media/achievement/{ach_id}"
            resp = await client.get(url, headers=headers, params=params)
            if resp.status_code == 200:
                data = resp.json()
                assets = data.get("assets", [])
                for asset in assets:
                    if asset.get("key") == "icon":
                        return (ach_id, asset.get("value"))
            return (ach_id, None)
        except Exception:
            return (ach_id, None)

    tasks = [fetch_icon(ach_id) for ach_id in ach_ids]
    results = await asyncio.gather(*tasks)
    return {ach_id: icon_url for ach_id, icon_url in results}


async def build_database(token: str, categories: dict, fetch_icons: bool = True) -> dict:
    """Build complete achievement database."""
    print("Fetching achievement index...")
    ach_ids = await fetch_achievement_index(token)
    print(f"Found {len(ach_ids)} achievements")

    database = {}
    batch_size = 50  # Concurrent requests per batch
    total_batches = (len(ach_ids) + batch_size - 1) // batch_size

    # Use longer timeout for batch operations
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Pass 1: Fetch achievement data
        for i in range(0, len(ach_ids), batch_size):
            batch = ach_ids[i:i + batch_size]
            batch_num = i // batch_size + 1
            print(f"[Pass 1] Fetching achievements {batch_num}/{total_batches}...")

            results = await fetch_achievement_batch(client, token, batch)

            for ach in results:
                if ach:
                    ach_id = ach["id"]
                    cat_info = ach.get("category", {})
                    cat_id = cat_info.get("id")
                    cat_name = cat_info.get("name", categories.get(cat_id, "Unknown"))

                    # Detect special categories
                    is_fos = "Feats of Strength" in cat_name
                    is_legacy = "Legacy" in cat_name or "(Legacy)" in ach.get("name", "")

                    database[str(ach_id)] = {
                        "id": ach_id,
                        "name": ach.get("name", f"Achievement {ach_id}"),
                        "description": ach.get("description", ""),
                        "points": ach.get("points", 0),
                        "category_id": cat_id,
                        "category": cat_name,
                        "is_feat_of_strength": is_fos,
                        "is_legacy": is_legacy,
                        "icon_url": None,
                    }

            await asyncio.sleep(0.1)

        # Pass 2: Fetch icon URLs (optional, doubles API calls)
        if fetch_icons:
            print(f"\n[Pass 2] Fetching {len(ach_ids)} icon URLs...")
            for i in range(0, len(ach_ids), batch_size):
                batch = ach_ids[i:i + batch_size]
                batch_num = i // batch_size + 1
                print(f"[Pass 2] Fetching icons {batch_num}/{total_batches}...")

                icon_map = await fetch_media_batch(client, token, batch)
                for ach_id, icon_url in icon_map.items():
                    if icon_url and str(ach_id) in database:
                        database[str(ach_id)]["icon_url"] = icon_url

                await asyncio.sleep(0.1)

    return database


async def main():
    client_id = os.environ.get("BATTLENET_CLIENT_ID")
    client_secret = os.environ.get("BATTLENET_CLIENT_SECRET")

    if not client_id or not client_secret:
        print("ERROR: Set BATTLENET_CLIENT_ID and BATTLENET_CLIENT_SECRET")
        return

    print(f"Starting WoW achievement database build at {datetime.now()}")

    token = await get_access_token(client_id, client_secret)
    print("Got access token")

    categories = await fetch_achievement_categories(token)
    print(f"Loaded {len(categories)} categories")

    database = await build_database(token, categories)
    print(f"\nBuilt database with {len(database)} achievements")

    # Analyze point distribution
    points_dist = {}
    for ach in database.values():
        pts = ach["points"]
        points_dist[pts] = points_dist.get(pts, 0) + 1

    print("\nPoint distribution:")
    for pts in sorted(points_dist.keys()):
        print(f"  {pts} points: {points_dist[pts]} achievements")

    # Count special achievements
    fos_count = sum(1 for a in database.values() if a["is_feat_of_strength"])
    legacy_count = sum(1 for a in database.values() if a["is_legacy"])
    print(f"\nFeats of Strength: {fos_count}")
    print(f"Legacy: {legacy_count}")

    # Save to app/data directory
    os.makedirs("app/data", exist_ok=True)
    output_path = "app/data/wow_achievements.json"

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({
            "version": "11.2.7",
            "generated": datetime.now().isoformat(),
            "count": len(database),
            "achievements": database
        }, f, indent=2)

    print(f"\nSaved to {output_path}")
    print(f"Finished at {datetime.now()}")


if __name__ == "__main__":
    asyncio.run(main())
