# Provider Roadmap

> Cross-platform achievement aggregation strategy for Mantle

## Vision

Mantle aggregates achievements across gaming platforms AND non-gaming platforms (GitHub, Reddit, Discord) to create a unified "gamer identity" that feels fair and comparable across all sources. A WoW Feat of Strength should feel equivalent to a Steam <1% achievement or a GitHub Arctic Code Vault badge.

---

## Current State

### Implemented Providers

| Provider | Status | Auth Method | Achievement Data |
|----------|--------|-------------|------------------|
| **Steam** | ✅ Live | OpenID 2.0 | Full (%, unlock time, icons) |
| **Battle.net** | ✅ Live | OAuth 2.0 | Partial (points, FoS, no %) |
| **Xbox** | ✅ Live | OpenXBL (OAuth 2.0) | Full (%, gamerscore, icons) |

### Data We Currently Extract

#### Steam
```
Profile: steam_id, personaname, avatarfull, lastlogoff, timecreated, loccountrycode
Games: app_id, name, box_art_url
Achievements: api_name, display_name, description, icon_url, icon_gray_url,
              hidden, percent (global unlock %), unlock_time, rarity_tier
```

#### Battle.net (WoW)
```
Profile: battletag, characters (name, realm, avatar)
Achievements: id, name, description, points (10/30/50), is_feat_of_strength
```

#### Xbox (via OpenXBL)
```
Profile: xuid, gamertag
Games: titleId, name, displayImage
Achievements: id, name, description, gamerscore, rarity percentage,
              progressState (Achieved/NotStarted), mediaAssets (icons)
```

---

## Unified Rarity System

### The Problem

Each provider uses different rarity signals:
- **Steam/Xbox/PlayStation**: Global unlock percentage (0.1% - 100%)
- **WoW**: Point values (10/30/50) + Feat of Strength flag
- **GitHub**: Tiered badges (bronze/silver/gold)
- **Reddit**: Trophy rarity (some unobtainable)
- **Epic/GOG**: No rarity data

### Solution: Normalized Effort Score (0-100)

All achievements map to a unified `effort_score` that determines visual tier:

```
TIERS:
├── Common     (effort_score 0-19)   → Gray
├── Uncommon   (effort_score 20-39)  → Green
├── Rare       (effort_score 40-59)  → Blue
├── Epic       (effort_score 60-79)  → Purple
└── Legendary  (effort_score 80-100) → Gold
```

### Normalization Rules Per Provider

#### Steam / Xbox / PlayStation (percentage-based)
```python
effort_score = 100 - global_percent

# Examples:
# 2% unlock rate  → effort_score = 98 → Legendary
# 15% unlock rate → effort_score = 85 → Legendary
# 35% unlock rate → effort_score = 65 → Epic
# 60% unlock rate → effort_score = 40 → Rare
# 85% unlock rate → effort_score = 15 → Common
```

#### Battle.net (WoW)
```python
if is_feat_of_strength:
    effort_score = 90  # Legendary
elif is_legacy_removed:
    effort_score = 95  # Legendary (unobtainable)
elif points >= 50:
    effort_score = 70  # Epic
elif points >= 30:
    effort_score = 50  # Rare
elif points >= 10:
    effort_score = 30  # Uncommon
else:
    effort_score = 15  # Common
```

#### Xbox (Gamerscore fallback if no %)
```python
if gamerscore >= 100:
    effort_score = 80  # Legendary
elif gamerscore >= 50:
    effort_score = 60  # Epic
elif gamerscore >= 25:
    effort_score = 40  # Rare
elif gamerscore >= 10:
    effort_score = 20  # Uncommon
else:
    effort_score = 10  # Common
```

#### PlayStation (trophy grade fallback if no %)
```python
if trophy_type == "platinum":
    effort_score = 95  # Legendary
elif trophy_type == "gold":
    effort_score = 60  # Epic
elif trophy_type == "silver":
    effort_score = 40  # Rare
elif trophy_type == "bronze":
    effort_score = 20  # Uncommon
```

#### GitHub
```python
if badge in ["arctic_code_vault", "mars_2020_mission"]:
    effort_score = 95  # Legendary (unobtainable legacy)
elif badge_tier == "gold":
    effort_score = 75  # Epic
elif badge_tier == "silver":
    effort_score = 50  # Rare
elif badge_tier == "bronze":
    effort_score = 30  # Uncommon
else:
    effort_score = 20  # Uncommon (base badge)
```

