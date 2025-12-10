"""Reset bridge cooldown for testing - makes pending bridge-outs immediately confirmable."""
from datetime import datetime, timedelta
from app.database import SessionLocal
from app.models import ForgedAchievement, BridgeStatus

db = SessionLocal()

# Find all items in bridging_out status
bridging = db.query(ForgedAchievement).filter(
    ForgedAchievement.bridge_status == BridgeStatus.BRIDGING_OUT.value
).all()

print(f"Found {len(bridging)} items in bridging_out status")

for item in bridging:
    old_time = item.bridge_requested_at
    # Set bridge_requested_at to 1 hour ago so cooldown is expired
    item.bridge_requested_at = datetime.utcnow() - timedelta(hours=1)
    print(f"  {item.item_name}: {old_time} -> {item.bridge_requested_at}")

db.commit()
print("Done! Cooldowns reset. Items should now be confirmable.")
db.close()
