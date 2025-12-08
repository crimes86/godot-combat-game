"""
Script to fetch all WoW achievements from Blizzard API and build a lookup table.

This fetches the bulk achievement data including points and categories,
which we can use to properly score Battle.net achievements.
"""

import httpx
import json
import os
from datetime import datetime

# Blizzard OAuth endpoints
TOKEN_URL = "https://oauth.battle.net/token"
API_BASE = "https://us.api.blizzard.com"

async def get_access_token(client_id: str, client_secret: str) -> str:
    """Get OAuth access token from Blizzard."""
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            TOKEN_URL,
            data={"grant_type": "client_credentials"},
            auth=(client_id, client_secret)
        )
        resp.raise_for_status()
        return resp.json()["access_token"]


async def fetch_all_achievements(token: str) -> dict:
    """Fetch all character achievements from Blizzard API."""
    headers = {"Authorization": f"Bearer {token}"}

    # Try the legacy endpoint first
    url = f"{API_BASE}/wow/data/character/achievements"
    params = {"locale": "en_US"}

    async with httpx.AsyncClient() as client:
        print(f"Fetching from: {url}")
        resp = await client.get(url, headers=headers, params=params)

        if resp.status_code != 200:
            print(f"Legacy endpoint failed: {resp.status_code}")
            print(resp.text[:500])

            # Try the newer Game Data API endpoint
            url = f"{API_BASE}/data/wow/achievement/index"
            params = {"namespace": "static-us", "locale": "en_US"}
            print(f"Trying Game Data API: {url}")
            resp = await client.get(url, headers=headers, params=params)

            if resp.status_code != 200:
                print(f"Game Data API also failed: {resp.status_code}")
                print(resp.text[:500])
                return None

        return resp.json()


async def fetch_achievement_categories(token: str) -> dict:
    """Fetch achievement category index."""
    headers = {"Authorization": f"Bearer {token}"}
    url = f"{API_BASE}/data/wow/achievement-category/index"
    params = {"namespace": "static-us", "locale": "en_US"}

    async with httpx.AsyncClient() as client:
        print(f"Fetching categories from: {url}")
        resp = await client.get(url, headers=headers, params=params)
        if resp.status_code == 200:
            return resp.json()
        print(f"Categories failed: {resp.status_code}")
        return None


async def fetch_single_achievement(token: str, ach_id: int) -> dict:
    """Fetch a single achievement's details."""
    headers = {"Authorization": f"Bearer {token}"}
    url = f"{API_BASE}/data/wow/achievement/{ach_id}"
    params = {"namespace": "static-us", "locale": "en_US"}

    async with httpx.AsyncClient() as client:
        resp = await client.get(url, headers=headers, params=params)
        if resp.status_code == 200:
            return resp.json()
        return None


def build_achievement_lookup(data: dict) -> dict:
    """Build a lookup table from achievement data."""
    lookup = {}

    def process_category(category, parent_name=""):
        """Recursively process achievement categories."""
        cat_name = category.get("name", "Unknown")
        full_cat_name = f"{parent_name} > {cat_name}" if parent_name else cat_name

        # Process achievements in this category
        for ach in category.get("achievements", []):
            ach_id = ach.get("id")
            if ach_id:
                lookup[ach_id] = {
                    "id": ach_id,
                    "name": ach.get("title", ach.get("name", f"Achievement {ach_id}")),
                    "points": ach.get("points", 10),
                    "category": full_cat_name,
                    "description": ach.get("description", ""),
                    "is_feat_of_strength": "Feats of Strength" in full_cat_name,
                    "is_legacy": "Legacy" in full_cat_name or "Removed" in full_cat_name,
                }

        # Process subcategories
        for subcat in category.get("categories", []):
            process_category(subcat, full_cat_name)

    # Handle different response formats
    if "achievements" in data:
        # Direct list of achievements
        for ach in data["achievements"]:
            ach_id = ach.get("id")
            if ach_id:
                lookup[ach_id] = {
                    "id": ach_id,
                    "name": ach.get("name", f"Achievement {ach_id}"),
                    "points": ach.get("points", 10),
                    "category": "",
                    "description": "",
                }
    elif "categories" in data:
        # Nested category structure
        for category in data["categories"]:
            process_category(category)

    return lookup


async def main():
    # Load credentials from environment
    client_id = os.environ.get("BATTLENET_CLIENT_ID")
    client_secret = os.environ.get("BATTLENET_CLIENT_SECRET")

    if not client_id or not client_secret:
        print("ERROR: Set BATTLENET_CLIENT_ID and BATTLENET_CLIENT_SECRET environment variables")
        return

    print("Getting access token...")
    token = await get_access_token(client_id, client_secret)
    print(f"Got token: {token[:20]}...")

    print("\nFetching all achievements...")
    data = await fetch_all_achievements(token)

    if data:
        # Save raw response for inspection
        with open("wow_achievements_raw.json", "w") as f:
            json.dump(data, f, indent=2)
        print(f"Saved raw data to wow_achievements_raw.json")
        print(f"Response keys: {list(data.keys())}")

        # Build lookup table
        lookup = build_achievement_lookup(data)
        print(f"Built lookup with {len(lookup)} achievements")

        # Save lookup table
        with open("wow_achievements_lookup.json", "w") as f:
            json.dump(lookup, f, indent=2)
        print(f"Saved lookup to wow_achievements_lookup.json")

        # Show some samples
        print("\nSample achievements:")
        for i, (ach_id, ach) in enumerate(list(lookup.items())[:5]):
            print(f"  {ach_id}: {ach['name']} ({ach['points']} pts) - {ach['category']}")
    else:
        print("Failed to fetch achievements")

    # Also try fetching categories
    print("\nFetching achievement categories...")
    categories = await fetch_achievement_categories(token)
    if categories:
        with open("wow_categories_raw.json", "w") as f:
            json.dump(categories, f, indent=2)
        print(f"Saved categories to wow_categories_raw.json")
        print(f"Categories keys: {list(categories.keys())}")

    # Try fetching a single known achievement for comparison
    print("\nFetching single achievement (ID 6)...")
    single = await fetch_single_achievement(token, 6)  # Level 10 achievement
    if single:
        print(f"Single achievement response: {json.dumps(single, indent=2)[:500]}")


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
