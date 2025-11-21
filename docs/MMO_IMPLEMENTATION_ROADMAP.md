# Mini-MMO Implementation Roadmap

## Timeline: 12-18 Weeks Total

---

## PHASE 1: Foundation (Weeks 1-3)

### Week 1: Database & Auth System

**Tasks:**
- [ ] Install godot-sqlite addon
- [ ] Create database schema (see DATABASE_SCHEMA.md)
- [ ] Implement Database class wrapper
- [ ] Create player registration system
- [ ] Implement password hashing (bcrypt)
- [ ] Build login/logout flow
- [ ] Create account UI (login screen, registration form)

**Deliverable:** Players can create accounts and log in

**Testing Checklist:**
- Create account with username/password
- Log in successfully
- Reject duplicate usernames
- Reject invalid credentials
- Handle database connection errors

---

### Week 2: Singleton Refactoring

**Tasks:**
- [ ] Create CharacterStats class (non-singleton)
- [ ] Create InventorySystem class (non-singleton)
- [ ] Update Player.gd to use instance references
- [ ] Update Enemy.gd to reference player stats correctly
- [ ] Update UI scripts (CharacterUI, ShopUI) for instance access
- [ ] Create ServerPlayerData class to hold per-player state
- [ ] Update all 500+ CharacterStats references
- [ ] Update all 100+ InventorySystem references

**Deliverable:** Game runs with instanced stats/inventory (still single-player)

**Testing Checklist:**
- Character sheet displays correct stats
- Equipment changes update stats
- Inventory add/remove works
- Combat damage calculation correct
- Level up increases stats

---

### Week 3: Headless Server Setup

**Tasks:**
- [ ] Create headless server entry point (server_main.gd)
- [ ] Configure export templates for dedicated server
- [ ] Implement server tick loop (30 Hz)
- [ ] Create server console logging
- [ ] Add command-line arguments (--port, --max-players)
- [ ] Implement graceful shutdown handler
- [ ] Create systemd service file
- [ ] Write Docker deployment configuration

**Deliverable:** Headless server runs and accepts connections

**Testing Checklist:**
- Server starts without rendering
- Server accepts client connections
- Server logs player join/leave
- Server survives client disconnect
- Ctrl+C gracefully shuts down

---

## PHASE 2: Core Networking (Weeks 4-6)

### Week 4: Player Connection & Authentication

**Tasks:**
- [ ] Implement peer_connected/peer_disconnected handlers
- [ ] Create login RPC (request_login)
- [ ] Validate credentials against database
- [ ] Prevent duplicate logins
- [ ] Load player data from database on login
- [ ] Spawn player node in server world
- [ ] Send initial world state to client
- [ ] Implement logout save (auto-save on disconnect)

**Deliverable:** Players can log in and see their character in world

**Testing Checklist:**
- Client connects to server
- Login with valid credentials succeeds
- Login with invalid credentials fails
- Player spawns at saved position
- Disconnect saves player data
- Cannot log in twice with same account

---

### Week 5: Movement Synchronization

**Tasks:**
- [ ] Implement client input sending (send_input RPC)
- [ ] Server processes input and moves players
- [ ] Implement client-side prediction
- [ ] Server broadcasts positions (sync_player_position)
- [ ] Implement position reconciliation (client correction)
- [ ] Add movement validation (speed hacks)
- [ ] Optimize with unreliable RPCs
- [ ] Implement Area of Interest (AOI) system

**Deliverable:** Multiple players can move and see each other

**Testing Checklist:**
- Player moves smoothly (no jitter)
- Other players' movement visible
- Movement works with 200+ ping
- Movement validation rejects teleport hacks
- AOI hides distant players

---

### Week 6: Multi-Player World State

**Tasks:**
- [ ] Sync player animations across network
- [ ] Sync player sprite layers (equipment visuals)
- [ ] Implement player name labels
- [ ] Sync player health bars
- [ ] Handle player death across network
- [ ] Implement player respawn
- [ ] Create player list UI (Tab key)

**Deliverable:** Full player representation across network

**Testing Checklist:**
- Players see each other's animations
- Equipment visual updates sync
- Name labels display correctly
- Health bars update in real-time
- Death visible to all players
- Respawn works correctly

---

## PHASE 3: Combat & Progression (Weeks 7-10)

### Week 7: Networked Combat

**Tasks:**
- [ ] Implement request_attack RPC
- [ ] Server validates attacks (cooldown, range)
- [ ] Server calculates damage (authoritative)
- [ ] Server applies damage to enemies
- [ ] Broadcast damage feedback (damage numbers)
- [ ] Sync enemy health across clients
- [ ] Implement enemy tagging system
- [ ] Prevent kill-stealing

**Deliverable:** Combat works in multiplayer

**Testing Checklist:**
- Player attacks hit enemies
- Damage numbers appear for all players
- Enemy health syncs correctly
- Only tagged player gets XP/loot
- Attack validation prevents hacks