#### Reddit
```python
if trophy in LEGACY_EVENT_TROPHIES:  # r/place, April Fools events
    effort_score = 90  # Legendary
elif trophy in ["gilding_xi", "gilding_x"]:  # High-tier gilding
    effort_score = 70  # Epic
elif trophy == "inciteful_comment":
    effort_score = 60  # Epic
elif trophy in ["verified_email", "new_user"]:
    effort_score = 10  # Common
else:
    effort_score = 30  # Uncommon (default)
```

#### Epic / GOG (no rarity data)
```python
effort_score = 30  # Default to Uncommon
# Allow manual admin override via tuning system
```

#### Facebook (friend count only)
```python
if friend_count >= 4000:
    effort_score = 70  # Epic
elif friend_count >= 2000:
    effort_score = 55  # Rare
elif friend_count >= 1000:
    effort_score = 40  # Rare
elif friend_count >= 500:
    effort_score = 30  # Uncommon
elif friend_count >= 200:
    effort_score = 20  # Uncommon
else:
    effort_score = 15  # Common
```

#### Roblox (winRatePercentage - like Steam)
```python
# Badges use same formula as Steam
effort_score = 100 - win_rate_percentage

# Example: 5% win rate -> 95 effort -> Legendary
# Example: 85% win rate -> 15 effort -> Common
```

---

## Provider Priority Tiers

### S-Tier (Core Gaming Platforms)

| Provider | Priority | Rationale |
|----------|----------|-----------|
| **Steam** | ✅ Implemented | Largest PC library, excellent API, global % |
| **Xbox** | ✅ Implemented | Great API parity with Steam, Gamerscore + % |
| **PlayStation** | ✅ Implemented | Platinum/Gold/Silver + rarity %, huge userbase |
| **Roblox** | ✅ Implemented | 70M+ DAU, Gen Z gateway, full rarity data |

### A-Tier (Gaming + Unique Value)

| Provider | Priority | Rationale |
|----------|----------|-----------|
| **Battle.net** | ✅ Implemented | WoW achievements are prestigious, Feats of Strength |
| **GitHub** | Medium | Native tiered achievements, developer identity, legacy badges |
| **Reddit** | Medium | Trophy API, karma as social proof, legacy event badges |

### B-Tier (Supplementary)

| Provider | Priority | Rationale |
|----------|----------|-----------|
| **Discord** | Low | HypeSquad + legacy badges via public_flags bitfield |
| **Epic Games** | Low | Growing platform, limited rarity data |
| **GOG** | Low | DRM-free niche, limited API |

### C-Tier (Limited Value)

| Provider | Priority | Rationale |
|----------|----------|-----------|
| **Facebook** | Low | Login gateway, friend count only, no achievements |
| **Twitch** | Skip | No achievement API, only badges |
| **Spotify** | Skip | No achievements, would need derived badges |
| **YouTube** | Skip | Only useful for creators |

---

## Provider Implementation Details

### Facebook

**Status:** Implemented (login gateway)

**Auth:** OAuth 2.0

**API Endpoints:**
- `GET /me?fields=id,name,picture,email,friends.summary(true)` - User profile + friend count

**Data Available:**
```
- User ID, name, email, profile picture
- Friend count (total_count from summary)
```

**Data NOT Available:**
```
- Account creation date (never exposed via API)
- Follower count (deprecated since API v2.0, 2014)
- Gaming achievements (Facebook Gaming shut down Oct 2024)
- Post count, likes, engagement metrics (require App Review)
```

**Effort Scoring (friend count only):**
```python
if friend_count >= 4000:
    effort_score = 70  # Epic - approaching 5000 limit
elif friend_count >= 2000:
    effort_score = 55  # Rare
elif friend_count >= 1000:
    effort_score = 40  # Rare
elif friend_count >= 500:
    effort_score = 30  # Uncommon
elif friend_count >= 200:
    effort_score = 20  # Uncommon
else:
    effort_score = 15  # Common
```

**Setup:**
1. Create app at developers.facebook.com
2. Set `FACEBOOK_APP_ID` and `FACEBOOK_APP_SECRET` env vars
3. Configure OAuth redirect URI
4. Request `public_profile`, `email`, `user_friends` permissions

