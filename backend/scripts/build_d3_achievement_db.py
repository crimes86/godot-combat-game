"""
One-time script to build a Diablo 3 achievement database.

Fetches all D3 achievements from Blizzard API and saves them as a static JSON lookup.

Output: app/data/d3_achievements.json
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


async def fetch_d3_achievements(token: str) -> dict:
    """Fetch all D3 achievements from the data API."""
    headers = {"Authorization": f"Bearer {token}"}

    # Try the EU region data API (sometimes has different availability)
    regions = ["us", "eu"]
    for region in regions:
        url = f"https://{region}.api.blizzard.com/d3/data/achievements"
        print(f"Trying {url}...")

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                print(f"Success with {region} region!")
                return resp.json()
            print(f"  {region}: {resp.status_code}")

    # If data API fails, we can still sync achievements from user profiles
    # The achievements will be discovered during sync
    print("\nNote: D3 data API not available. Achievements will be discovered during user sync.")
    return {"categories": []}


def extract_achievements(data: dict) -> dict:
    """Extract all achievements from nested categories."""
    database = {}

    def process_category(cat, parent_name=""):
        cat_name = cat.get("name", "Unknown")
        full_cat = f"{parent_name} > {cat_name}" if parent_name else cat_name

        # Process achievements in this category
        for ach in cat.get("achievements", []):
            ach_id = str(ach.get("id"))
            database[ach_id] = {
                "id": ach.get("id"),
                "name": ach.get("name", f"Achievement {ach_id}"),
                "description": ach.get("description", ""),
                "points": ach.get("points", 10),
                "category": full_cat,
                "icon_url": None,  # D3 doesn't provide icons in this endpoint
            }

        # Recurse into subcategories
        for subcat in cat.get("subcategories", []):
            process_category(subcat, full_cat)

    # Process root categories
    for cat in data.get("categories", []):
        process_category(cat)

    return database


async def main():
    client_id = os.environ.get("BATTLENET_CLIENT_ID")
    client_secret = os.environ.get("BATTLENET_CLIENT_SECRET")

    if not client_id or not client_secret:
        print("ERROR: Set BATTLENET_CLIENT_ID and BATTLENET_CLIENT_SECRET")
        return

    print(f"Starting D3 achievement database build at {datetime.now()}")

    token = await get_access_token(client_id, client_secret)
    print("Got access token")

    data = await fetch_d3_achievements(token)
    print(f"Fetched D3 achievement data")

    database = extract_achievements(data)
    print(f"Extracted {len(database)} achievements")

    # Analyze point distribution
    points_dist = {}
    for ach in database.values():
        pts = ach["points"]
        points_dist[pts] = points_dist.get(pts, 0) + 1

    print("\nPoint distribution:")
    for pts in sorted(points_dist.keys()):
        print(f"  {pts} points: {points_dist[pts]} achievements")

    # Save to app/data directory
    os.makedirs("app/data", exist_ok=True)
    output_path = "app/data/d3_achievements.json"

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({
            "version": "1.0",
            "generated": datetime.now().isoformat(),
            "count": len(database),
            "achievements": database
        }, f, indent=2)

    print(f"\nSaved to {output_path}")
    print(f"Finished at {datetime.now()}")


if __name__ == "__main__":
    asyncio.run(main())
