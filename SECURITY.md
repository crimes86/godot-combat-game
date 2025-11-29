# Security Audit & Improvement Roadmap

Last audit: 2025-11-29

## Completed Fixes (This Session)

### Critical
- [x] **Healing RPC validation** - Server now validates healer has healing weapon equipped before processing heal requests
- [x] **is_instance_valid() checks** - Added to healing RPC to prevent crashes from invalid node references

### High Priority
- [x] **Rate limit memory leak** - DatabaseManager now erases login_attempts entry on successful login
- [x] **Attack cooldown cleanup** - NetworkEnemyManager clears cooldown entries when players disconnect
- [x] **Attack cooldown tightened** - Reduced from 80ms to 90ms (client uses 100ms)

---

## Long-Term Security Improvements Needed

### CRITICAL - Network Security

#### 1. Password Transport Vulnerability
**File:** `scripts/networking/NetworkManager.gd:413-418`
**Issue:** Passwords are SHA256 hashed client-side without salt, sent over unencrypted ENet
**Risk:** Vulnerable to rainbow table attacks and MITM attacks
**Recommendation:**
- Implement challenge-response authentication
- Add TLS/DTLS layer for network encryption
- Consider using Godot 4's built-in encryption options or external auth service

#### 2. Missing Input Sanitization Service
**Issue:** Chat messages, usernames validated in multiple places with inconsistent logic
**Recommendation:** Create centralized `InputValidator` autoload:
```gdscript
# scripts/systems/InputValidator.gd
extends Node

static func sanitize_username(username: String) -> String:
    # Centralized validation logic

static func sanitize_chat(msg: String) -> String:
    # Remove control characters, validate length
```

---

### HIGH - Code Hardening

#### 3. Unsafe Node Lookups (85+ occurrences)
**Files:** `Player.gd`, `NetworkManager.gd`, various UI scripts
**Issue:** Many `get_node_or_null()` calls without `is_instance_valid()` checks
**Risk:** Potential crashes if nodes are freed while references held
**Recommendation:** Audit all node lookups, add validation pattern:
```gdscript
var node = get_node_or_null("/root/SomeNode")
if node and is_instance_valid(node):
    node.some_method()
```

#### 4. Hardcoded Node Paths
**Issue:** Paths like `/root/GameWorld`, `/root/SoundManager` throughout codebase
**Risk:** Brittle to scene structure changes
**Recommendation:** Use groups instead:
```gdscript
var game_world = get_tree().get_first_node_in_group("game_world")
```

---

### MEDIUM - Anti-Cheat Improvements

#### 5. Damage Validation Buffer Too Generous
**File:** `scripts/networking/NetworkEnemyManager.gd:143`
**Current:** 50% buffer allows damage up to 1.5x expected max
**Recommendation:** Reduce to 10-20%, calculate expected crit damage properly

#### 6. Group Leader Validation Gap
**File:** `scripts/systems/GroupManager.gd`
**Issue:** When `group_leader == -1`, leader checks may pass incorrectly
**Recommendation:** Add explicit validation:
```gdscript
func _validate_is_leader(peer_id: int) -> bool:
    return group_leader > 0 and group_leader == peer_id
```

#### 7. Missing Heal Cooldown
**Issue:** Players can spam heal requests without server-side cooldown
**Recommendation:** Add per-player heal cooldown similar to attack_cooldowns

---

### LOW - Technical Debt

#### 8. Excessive Debug Logging
**Files:** `Player.gd` (100+ print statements), `NetworkManager.gd`
**Recommendation:** Replace with `DebugConfig.debug_log()` calls with configurable levels

#### 9. Over-engineered Name Update Retry System
**File:** `scripts/networking/NetworkManager.gd:237-289`
**Issue:** 60-retry polling loop for setting player names
**Recommendation:** Use signal-based approach with `player_spawned` signal

#### 10. Missing Graceful Shutdown
**Issue:** Timers, signal connections not cleaned up on `_exit_tree()`
**Recommendation:** Add cleanup in all scripts with timers/connections

---

## Security Checklist for New Features

When adding new RPC endpoints:
- [ ] Validate `multiplayer.get_remote_sender_id()` is authenticated
- [ ] Validate sender has required items/abilities equipped
- [ ] Add rate limiting/cooldown checks
- [ ] Clamp all numeric inputs to reasonable bounds
- [ ] Add `is_instance_valid()` checks on all node references
- [ ] Log suspicious activity with `push_warning()` for anti-cheat monitoring

When adding new UI inputs:
- [ ] Strip and validate all text inputs
- [ ] Check length limits
- [ ] Filter control characters
- [ ] Sanitize before display (prevent injection)

---

## Monitoring & Logging

Current anti-cheat logging uses `push_warning()` for:
- Attack speed violations
- Suspicious damage amounts
- Heal requests without healing weapon
- Unauthenticated peer actions

Consider implementing:
- [ ] Server-side audit log file
- [ ] Player reputation/trust score
- [ ] Automatic temporary bans for repeated violations
- [ ] Admin notification system for suspicious activity