---

### Week 8: Crit Windows & Chain System

**Tasks:**
- [ ] Implement per-player crit windows
- [ ] Send weakpoint spawn only to owner
- [ ] Track crit window ownership
- [ ] Prevent other players clicking your weakpoints
- [ ] Decide: per-player or shared chain system
- [ ] If per-player: instance ChainManager per player
- [ ] If shared: sync chain level across clients
- [ ] Update chain UI for chosen approach

**Deliverable:** Crit windows work in multiplayer

**Testing Checklist:**
- Crit triggers weakpoints
- Only triggering player sees weakpoints
- Clicking weakpoints works correctly
- Chain multiplier displays properly
- Chain resets work across network

---

### Week 9: XP & Leveling

**Tasks:**
- [ ] Server awards XP to damage dealers
- [ ] Implement group XP sharing (if in party)
- [ ] Apply group XP bonus (+10% per player)
- [ ] Sync level-up across network
- [ ] Broadcast level-up visual effects
- [ ] Update stat increases server-side
- [ ] Sync new stats to client
- [ ] Update enemy level displays

**Deliverable:** Progression works in multiplayer

**Testing Checklist:**
- Killing enemy awards XP
- Group kills share XP fairly
- Group bonus applies correctly
- Level-up increases stats
- Stats sync to client immediately

---

### Week 10: Loot & Inventory

**Tasks:**
- [ ] Implement instanced loot per player
- [ ] Generate loot on enemy death (per player)
- [ ] Send loot spawn only to owner
- [ ] Implement pickup requests (request_pickup_item)
- [ ] Validate pickup range server-side
- [ ] Sync inventory adds to client
- [ ] Implement inventory full handling
- [ ] Apply group drop rate bonus

**Deliverable:** Loot system works in multiplayer

**Testing Checklist:**
- Each player gets own loot
- Loot appears only to owner
- Pickup range validated
- Inventory syncs correctly
- Inventory full prevents pickup
- Group bonus increases drops

---

## PHASE 4: Advanced Systems (Weeks 11-14)

### Week 11: Phasing System

**Tasks:**
- [ ] Implement PhasingManager singleton
- [ ] Track player phases in database
- [ ] Implement phase visibility rules
- [ ] Create shared zone detection
- [ ] Spawn phase-specific enemies
- [ ] Hide enemies from wrong-phase players
- [ ] Implement ruins conversion trigger
- [ ] Create phase transition flow

**Deliverable:** Phasing system functional

**Testing Checklist:**
- Players in same phase see each other
- Players in different phases don't see each other
- Shared zones work (campfire, vendors)
- Phase transition advances player correctly
- Converted ruins appear for right players

---

### Week 12: Shop & Vendors

**Tasks:**
- [ ] Sync shop UI across network
- [ ] Implement purchase requests (request_buy_item)
- [ ] Validate gold amount server-side
- [ ] Prevent race conditions (two players buying last item)
- [ ] Deduct gold on server
- [ ] Add item to inventory on server
- [ ] Sync gold and inventory to client
- [ ] Phase-specific vendor inventories

**Deliverable:** Shopping works in multiplayer

**Testing Checklist:**
- Players can buy items
- Gold deducted correctly
- Inventory receives item
- Insufficient gold prevents purchase
- Race condition handled gracefully

---

### Week 13: Campfire & Buffs

**Tasks:**
- [ ] Sync campfire fuel across players
- [ ] Implement shared campfire buffs (all players benefit)
- [ ] Add fuel requests (request_add_fuel)
- [ ] Validate fuel in player inventory
- [ ] Deduct fuel items server-side
- [ ] Broadcast fuel level updates
- [ ] Sync buff auras to all clients
- [ ] Apply healing/crit buffs server-side

**Deliverable:** Campfires work in multiplayer

**Testing Checklist:**
- Adding fuel works from any player
- Fuel level syncs to all players
- Buffs apply to all nearby players
- Auras visible to all players
- Fuel decay syncs correctly

---

### Week 14: Chat & Social

**Tasks:**
- [ ] Implement chat system (send_chat_message RPC)
- [ ] Create chat UI with channels (global, party, whisper)
- [ ] Implement chat sanitization
- [ ] Add spam protection (rate limiting)
- [ ] Log chat to database
- [ ] Create player inspect feature (right-click player)
- [ ] Implement party invite system
- [ ] Create friend list (optional)

**Deliverable:** Communication systems work

**Testing Checklist:**
- Global chat broadcasts to all
- Spam protection prevents flood
- Chat persists in database
- Player inspect shows stats/gear
- Party invites work

---

## PHASE 5: Content & Polish (Weeks 15-18)

### Week 15: Zones & Enemies

**Tasks:**
- [ ] Complete single-player content (Zones 2-4)
- [ ] Implement boss fight (Necromancer King)
- [ ] Create boss instance system
- [ ] Implement daily boss lockout
- [ ] Add roaming enemies along paths
- [ ] Balance enemy HP for multiplayer
- [ ] Tune group scaling formulas
- [ ] Test with 2-4 players

