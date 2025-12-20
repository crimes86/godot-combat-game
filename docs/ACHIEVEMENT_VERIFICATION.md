# Achievement Verification & Token Integrity

This document describes how Ashbane verifies gaming achievements and ensures that forged tokens are unique, authentic, and non-duplicatable.

> **This is the authoritative reference for Ashbane's anti-exploit and integrity systems.**
> Reference this document for any questions about duplicate prevention or token authenticity.

---

## Overview

Ashbane aggregates achievements from gaming platforms (Steam, Battle.net, etc.) and allows users to "forge" rare achievements into tradeable tokens. The system guarantees:

1. **Authenticity** - Only actually-earned achievements can be forged
2. **Uniqueness** - Each achievement can only be forged once globally
3. **Provenance** - The original earner is permanently recorded on-chain
4. **Anti-Exploit** - Unlinking/relinking accounts cannot generate duplicate credits

---

## Data Model

### Core Entities

```
User
├── id (primary key)
├── username (auto-generated: "Ashbane-{uuid}")
├── is_admin (bypass sync cooldowns for testing)
└── Relationships:
    ├── provider_accounts[] (Steam, Battle.net, etc.)
    ├── achievement_credits[] (earned achievements)
    └── wallet_accounts[] (linked crypto wallets)

ProviderAccount
├── id (primary key)
├── user_id (FK → User)
├── provider_name ("steam", "battlenet", etc.)
├── provider_user_id (Steam ID, Battle.net ID, etc.)
├── access_token (for API calls)
├── is_active (soft-delete flag)
├── unclaimed_at (timestamp when unlinked)
├── last_sync_at (for 15-min sync cooldown)
└── UNIQUE(provider_name, provider_user_id)

Achievement
├── id (primary key)
├── app_id (game identifier)
├── api_name (achievement identifier within game)
├── display_name, description, icon_url
├── percent (global unlock percentage)
├── effort_score (0-100, normalized difficulty)          ← CROSS-PLATFORM
├── effort_auto (True = auto-calculated, False = admin override)
├── effort_notes (admin notes for manual overrides)
├── rarity_tier (Common → Legendary, computed from effort_score)
└── UNIQUE(app_id, api_name)

AchievementCredit
├── id (primary key)
├── user_id (FK → User)
├── provider_account_id (FK → ProviderAccount)
├── achievement_id (FK → Achievement)
├── provider_name (denormalized for global tracking)      ← ANTI-EXPLOIT
├── provider_user_id (denormalized for global tracking)  ← ANTI-EXPLOIT
├── is_original_claim (True = counts, False = display only) ← ANTI-EXPLOIT
├── character_name, realm_slug (for WoW multi-character)
├── date_credited
└── UNIQUE(provider_name, provider_user_id, achievement_id, character_name, realm_slug)

ForgedAchievement
├── id (primary key)
├── achievement_credit_id (FK → AchievementCredit, UNIQUE)
├── wallet_account_id (FK → WalletAccount)
├── token_id (on-chain NFT token ID)
├── contract_address
├── chain_id
├── tx_hash
└── forged_at
```

---

## Verification Flow

### 1. Provider Authentication (OAuth)

```
User clicks "Login with Steam"
       ↓
Redirected to Steam's OAuth
       ↓
Steam authenticates user
       ↓
Callback returns with Steam ID (cryptographically verified)
       ↓
ProviderAccount created/updated with verified Steam ID
```

**Security**: Steam ID comes directly from Steam's OAuth response. We never trust client-provided IDs.

### 2. Achievement Sync (with Global Claim Tracking)

```
User triggers achievement sync
       ↓
Backend calls Steam/Battle.net API with user's access token
       ↓
API returns list of achievements with unlock status
       ↓
For each UNLOCKED achievement:
       ↓
Check: Does GLOBAL claim exist? (provider_name + provider_user_id + achievement_id)
  → Yes, same provider_account: Skip (already credited)
  → Yes, different provider_account: Update to new owner, set is_original_claim=FALSE
  → No: Create new AchievementCredit with is_original_claim=TRUE
```