**Notes:**
- Primary value is frictionless login for casual users
- Friend count is the only reliable achievement metric
- Most other data requires Facebook App Review (weeks)
- Platform limit is 5000 friends

---

### Roblox

**Status:** ✅ Implemented

**Auth:** OAuth 2.0 (with PKCE support)

**API Endpoints:**
- `GET /oauth/v1/userinfo` - User profile (via OAuth token)
- `GET /v1/users/{userId}/badges` - User badges (public API)
- `GET /v1/badges/{badgeId}` - Badge details + statistics
- `GET /v1/users/{userId}/badges/awarded-dates` - Unlock timestamps

**Data Available:**
```
Profile: user_id, display_name, username, created_at, avatar_url, profile_url
Badges: id, name, description, icon, awardedDate
Statistics: awardedCount, winRatePercentage (rarity!), pastDayAwardedCount
Games: universe_id, name, icon
```

**Effort Scoring:**
```python
# Badges use winRatePercentage (same formula as Steam)
effort_score = 100 - win_rate_percentage

# Tenure achievements (account age)
if account_age_years >= 10:
    effort_score = 85  # Legendary (OG - 2015 or earlier)
elif account_age_years >= 7:
    effort_score = 65  # Epic
elif account_age_years >= 5:
    effort_score = 45  # Rare
elif account_age_years >= 3:
    effort_score = 30  # Uncommon
else:
    effort_score = 15  # Common
```

**Setup:**
1. Create OAuth app at create.roblox.com (requires ID verification)
2. Set `ROBLOX_CLIENT_ID` and `ROBLOX_CLIENT_SECRET` env vars
3. Configure redirect URI
4. Request `openid` and `profile` scopes