**Deliverable:** Full content playable multiplayer

**Testing Checklist:**
- All 4 zones accessible
- Boss fight works in instance
- Daily lockout prevents re-farming
- Enemy HP scales reasonably
- Group difficulty feels balanced

---

### Week 16: Save/Load & Persistence

**Tasks:**
- [ ] Implement auto-save (every 5 minutes)
- [ ] Save player position, stats, inventory
- [ ] Save world state (chests opened, etc.)
- [ ] Implement manual save command
- [ ] Create backup system (hourly snapshots)
- [ ] Test database corruption recovery
- [ ] Implement rollback command (admin only)
- [ ] Create export character feature

**Deliverable:** Player progress persists reliably

**Testing Checklist:**
- Progress saves every 5 minutes
- Server crash doesn't lose data
- Database backup system works
- Character can be exported/imported

---

### Week 17: Performance & Security

**Tasks:**
- [ ] Optimize AOI distance calculations
- [ ] Implement entity pooling (enemies, damage numbers)
- [ ] Add network compression
- [ ] Profile server tick time (target <30ms)
- [ ] Implement anti-cheat (movement validation)
- [ ] Add admin commands (kick, ban, teleport)
- [ ] Create server monitoring dashboard
- [ ] Load test with 20+ bots

**Deliverable:** Server handles 50 concurrent players

**Testing Checklist:**
- Server tick time <30ms average
- Memory usage stable (no leaks)
- Network bandwidth reasonable (<1 TB/month)
- Anti-cheat catches speed hacks
- Admin commands work correctly

---

### Week 18: Testing & Bug Fixes

**Tasks:**
- [ ] Organize 10-player playtest
- [ ] Fix all critical bugs found
- [ ] Balance enemy difficulty based on feedback
- [ ] Tune XP/loot rates
- [ ] Polish UI for multiplayer (chat UX)
- [ ] Write player documentation
- [ ] Create server admin guide
- [ ] Prepare for launch

**Deliverable:** Game ready for public testing

---

## Post-Launch Roadmap (Optional)

### Short-Term (Weeks 19-24)
- [ ] Guild/clan system
- [ ] Player trading system
- [ ] Leaderboards (XP, boss kills)
- [ ] Daily quests
- [ ] Seasonal events

### Medium-Term (Months 6-12)
- [ ] New zones (5-8)
- [ ] Additional enemy types
- [ ] Crafting system
- [ ] Housing/base building
- [ ] PvP arena (optional)

### Long-Term (Year 2+)
- [ ] Expansions with new story
- [ ] Raids (8-player boss fights)
- [ ] Prestige/rebirth system
- [ ] Cosmetic shop (monetization)

---

## Development Tips

### Parallel Work Streams

If working with a team, these can be done in parallel:

**Stream A: Core Systems (1 person)**
- Database, auth, networking core

**Stream B: Gameplay (1 person)**
- Combat, loot, progression

**Stream C: Content (1 person)**
- Zones, enemies, quests

**Stream D: UI/UX (1 person)**
- Menus, chat, HUD

### Solo Development

Focus on getting one feature fully working before moving to next:
1. Week-by-week approach
2. Test each week's deliverable thoroughly
3. Don't move forward with broken systems
4. Keep single-player build working as fallback

### Risk Areas

**High Risk (test early):**
- Database corruption
- Network desync
- Memory leaks
- Security exploits

**Medium Risk:**
- Performance with 20+ players
- Phasing edge cases
- Loot distribution bugs

**Low Risk:**
- UI polish
- Chat features
- Social systems

### Tools You'll Need

- **godot-sqlite**: Database addon
- **bcrypt**: Password hashing (GDExtension)
- **Docker**: Server deployment
- **Git**: Version control
- **Wireshark**: Network debugging (optional)
- **htop/btop**: Server monitoring

### Estimated Costs

**Development:**
- $0 (Godot is free)
- $0 (SQLite is free)
- Time: 12-18 weeks solo

**Hosting (Production):**
- VPS: $5-12/month (Hetzner/DigitalOcean)
- Domain: $10/year (optional)
- Backup storage: $2/month (optional)

**Total: ~$10-15/month operational cost**

### Success Metrics

**Technical:**
- Server uptime >99%
- Tick time <30ms average
- <5% packet loss
- <100ms latency (regional)

**Gameplay:**
- Players reach endgame (level 30)
- Average session >30 minutes
- Retention >50% week 2
- Positive feedback on combat feel

---

## Next Steps

1. **Commit current work** (campfire auras)
2. **Finish single-player MVP** (3-4 weeks)
   - Save/load system
   - Main menu
   - Tutorial
   - Boss fight
3. **Start Phase 1 of MMO** (Week 1: Database & Auth)

Would you like me to start on any of these phases?