**Security**:
- Achievements come directly from provider APIs, not user input
- Only unlocked achievements are credited
- **Global claim tracking prevents re-crediting after unlink/relink**
- Reclaimed achievements are display-only (don't count toward Ashbane score)

### 3. Forge Request

```
User selects achievements to forge
       ↓
Backend verifies:
  1. User owns the AchievementCredit
  2. is_original_claim == TRUE (not a reclaimed achievement)
  3. AchievementCredit hasn't been forged (no ForgedAchievement record)
  4. User has linked wallet
       ↓
Backend calls smart contract to mint
       ↓
Contract verifies:
  5. Achievement hasn't been minted to this wallet before
       ↓
Token minted, ForgedAchievement record created
```

---

## Duplicate Prevention (6 Layers)

### Layer 1: Provider Account Uniqueness

```sql
UNIQUE CONSTRAINT: (provider_name, provider_user_id)
```

- One Steam account = one ProviderAccount record
- Cannot link same Steam account to multiple Ashbane users simultaneously
- Prevents: Same person having two active links to same Steam

### Layer 2: Achievement Uniqueness

```sql
UNIQUE CONSTRAINT: (app_id, api_name)
```

- Each achievement exists once in the database
- "TF2 Hat" achievement has one canonical record
- Prevents: Duplicate achievement definitions

### Layer 3: Achievement Credit Uniqueness (LOCAL)

```sql
-- OLD: Only prevented duplicates within same provider_account
UNIQUE CONSTRAINT: (provider_account_id, achievement_id, character_name, realm_slug)
```

- Each provider account can only be credited once per achievement
- WoW characters are tracked separately
- **Limitation**: Did NOT prevent exploit via unlink/relink

### Layer 4: Global Claim Tracking (ANTI-EXPLOIT)

```sql
-- NEW: Prevents duplicates across ALL provider_account instances
UNIQUE CONSTRAINT: (provider_name, provider_user_id, achievement_id, character_name, realm_slug)

-- Additional tracking fields
provider_name VARCHAR     -- Denormalized from provider_account
provider_user_id VARCHAR  -- Denormalized from provider_account
is_original_claim BOOLEAN -- TRUE = first claim, FALSE = reclaimed (display only)
```

**This is the critical anti-exploit layer.** It tracks claims by the permanent provider identity (e.g., Steam ID "76561197963990204"), not by the ephemeral provider_account row ID.

| Scenario | is_original_claim | Counts in Ashbane | Can Forge |
|----------|-------------------|------------------|-----------|
| First sync of Steam ID | TRUE | YES | YES |
| Unlink, relink same Steam | FALSE | NO | NO |
| Different user links orphaned Steam | FALSE | NO | NO |

**Prevents:**
- User unlinks provider, creates new account, re-syncs same achievements
- User orphans provider account, logs in fresh to generate new credits
- Any attempt to "reset" achievement history by cycling accounts

### Layer 5: Forge Record Uniqueness

```sql
UNIQUE CONSTRAINT: achievement_credit_id (one forge per credit)
```

- Each AchievementCredit can only be forged once
- Prevents: Forging same achievement credit multiple times

### Layer 6: Smart Contract Uniqueness

```solidity
mapping(bytes32 => bool) public alreadyMinted;

function mintAchievement(...) {
    bytes32 mintHash = keccak256(abi.encodePacked(wallet, achievementId));
    require(!alreadyMinted[mintHash], "Already minted");
    alreadyMinted[mintHash] = true;
    // ... mint token
}
```

- On-chain verification independent of database
- Even if database is compromised, contract rejects duplicates
- Prevents: Any bypass of database checks

---

## The Orphan/Relink Exploit (Patched)

### The Attack Vector

```
BEFORE PATCH:

1. User A links Steam ID "12345", syncs 500 achievements
2. User A has 500 AchievementCredits, can forge Legendaries
3. User A unlinks Steam (orphans the provider_account)
4. User A logs in with Steam again → creates NEW provider_account
5. User A syncs → 500 NEW AchievementCredits created (different provider_account_id)
6. User A now has 1000 credits, can forge duplicates!

EXPLOIT: Repeat to generate infinite achievement credits
```

### The Fix (Global Claim Tracking)

```
AFTER PATCH:

1. User A links Steam ID "12345", syncs 500 achievements
   → AchievementCredit created with:
     - provider_name = "steam"
     - provider_user_id = "12345"
     - is_original_claim = TRUE

2. User A unlinks Steam

3. User A logs in with Steam again → creates NEW provider_account (id=2)

4. User A syncs → For EACH achievement:
   → Check: Global claim exists for (steam, 12345, achievement)?
   → YES! Update existing credit:
     - provider_account_id = 2 (new)
     - user_id = new user
     - is_original_claim = FALSE (not first claim!)

5. User A has 500 credits, but ALL are is_original_claim=FALSE
   → Ashbane score: 0 (only original claims count)
   → Forgeable: 0 (only original claims can forge)
   → Display: Shows on provider card for reference only
```

---

## Account Merging

When users have multiple Ashbane accounts, they can merge accounts.

### Merge Process

```
User A (current): Has Steam linked
User B (other):   Has Battle.net linked

MERGE CHECKS:
1. No provider conflicts (both can't have Steam)
2. Both accounts exist

MERGE ACTIONS:
1. Transfer ProviderAccounts: B → A
2. Transfer AchievementCredits: B → A
3. Transfer UserAchievements: B → A
4. Transfer WalletAccounts: B → A
5. Delete User B
```

### Why Duplicates Don't Occur

```
Scenario: Both users have Steam

BLOCKED: "Cannot merge: both have Steam linked"
         User must unclaim one Steam first

Scenario: Different providers (allowed)

User A: Steam (ProviderAccount #1) → Credits via PA #1
User B: BNet (ProviderAccount #2)  → Credits via PA #2

After merge:
User A: PA #1 (Steam credits) + PA #2 (BNet credits)

No duplicates because:
- Different provider_name + provider_user_id combinations
- Global uniqueness constraint prevents any overlap
```

---

## Token Authenticity Guarantees

### What a Forged Token Proves

1. **Achievement was earned** - Verified via provider API at sync time
2. **Earner owned the account** - OAuth authentication verified identity
3. **First-time claim** - is_original_claim=TRUE enforced at forge time
4. **One-time forge** - Database + smart contract prevent duplicates
5. **Original earner recorded** - On-chain `originalEarner` field is immutable

### What's Stored On-Chain

```solidity
struct AchievementData {
    address originalEarner;     // Wallet that forged it (earned it)
    string achievementId;       // "steam_440_tf2_hat"
    string provider;            // "steam"
    uint256 mintedAt;           // Block timestamp
    string rarityTier;          // "Legendary"
}
```

### Metadata API

Each token points to a metadata URI that returns:

```json
{
  "name": "Team Fortress 2 - Golden Wrench",
  "description": "Verified gaming achievement from steam.",
  "image": "https://steamcdn.../golden_wrench.png",
  "attributes": [
    {"trait_type": "Rarity", "value": "Legendary"},
    {"trait_type": "Provider", "value": "steam"},
    {"trait_type": "Global Unlock %", "value": 0.01},
    {"trait_type": "Game ID", "value": "440"}
  ]
}
```

---

## Attack Vectors & Mitigations

| Attack | Mitigation | Layer |
|--------|------------|-------|
| Fake achievement injection | Achievements only from provider APIs | Sync verification |
| Forge same achievement twice | 6 layers of uniqueness checks | Layers 1-6 |
| Steal someone else's achievement | OAuth verifies account ownership | Layer 1 |
| Create fake provider account | Provider IDs from OAuth, not user-supplied | Layer 1 |
| Forge then re-sync to get another | ForgedAchievement record blocks re-forging | Layer 5 |
| **Unlink/relink to duplicate** | **Global claim tracking (provider_name + provider_user_id)** | **Layer 4** |
| **Orphan account, create fresh** | **is_original_claim=FALSE on reclaim** | **Layer 4** |
| Merge accounts to duplicate | Conflict check blocks if same provider | Merge logic |
| Database tampering | Smart contract has independent check | Layer 6 |
| Re-link provider to new user | Reclaimed credits are display-only | Layer 4 |

---

## Ashbane Score Calculation

Only **original claims** count toward a user's Ashbane score:

```python
total_achievements = (
    db.query(AchievementCredit)
    .filter(
        AchievementCredit.user_id == user.id,
        AchievementCredit.is_original_claim == True  # CRITICAL
    )
    .count()
)
```

**Display behavior:**
- Provider card: Shows ALL achievements (including reclaimed) for reference
- Ashbane card: Only shows original claims in totals
- API `/api/achievements`: Returns `is_original_claim` flag for each achievement
- Forge UI: Only shows achievements where `is_original_claim=TRUE`

**UI Terminology:**
- **Ashbane** badge (cyan): Achievement counts toward Ashbane score
- **Consumed** badge (orange): Achievement was already claimed by another user

---

## Sync Cooldown

To prevent API abuse and rate limiting from providers:

```python
SYNC_COOLDOWN_MINUTES = 15

# Check cooldown (admin users bypass)
if not user.is_admin:
    if provider_account.last_sync_at:
        cooldown_end = provider_account.last_sync_at + timedelta(minutes=15)
        if datetime.utcnow() < cooldown_end:
            raise HTTPException(status_code=429, detail="Sync cooldown active...")

# Update after successful sync
provider_account.last_sync_at = datetime.utcnow()
```

**Features:**
- 15-minute cooldown between syncs per provider
- Admin users bypass cooldown (for testing)
- UI shows countdown timer on sync button
- Returns 429 status code when on cooldown

---

## Reclaim Confirmation Flow

When a user tries to claim a provider that was previously linked to another user:

```
User B logs in with Steam account that User A previously unlinked
                    ↓
System detects: ProviderAccount exists, is_active=False, user_id != current_user
                    ↓
Show reclaim confirmation page:
  - Warning: "This account was linked to {other_username}"
  - "Already synced achievements are CONSUMED"
  - "NEW achievements you earn will count"
                    ↓
User confirms claim
                    ↓
Provider is transferred:
  - provider_account.user_id = new_user.id
  - provider_account.is_active = True
  - provider_account.unclaimed_at = None
                    ↓
When user syncs:
  - Existing achievements: is_original_claim = FALSE (display only)
  - New achievements: is_original_claim = TRUE (full credit)

---

## Effort Scoring System

### The Problem

Different platforms measure achievement difficulty differently:
- **Steam/Xbox/PlayStation**: Global unlock percentage (0.1% - 100%)
- **WoW (Battle.net)**: Point values (10/30/50) + Feat of Strength flag
- **GitHub**: Tiered badges (bronze/silver/gold)
- **Reddit**: Trophy rarity (some unobtainable)

A 1-hour achievement in WoW should feel equivalent to a 1-hour achievement in CS2.

### The Solution: Normalized Effort Score (0-100)

All achievements are converted to a unified `effort_score` that determines rarity tier:

```
effort_score    rarity_tier    Forgeable
─────────────────────────────────────────
80-100          Legendary      Yes
60-79           Epic           Yes
40-59           Rare           Yes
20-39           Uncommon       No
0-19            Common         No
```

### Provider-Specific Formulas

**Implementation:** `app/services/effort_scoring.py`

#### Steam / Xbox / PlayStation (percentage-based)

```python
effort_score = 100 - global_percent

# Examples:
# 2% unlock rate  → effort = 98 → Legendary
# 15% unlock rate → effort = 85 → Legendary
# 35% unlock rate → effort = 65 → Epic
# 60% unlock rate → effort = 40 → Rare
# 85% unlock rate → effort = 15 → Common
```

#### Battle.net (WoW)

```python
if is_feat_of_strength: effort = 90  # Legendary
elif is_legacy_removed: effort = 95  # Legendary (unobtainable)
elif points >= 50:      effort = 70  # Epic
elif points >= 30:      effort = 50  # Rare
elif points >= 10:      effort = 30  # Uncommon
else:                   effort = 15  # Common
```

#### Xbox (Gamerscore fallback)

```python
# Use global % if available, otherwise fall back to Gamerscore
if gamerscore >= 100: effort = 80  # Legendary
elif gamerscore >= 50: effort = 60  # Epic
elif gamerscore >= 25: effort = 40  # Rare
elif gamerscore >= 10: effort = 20  # Uncommon
else:                  effort = 10  # Common
```

#### PlayStation (trophy grade fallback)

```python
# Use global % if available, otherwise fall back to trophy type
if trophy_type == "platinum": effort = 95  # Legendary
elif trophy_type == "gold":   effort = 60  # Epic
elif trophy_type == "silver": effort = 40  # Rare
elif trophy_type == "bronze": effort = 20  # Uncommon
```

### Admin Override

Achievements have three effort-related fields:

| Field | Purpose |
|-------|---------|
| `effort_score` | The 0-100 normalized difficulty |
| `effort_auto` | True = auto-calculated, False = manually set |
| `effort_notes` | Admin notes explaining manual override |

When `effort_auto=False`, syncs won't overwrite the score. This allows admins to:
- Boost achievements harder than their % suggests (bot-inflated games)
- Lower achievements easier than their % suggests (new games with few players)
- Mark legacy/unobtainable achievements as Legendary

### Rarity Tier Computation

`rarity_tier` is now **computed from effort_score**, not stored independently:

```python
def compute_rarity_from_effort(effort_score: float) -> str:
    if effort_score >= 80: return "Legendary"
    if effort_score >= 60: return "Epic"
    if effort_score >= 40: return "Rare"
    if effort_score >= 20: return "Uncommon"
    return "Common"
```

### Forging Rules

Only achievements with:
- `effort_score >= 40` (Rare or better)
- `is_original_claim = True`

can be forged into NFTs.

---

## Summary

The Ashbane achievement system provides cryptographic proof that:

1. A specific gaming achievement was unlocked
2. By a verified account owner
3. **For the first time** (not reclaimed after orphaning)
4. On a specific date
5. And can only be tokenized once

This creates genuine digital scarcity backed by verifiable gaming history, with robust protection against account manipulation exploits.

---

## Trading & Provenance

Forged items are **fully tradeable** in-game. After forging:

- Items can be traded via direct trade or marketplace
- 5% gold tax applies to trades (gold sink)
- 24-hour cooldown after acquisition before can trade again
- **Provenance is tracked**: trade count, ownership chain, original forger
- Blockchain is updated (batched) but users never see crypto complexity

**Key principle:** The `is_original_claim` check happens at **forge time**, not trade time. Once forged, the item exists and can be traded freely. The original forger is permanently recorded in provenance.

See:
- `docs/FORGE_ECONOMY_DESIGN.md` - Full trading specification
- `docs/FORGE_PROVENANCE_SYSTEM.md` - Chain integration details

---

## Changelog

| Date | Change |
|------|--------|
| 2025-12-06 | Added Effort Scoring System section with unified 0-100 scale |
| 2025-12-06 | Added `effort_score`, `effort_auto`, `effort_notes` to Achievement model |
| 2025-12-06 | Steam now uses effort_score (100 - global_percent) |
| 2025-12-06 | Battle.net now uses shared effort scoring from `effort_scoring.py` |
| 2025-12-06 | rarity_tier now computed from effort_score |
| 2024-12-06 | Added Layer 4: Global Claim Tracking to prevent orphan/relink exploit |
| 2024-12-06 | Added `provider_name`, `provider_user_id`, `is_original_claim` to AchievementCredit |
| 2024-12-06 | Updated sync logic to detect reclaims and mark as display-only |
| 2024-12-06 | Updated forge logic to reject non-original claims |
| 2024-12-06 | Added `is_admin` to User model for cooldown bypass |
| 2024-12-06 | Added `last_sync_at` to ProviderAccount for 15-min cooldown |
| 2024-12-06 | Added reclaim confirmation flow documentation |
| 2024-12-06 | Updated UI terminology: "Ashbane" (credited) vs "Consumed" (display-only) |
