"""
Vendor Service - Server-side item catalog for purchase validation.

Loads shop data from JSON files and provides lookup methods.
This is the source of truth for item prices and stats.
"""
import json
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Note: Free items (price=0) should stay free
# Previously had DEFAULT_TEST_PRICE = 5 which broke free items


class VendorService:
    """
    Manages item catalogs for vendor purchases.

    Catalogs are loaded once at startup and cached.
    Items are keyed by their ID for O(1) lookup.
    """

    def __init__(self):
        self.catalogs: dict[str, dict[str, dict]] = {}
        self._loaded = False

    def _load_catalogs(self):
        """Load shop data from JSON files."""
        if self._loaded:
            return

        # Data files are in the root data folder (not backend/data)
        data_dir = Path(__file__).parent.parent.parent.parent / "data"

        # Weapons
        weapons_path = data_dir / "shop_weapons.json"
        if weapons_path.exists():
            with open(weapons_path) as f:
                data = json.load(f)
                self.catalogs["weapons"] = {
                    item["id"]: item for item in data.get("weapons", [])
                }
            logger.info(f"Loaded {len(self.catalogs['weapons'])} weapons")
        else:
            logger.warning(f"shop_weapons.json not found at {weapons_path}")
            self.catalogs["weapons"] = {}

        # Armor
        armor_path = data_dir / "shop_armor.json"
        if armor_path.exists():
            with open(armor_path) as f:
                data = json.load(f)
                self.catalogs["armor"] = {
                    item["id"]: item for item in data.get("armor", [])
                }
            logger.info(f"Loaded {len(self.catalogs['armor'])} armor pieces")
        else:
            logger.warning(f"shop_armor.json not found at {armor_path}")
            self.catalogs["armor"] = {}

        # Misc items
        misc_path = data_dir / "shop_misc.json"
        if misc_path.exists():
            with open(misc_path) as f:
                data = json.load(f)
                self.catalogs["misc"] = {
                    item["id"]: item for item in data.get("items", [])
                }
            logger.info(f"Loaded {len(self.catalogs['misc'])} misc items")
        else:
            logger.warning(f"shop_misc.json not found at {misc_path}")
            self.catalogs["misc"] = {}

        # Tools (if exists)
        tools_path = data_dir / "shop_tools.json"
        if tools_path.exists():
            with open(tools_path) as f:
                data = json.load(f)
                self.catalogs["tools"] = {
                    item["id"]: item for item in data.get("tools", [])
                }
            logger.info(f"Loaded {len(self.catalogs['tools'])} tools")
        else:
            # Tools catalog is optional
            self.catalogs["tools"] = {}

        self._loaded = True
        total = sum(len(c) for c in self.catalogs.values())
        logger.info(f"VendorService loaded {total} total items across {len(self.catalogs)} catalogs")

    def ensure_loaded(self):
        """Ensure catalogs are loaded. Called lazily on first access."""
        if not self._loaded:
            self._load_catalogs()

    def get_item(self, vendor_type: str, item_id: str) -> Optional[dict]:
        """
        Get item from catalog.

        Args:
            vendor_type: One of "weapons", "armor", "misc", "tools"
            item_id: The item's ID

        Returns:
            Item dict if found, None otherwise
        """
        self.ensure_loaded()
        return self.catalogs.get(vendor_type, {}).get(item_id)

    def get_price(self, vendor_type: str, item_id: str) -> Optional[int]:
        """
        Get item price.

        Args:
            vendor_type: One of "weapons", "armor", "misc", "tools"
            item_id: The item's ID

        Returns:
            Item price (uses DEFAULT_TEST_PRICE if price is 0), None if item not found
        """
        item = self.get_item(vendor_type, item_id)
        if item is None:
            return None

        # Return actual price from JSON (free items stay free)
        return item.get("price", 0)

    def get_valid_vendor_types(self) -> list[str]:
        """Get list of valid vendor types."""
        return ["weapons", "armor", "misc", "tools"]

    def get_catalog(self, vendor_type: str) -> dict[str, dict]:
        """Get entire catalog for a vendor type."""
        self.ensure_loaded()
        return self.catalogs.get(vendor_type, {})


# Singleton instance
vendor_service = VendorService()
