from app.database import SessionLocal
from app.models import WalletAccount

db = SessionLocal()
wallets = db.query(WalletAccount).all()

print("Wallet Accounts in database:")
for w in wallets:
    print(f"  ID: {w.id}, User ID: {w.user_id}, Address: {w.wallet_address}, Chain: {w.chain_id}")

if not wallets:
    print("  (none)")

db.close()
