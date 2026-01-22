# Network Latency Fixes Specification

## Goal
Make the game feel like single-player even at 200ms RTT (Asia/America on same servers).

**Design Philosophy:** Client predicts locally for instant feedback, server validates asynchronously, reconcile on mismatch.

---

## Critical Issues (Priority 1)

### 1. Damage Feedback Delay (200-400ms)

**Current Flow:**
```
Client attacks → RPC to server (200ms) → Server validates → RPC broadcast back (200ms) → Client shows damage
Total: 400ms before player sees damage numbers
```

**File:** `scripts/player/PlayerCombat.gd` lines 1016-1028

**Current Code:**
```gdscript
if has_peer and enemy_net_id >= 0:
    network_enemy_mgr.request_damage.rpc_id(1, enemy_net_id, damage, is_crit, hit_weakpoint)
    # Server will broadcast visual feedback via _client_enemy_damaged
    _track_weapon_hit(damage, is_crit, enemy, enemy_hp_before)
    return  # ← PROBLEM: No local feedback, waits for server
```

**Fix - Add client prediction before return:**
```gdscript
if has_peer and enemy_net_id >= 0:
    # CLIENT PREDICTION: Show feedback immediately (0ms)
    _show_predicted_damage_feedback(enemy, damage, is_crit, hit_weakpoint)

    # Send to server for authoritative validation
    network_enemy_mgr.request_damage.rpc_id(1, enemy_net_id, damage, is_crit, hit_weakpoint)
    _track_weapon_hit(damage, is_crit, enemy, enemy_hp_before)
    return

func _show_predicted_damage_feedback(enemy: Node, damage: float, is_crit: bool, hit_weakpoint: bool) -> void:
    """Client-side predicted feedback - shown instantly, server reconciles later"""
    # 1. Damage number (copy from single-player path below)
    if attack_feedback and attack_feedback.has_method("spawn_damage_number"):
        attack_feedback.spawn_damage_number(enemy.global_position, damage, is_crit, hit_weakpoint)

    # 2. Blood splatter particles
    if attack_feedback and attack_feedback.has_method("trigger_attack_feedback"):
        attack_feedback.trigger_attack_feedback(enemy.global_position, is_crit, hit_weakpoint)

    # 3. Hit flash on enemy (if available)
    if enemy.has_node("HitFlash"):
        enemy.get_node("HitFlash").flash(is_crit)

    # 4. Hit sound (same logic as single-player)
    _play_hit_sound(enemy, is_crit)

    # 5. OPTIONAL: Predict health bar (can cause visual pop if server disagrees)
    # if enemy.health_bar:
    #     var predicted_hp = max(0, enemy.current_health - damage)
    #     enemy.health_bar.update_health(predicted_hp, enemy.max_health)
```

**Server-side change:** In `_client_enemy_damaged()`, add flag to skip feedback if already predicted:
```gdscript
# File: scripts/networking/NetworkEnemyManager.gd line 557
func _client_enemy_damaged(..., attacker_id: int = 0) -> void:
    # Skip visual feedback for attacker (they already predicted it)
    var my_peer_id = multiplayer.get_unique_id()
    var skip_feedback = (attacker_id == my_peer_id)

    # Update health bar (authoritative - always apply)
    if enemy.health_bar:
        enemy.health_bar.update_health(new_health, max_health)

    # Visual feedback only for non-attackers (they see the hit happen to enemy)
    if not skip_feedback:
        if enemy.has_node("HitFlash"):
            enemy.get_node("HitFlash").flash(is_crit)
        # spawn combat text, etc.
```

---

### 2. Healing Feedback Delay (200-250ms)

**Current Flow:**
```
Healer casts → RPC to server (200ms) → Server validates → Sync health back (200ms)
Healer sees nothing until server responds
```

**File:** `scripts/networking/NetworkManager.gd` lines 1636-1704

**Fix - Client prediction for healing:**

