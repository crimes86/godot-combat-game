"""
Icon caching proxy for achievement icons.
Caches external achievement icons locally to improve loading performance.
"""
import hashlib
import os
import logging
from pathlib import Path
from typing import Optional

import httpx
from fastapi import APIRouter, Query, Response
from fastapi.responses import FileResponse, RedirectResponse

logger = logging.getLogger(__name__)

router = APIRouter()

# Cache directory for achievement icons
ICON_CACHE_DIR = Path("static/achievement_icons")
ICON_CACHE_DIR.mkdir(parents=True, exist_ok=True)

# HTTP client for fetching icons
http_client = httpx.AsyncClient(timeout=10.0, follow_redirects=True)


def get_cache_filename(url: str) -> str:
    """
    Generate a cache filename from the icon URL.
    Uses SHA256 hash of URL to avoid filesystem issues with special characters.
    """
    url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]

    # Try to preserve file extension
    ext = ".png"  # Default extension
    if "?" in url:
        path_part = url.split("?")[0]
    else:
        path_part = url

    if path_part.endswith((".jpg", ".jpeg")):
        ext = ".jpg"
    elif path_part.endswith(".gif"):
        ext = ".gif"
    elif path_part.endswith(".webp"):
        ext = ".webp"

    return f"{url_hash}{ext}"


async def download_and_cache_icon(url: str, cache_path: Path) -> bool:
    """
    Download an icon from external URL and cache it locally.
    Returns True if successful, False otherwise.
    """
    try:
        logger.info(f"[IconCache] Downloading icon from {url}")
        response = await http_client.get(url)
        response.raise_for_status()

        # Save to cache
        cache_path.write_bytes(response.content)
        logger.info(f"[IconCache] Cached icon to {cache_path}")
        return True

    except Exception as e:
        logger.error(f"[IconCache] Failed to download icon from {url}: {e}")
        return False


@router.get("/icon")
async def get_cached_icon(
    url: str = Query(..., description="External icon URL to proxy/cache"),
    fallback: bool = Query(True, description="Redirect to original URL if cache fails")
):
    """
    Proxy endpoint for achievement icons with local caching.

    Flow:
    1. Check if icon is already cached locally
    2. If cached, serve from local cache with long cache headers
    3. If not cached, download and cache it, then serve
    4. If download fails and fallback=true, redirect to original URL
    """
    if not url:
        return Response(status_code=400, content="Missing 'url' parameter")

    # Skip caching for placeholder/default icons
    if "placeholder" in url.lower() or url.startswith("data:"):
        if fallback:
            return RedirectResponse(url=url, status_code=302)
        return Response(status_code=404, content="Placeholder icons not cached")

    # Generate cache filename
    cache_filename = get_cache_filename(url)
    cache_path = ICON_CACHE_DIR / cache_filename

    # Check if already cached
    if cache_path.exists():
        logger.debug(f"[IconCache] Serving cached icon for {url}")
        return FileResponse(
            cache_path,
            media_type="image/png",
            headers={
                "Cache-Control": "public, max-age=2592000",  # 30 days
                "ETag": cache_filename,
            }
        )

    # Not cached - download it
    success = await download_and_cache_icon(url, cache_path)

    if success and cache_path.exists():
        return FileResponse(
            cache_path,
            media_type="image/png",
            headers={
                "Cache-Control": "public, max-age=2592000",  # 30 days
                "ETag": cache_filename,
            }
        )

    # Download failed - fall back to original URL if enabled
    if fallback:
        logger.warning(f"[IconCache] Cache failed, redirecting to original URL: {url}")
        return RedirectResponse(url=url, status_code=302)

    return Response(status_code=404, content="Icon not found and caching failed")


@router.delete("/icon/clear-cache")
async def clear_icon_cache():
    """
    Clear all cached achievement icons.
    Admin endpoint for cache management.
    """
    try:
        count = 0
        for cache_file in ICON_CACHE_DIR.glob("*"):
            if cache_file.is_file():
                cache_file.unlink()
                count += 1

        logger.info(f"[IconCache] Cleared {count} cached icons")
        return {"status": "success", "cleared": count}

    except Exception as e:
        logger.error(f"[IconCache] Failed to clear cache: {e}")
        return {"status": "error", "message": str(e)}