**Notes:**
- Users must be 13+ to authorize OAuth apps (Roblox policy)
- Badges API is public, no auth needed for badge data
- `winRatePercentage` = % of players who earned badge (like Steam's global %)
- Account age available via `created_at` claim
- 70M+ daily active users, primarily Gen Z/Gen Alpha

**Docs:**
- https://create.roblox.com/docs/cloud/open-cloud/oauth2-overview
- https://create.roblox.com/docs/cloud/legacy/badges/v1

---

### Xbox Live (via OpenXBL)

**Status:** ✅ Implemented

**Auth:** OpenXBL OAuth (wraps Microsoft OAuth 2.0)

**Why OpenXBL:** Direct Xbox Live API requires ID@Xbox program membership. OpenXBL provides the same data via their third-party service, avoiding the approval process.

**API Endpoints (OpenXBL):**
- `GET /api/v2/account` - User profile (XUID, gamertag)
- `GET /api/v2/achievements` - User achievements
- `GET /api/v2/achievements/player/{xuid}` - Achievements by XUID
- `GET /api/v2/player/summary` - Player summary with gamerscore

**Data Available:**
```
- Achievement name, description, icon
- Gamerscore (5-100+ points)
- Global unlock percentage (0.0 - 1.0)
- "Rare" flag (auto-set when % <= 9%)
- Unlock timestamp
- Progress (1-100 for incomplete)
```

**OpenXBL Docs:** https://xbl.io/docs

**Rate Limit:** 150 requests/hour (free tier)

**Setup:** Set `OPENXBL_API_KEY` environment variable with your OpenXBL app key.

---

### PlayStation Network

**Auth:** OAuth 2.0 (unofficial/community-documented)

**API Endpoints:**
- No official public docs - community reverse-engineered
- Libraries: psn-api (JS), PlayStation-Trophies (docs)

**Data Available:**
```
- Trophy name, description, icon
- Trophy type: Bronze, Silver, Gold, Platinum
- Trophy points: 15 (B), 30 (S), 90 (G), 300 (P)
- Rarity percentage
- Rarity tier: Ultra Rare, Very Rare, Rare, Common
- Earned timestamp
```

**Community Docs:**
- https://github.com/andshrew/PlayStation-Trophies
- https://psn-api.achievements.app/

**Notes:** Sony has no official public API. Implementations rely on capturing my.playstation.com requests. May break with Sony updates.

---

### GitHub

**Auth:** GitHub OAuth 2.0

**API Endpoints:**
- Profile achievements visible on user profile page
- GraphQL API for contribution data
- REST API for repos, stars, followers

**Achievements Available:**
| Badge | Tiers | Criteria |
|-------|-------|----------|
| Pull Shark | Bronze/Silver/Gold | Merged PRs (2/16/128+) |
| Galaxy Brain | Bronze/Silver/Gold | Accepted answers |
| Starstruck | Bronze/Silver/Gold | Stars on repos (16/128/512+) |
| YOLO | Single | Merged PR without review |
| Quickdraw | Single | Fast issue close |
| Pair Extraordinaire | Bronze/Silver/Gold | Co-authored commits |
| **Arctic Code Vault** | Single | **LEGACY - Unobtainable** |
| **Mars 2020 Mission** | Single | **LEGACY - Unobtainable** |

**Official Docs:** https://docs.github.com/en/rest

**Notes:** Legacy badges (Arctic, Mars) are instant Legendary. Tiered badges map well to our system.

---

### Reddit

**Auth:** Reddit OAuth 2.0

**API Endpoints:**
- `GET /api/v1/me/trophies` - User trophies
- `GET /api/v1/me/karma` - Karma breakdown by subreddit

**Data Available:**
```
- Trophy name, description, icon
- Trophy ID (for categorization)
- Award date
- Link karma, comment karma (by subreddit)
- Account creation date
```

**Notable Trophies:**
| Trophy | Rarity | Notes |
|--------|--------|-------|
| Verified Email | Common | Everyone has this |
| Team Orangered/Periwinkle | Legendary | April Fools 2013, unobtainable |
| Sequence | Epic | r/place 2023, unobtainable |
| Inciteful Comment | Epic | Top controversial |
| Gilding I-XI | Tiered | Gold/awards given |
| Bellwether | Epic | Predicted trending posts |

**Official Docs:** https://www.reddit.com/dev/api/

**Notes:** Trophy system via API is solid. Legacy event trophies are rare and valuable.

---

### Discord

**Auth:** Discord OAuth 2.0

**API Endpoints:**
- `GET /users/@me` - Returns `public_flags` integer

**Badges (via public_flags bitfield):**
```python
DISCORD_FLAGS = {
    1 << 0:  "Discord Employee",
    1 << 1:  "Partnered Server Owner",
    1 << 2:  "HypeSquad Events",
    1 << 3:  "Bug Hunter Level 1",
    1 << 6:  "House Bravery",
    1 << 7:  "House Brilliance",
    1 << 8:  "House Balance",
    1 << 9:  "Early Supporter",       # LEGACY - Unobtainable
    1 << 14: "Bug Hunter Level 2",
    1 << 17: "Early Verified Bot Dev", # LEGACY - Unobtainable
}
```

**Official Docs:** https://discord.com/developers/docs

**Notes:** Active Developer badge was discontinued. Early Supporter (pre-Oct 2018 Nitro) is legendary-tier.

---

## Additional Data Opportunities

### Steam (Not Yet Using)

| Field | API | Value |
|-------|-----|-------|
| `playtime_forever` | GetOwnedGames | Total hours per game |
| `playtime_2weeks` | GetOwnedGames | Recent activity |
| `rtime_last_played` | GetOwnedGames | Last played timestamp |
| Game stats | GetUserStatsForGame | Kills, deaths, etc. |

**Recommendation:** Add playtime display. "1,200 hours in CS2" is impressive context.

### Battle.net (Not Yet Using)

| Field | API | Value |
|-------|-----|-------|
| Completion date | Achievement API | Month/Day/Year earned |
| Character level | Profile API | Progression indicator |
| Character item level | Profile API | Gear score proxy |
| Legacy achievements | Flags | No longer obtainable |

**Recommendation:** Add completion dates. "Earned: March 2012" shows veteran status.

---

## Database Schema Changes

### Achievement Model Updates

```python
class Achievement(Base):
    # ... existing fields ...

    # Unified rarity system
    effort_score = Column(Integer, default=30)      # 0-100 normalized
    effort_auto = Column(Boolean, default=True)     # Auto-calculated?
    effort_override = Column(Integer, nullable=True) # Manual admin override

    # Additional metadata
    is_legacy = Column(Boolean, default=False)      # Unobtainable?
    is_prestige = Column(Boolean, default=False)    # Admin-flagged special?
    estimated_hours = Column(Float, nullable=True)  # Time investment

    @property
    def rarity_tier(self):
        score = self.effort_override or self.effort_score
        if score >= 80: return "Legendary"
        if score >= 60: return "Epic"
        if score >= 40: return "Rare"
        if score >= 20: return "Uncommon"
        return "Common"
```

### Provider Account Updates

```python
class ProviderAccount(Base):
    # ... existing fields ...

    # Extended stats
    total_playtime_hours = Column(Float, nullable=True)  # Steam
    account_created_at = Column(DateTime, nullable=True) # Tenure
    legacy_badge_count = Column(Integer, default=0)      # Unobtainables
```

---

## Admin Tuning System

### Purpose

Allow admins to manually adjust achievement rarity when auto-calculation doesn't reflect true difficulty:

- WoW achievement harder than points suggest
- Steam achievement has inflated % due to bots
- Cross-game equivalence tuning

### Endpoints

```
POST /admin/achievements/{id}/tune
Body: { "effort_override": 85, "is_prestige": true }

GET /admin/achievements/review
Query: ?effort_auto=true&provider=steam&sort=effort_score
Returns: Achievements for manual review
```

### Tuning Guidelines

1. **Legacy/Unobtainable** → Automatic Legendary (90+)
2. **Time-gated events** → Epic minimum (60+)
3. **Skill-based** → Base on comparable achievements
4. **Grind-based** → Consider hours required

---

## Implementation Roadmap

### Phase 1: Foundation (Current)
- [x] Steam integration with global %
- [x] Battle.net integration with points
- [x] Add effort_score column to Achievement model
- [x] Unified effort scoring system (`app/services/effort_scoring.py`)
- [x] Steam uses effort_score (100 - global_percent)
- [x] Battle.net uses effort_score (points/FoS based)
- [x] rarity_tier computed from effort_score
- [ ] Pull Steam playtime data

### Phase 2: Console Gaming
- [x] Xbox Live OAuth integration (via OpenXBL)
- [x] Xbox achievement sync with Gamerscore + %
- [x] PlayStation OAuth integration (via NPSSO)
- [x] PlayStation trophy sync with grades + %
- [x] Roblox OAuth 2.0 integration
- [x] Roblox badge sync with winRatePercentage

### Phase 3: Non-Gaming Identity
- [x] GitHub OAuth integration
- [x] GitHub achievement badge sync
- [x] Discord badge extraction from public_flags
- [x] Facebook OAuth integration (login gateway)
- [x] Facebook friend count sync
- [ ] Reddit OAuth integration
- [ ] Reddit trophy sync

### Phase 4: Polish
- [ ] Admin tuning interface
- [ ] Legacy achievement auto-detection
- [ ] Cross-platform effort normalization tuning
- [ ] Playtime display on profile

---

## User Experience Goals

### The "Flex" Moment

When a Steam player sees a WoW player's profile:
> "Whoa, they have 3 Legendary Feats of Strength from 2010. That's like my <0.5% Steam achievements."

When a console player sees a PC player's profile:
> "They have Platinum trophies AND GitHub Arctic Code Vault? This person games AND codes."

### The "Go Play" Loop

1. User syncs achievements → sees Mantle card update
2. User plays more games → earns new achievements
3. User returns to Mantle → re-syncs → new credits
4. Free forge rewards for new Legendary/Epic achievements
5. New cosmetics in Godot game

### Cross-Platform Fairness

A user should never feel their platform is "worth less":
- Steam: % based (objective)
- PlayStation: Platinum = Legendary (clear)
- WoW: Feats of Strength = Legendary (clear)
- Xbox: Gamerscore maps to tiers (intuitive)
- GitHub: Tiered badges (already normalized)

---

## References

- [Steam Web API](https://partner.steamgames.com/doc/webapi)
- [Xbox Live API](https://learn.microsoft.com/en-us/gaming/gdk/)
- [PlayStation Trophies (Community)](https://github.com/andshrew/PlayStation-Trophies)
- [PSN API Library](https://psn-api.achievements.app/)
- [GitHub REST API](https://docs.github.com/en/rest)
- [GitHub Achievements Guide](https://githubachievements.com/)
- [Reddit API](https://www.reddit.com/dev/api/)
- [Discord Developer Docs](https://discord.com/developers/docs)
- [GOG Galaxy SDK](https://docs.gog.com/sdk/)