```gdscript
# File: scripts/player/Player.gd around line 1682
func heal_allies(allies: Array, heal_amount: float) -> void:
    for ally in allies:
        if is_multiplayer_authority():
            # CLIENT PREDICTION: Show heal effect immediately
            _show_predicted_heal(ally, heal_amount)

            # Send to server for validation
            var ally_peer_id = ally.get_multiplayer_authority()
            network_manager.request_player_heal.rpc_id(1, ally_peer_id, heal_amount)
        else:
            # Server/single-player: apply directly
            ally.heal(heal_amount, "player", my_peer_id)

func _show_predicted_heal(target: Node, amount: float) -> void:
    """Client-predicted heal feedback"""
    # 1. Green heal number
    CombatText.create_heal(amount, target.global_position, target.get_parent())

    # 2. Heal sound
    var sound_manager = get_node_or_null("/root/SoundManager")
    if sound_manager:
        sound_manager.play_healing_impact_sound(target.global_position)

    # 3. OPTIONAL: Predict health bar (reconcile on server response)
    # var predicted_hp = min(target.current_health + amount, target.max_health)
    # target.health_bar.update_health(predicted_hp, target.max_health)
```

**Server reconciliation:** `_sync_player_health()` already handles authoritative health sync.

---

### 3. Weakpoint Window Desync (Critical)

**Current Problem:** Each client triggers weakpoint windows locally based on their view of hit counts/health thresholds. At 200ms latency, clients see different game states and trigger windows at different times.

**Example Desync:**
```
Player A hits enemy (client sees HP drop to 74%)
Player B hits enemy 50ms later (their client still sees 76%)
Player A's client triggers 75% threshold window
Player B's client hasn't crossed threshold yet - no window
```

**File:** `scripts/systems/crit_window_manager.gd`

**Fix Option A - Server-Authoritative Windows:**
```gdscript
# Server tracks thresholds and broadcasts window events
# File: scripts/networking/NetworkEnemyManager.gd

func _apply_damage_internal(...):
    # ... existing damage logic ...

    # Check for weakpoint window trigger (SERVER ONLY)
    var threshold_crossed = _check_threshold_trigger(enemy_network_id, enemy, attacker_id)
    if threshold_crossed:
        # Broadcast to attacker only (they see the window)
        _start_weakpoint_window.rpc_id(attacker_id, enemy_network_id)

@rpc("authority", "reliable")
func _start_weakpoint_window(enemy_network_id: int) -> void:
    """Server tells client to start a weakpoint window"""
    var enemy = get_enemy(enemy_network_id)
    if enemy and is_instance_valid(enemy):
        var crit_window_mgr = _get_local_crit_window_manager()
        if crit_window_mgr:
            crit_window_mgr.start_window(enemy)
```

**Fix Option B - Client-Predicted with Server Validation:**
Keep current client-predicted windows but add server acknowledgment:
```gdscript
# Client starts window locally (instant feedback)
# Client reports to server: "I started a window on enemy X"
# Server validates: "Yes, threshold was crossed" or "No, reject"
# If rejected, client closes window early
```

**Recommendation:** Option A is cleaner but adds 200ms delay to window start. Option B keeps instant feedback but is more complex. For 200ms target, Option B is better.

---

## High Priority Issues (Priority 2)

### 4. Enemy Movement Interpolation (300-400ms visual lag)

**Current Code:** `scripts/networking/NetworkEnemyManager.gd` line 264
```gdscript
const LERP_SPEED: float = 12.0  # Assumes ~50ms between updates
```

**Problem:** At 200ms latency + 50ms tick rate, enemies are always "catching up" visually.

**Fix - Velocity-based extrapolation:**
```gdscript
# Track velocity for prediction
var enemy_velocities: Dictionary = {}  # network_id -> Vector2

func _receive_enemy_position(id: int, pos: Vector2, ...) -> void:
    # Calculate velocity from position delta
    if enemy_target_positions.has(id):
        var old_pos = enemy_target_positions[id]
        var dt = get_sync_interval()  # Time between updates
        enemy_velocities[id] = (pos - old_pos) / dt

    enemy_target_positions[id] = pos

func _interpolate_enemy_positions(delta: float) -> void:
    for id in enemy_target_positions:
        var enemy = get_enemy(id)
        var target = enemy_target_positions[id]
        var velocity = enemy_velocities.get(id, Vector2.ZERO)

        # Extrapolate: predict where enemy WILL be
        var time_since_update = _get_time_since_last_update(id)
        var predicted_pos = target + velocity * time_since_update

        # Smoothly move toward predicted position
        enemy.global_position = enemy.global_position.lerp(predicted_pos, delta * 15.0)
```

**Alternative - Increase sync rate for nearby enemies:**
```gdscript
# Already partially implemented in DynamicTickRateManager
# Ensure nearby enemies sync at 30Hz+ (33ms) not 20Hz (50ms)
```

---

### 5. Remote Player Animation Delay (200ms)

**Current:** Animation changes sent via position sync, 200ms behind.

**File:** `scripts/networking/NetworkPlayer.gd` line 139

**Fix - Predict animations from velocity:**
```gdscript
func _physics_process(delta):
    if not is_local:
        # Interpolate position (existing)
        _interpolate_position(delta)

        # PREDICT animation from movement
        var velocity = (target_position - player_instance.global_position)
        if velocity.length() > 5.0:
            var predicted_anim = _velocity_to_animation(velocity)
            player_instance.play_animation(predicted_anim)
        else:
            # Use synced animation for idle/special states
            player_instance.play_animation(sync_animation)

func _velocity_to_animation(vel: Vector2) -> String:
    # Convert velocity to walk/run animation
    var dir = vel.normalized()
    if abs(dir.x) > abs(dir.y):
        return "walk_right" if dir.x > 0 else "walk_left"
    else:
        return "walk_down" if dir.y > 0 else "walk_up"
```

---

## Implementation Checklist

### Phase 1: Instant Feedback (Most Impact) ✅ COMPLETE
- [x] Add `_show_predicted_damage_feedback()` in PlayerCombat.gd
- [x] Add `_show_predicted_damage_feedback()` in Player.gd (legacy path)
- [x] Add `skip_feedback` flag to `_client_enemy_damaged()` for attacker
- [x] Add heal sound to `heal_allies()` in Player.gd
- [ ] Test at 200ms simulated latency

### Phase 2: Weakpoint Sync ✅ COMPLETE (Option A)
- [x] Choose Option A - Server-authoritative with charging animation
- [x] Weakpoints spawn in "charging" state (pulsing, 40% opacity, not clickable)
- [x] Client requests validation via `request_weakpoint_window_validation` RPC
- [x] Server confirms via `confirm_weakpoint_window` RPC
- [x] On confirmation, `activate()` makes weakpoints clickable with pop animation
- [ ] Test multi-client weakpoint scenarios

### Phase 3: Smooth Movement ✅ COMPLETE
- [x] Add velocity tracking to enemy interpolation (`enemy_velocities`, `enemy_last_update_times`)
- [x] Implement position extrapolation in `_interpolate_enemy_positions()`
- [x] Tune LERP_SPEED for 200ms scenario (increased to 15.0)
- [ ] Add animation prediction for remote players (optional)

### Phase 4: Testing
- [ ] Test with artificial 200ms latency (network conditioner)
- [ ] Test with 2+ clients attacking same enemy
- [ ] Test healing in group scenarios
- [ ] Profile bandwidth impact of changes

---

## Testing Commands

**Simulate latency on Windows:**
```powershell
# Use Clumsy (https://jagt.github.io/clumsy/)
# Or network conditioner in Windows
```

**Simulate latency on Linux server:**
```bash
tc qdisc add dev eth0 root netem delay 100ms
# This adds 100ms each way = 200ms RTT
```

---

## Bandwidth Budget

Current estimates per client at 200ms RTT:
- Position sync (30Hz): ~3 KB/s
- Enemy sync (20Hz, 50 enemies): ~8 KB/s
- Damage events: ~0.5 KB/s
- **Total:** ~12 KB/s per client

With 100 clients: ~1.2 MB/s server bandwidth

**Budget target:** 100 KB/s per client max

---

## Files to Modify

| File | Changes |
|------|---------|
| `scripts/player/PlayerCombat.gd` | Add `_show_predicted_damage_feedback()` |
| `scripts/player/Player.gd` | Add `_show_predicted_heal()` |
| `scripts/networking/NetworkEnemyManager.gd` | Add `skip_feedback` flag, velocity tracking |
| `scripts/networking/NetworkPlayer.gd` | Add animation prediction |
| `scripts/networking/NetworkManager.gd` | No changes needed (heal sync already works) |
| `scripts/systems/crit_window_manager.gd` | Server-side threshold sync |

---

## Success Criteria

At 200ms RTT:
1. **Damage feedback:** 0ms (instant) - client predicted
2. **Heal feedback:** 0ms (instant) - client predicted
3. **Weakpoint windows:** <50ms sync between clients
4. **Enemy movement:** Smooth, no visible rubber-banding
5. **Health bars:** Authoritative (may have brief desync, acceptable)
