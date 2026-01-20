#!/usr/bin/env python3
"""
Bot Manager Control Tool

Control stress test bots on the Ashbane server.

Usage:
    python bot_control.py spawn 50 cluster 0 0     # Invisible stress bots
    python bot_control.py vspawn 10 wander 0 0     # Visible bots (clients can see)
    python bot_control.py ramp 200 60
    python bot_control.py status
    python bot_control.py metrics
    python bot_control.py despawn all

Invisible Bot Commands (server-side stress testing, clients can't see):
    spawn <count> [behavior] [x] [y]  - Spawn bots (behavior: idle/wander/cluster/combat/reinforce)
    despawn <count|all>               - Despawn bots
    behavior <mode> [x] [y]           - Change all bot behavior
    ramp <target> <seconds>           - Gradually ramp to target count
    stop                              - Stop active ramp

Visible Bot Commands (actual players that clients can see):
    vspawn <count> [behavior] [x] [y] - Spawn visible bots
    vdespawn <count|all>              - Despawn visible bots
    vbehavior <mode> [x] [y]          - Change visible bot behavior
    vstatus                           - Get visible bot status

General Commands:
    status                            - Get current status
    metrics                           - Get performance metrics
    watch                             - Live metrics display (Ctrl+C to stop)
"""

import socket
import json
import sys
import time
import argparse

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 9051  # BotManager port

def send_command(cmd: dict, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> dict:
    """Send a JSON command to the BotManager and return response"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5.0)
        sock.connect((host, port))

        # Send command
        sock.send((json.dumps(cmd) + "\n").encode())

        # Read response
        data = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
            if b"\n" in data:
                break

        sock.close()

        if data:
            return json.loads(data.decode().strip())
        return {"error": "No response"}

    except ConnectionRefusedError:
        return {"error": "Connection refused - is the server running?"}
    except socket.timeout:
        return {"error": "Connection timeout"}
    except Exception as e:
        return {"error": str(e)}

def cmd_spawn(args):
    """Spawn stress test bots"""
    cmd = {
        "action": "bots_spawn",
        "count": args.count,
        "behavior": args.behavior,
        "x": args.x,
        "y": args.y
    }
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_despawn(args):
    """Despawn bots"""
    count = "all" if args.count == "all" else int(args.count)
    cmd = {"action": "bots_despawn", "count": count}
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_behavior(args):
    """Change bot behavior"""
    cmd = {
        "action": "bots_behavior",
        "behavior": args.mode,
        "x": args.x,
        "y": args.y
    }
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_ramp(args):
    """Ramp bot count over time"""
    cmd = {
        "action": "bots_ramp",
        "target": args.target,
        "seconds": args.seconds
    }
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_stop(args):
    """Stop active ramp"""
    cmd = {"action": "bots_stop_ramp"}
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_status(args):
    """Get current status"""
    cmd = {"action": "bots_status"}
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_metrics(args):
    """Get performance metrics"""
    cmd = {"action": "bots_metrics"}
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

# ============== Visible Bot Commands ==============

def cmd_vspawn(args):
    """Spawn visible bots (clients can see these)"""
    cmd = {
        "action": "vbots_spawn",
        "count": args.count,
        "behavior": args.behavior,
        "x": args.x,
        "y": args.y
    }
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_vdespawn(args):
    """Despawn visible bots"""
    count = "all" if args.count == "all" else int(args.count)
    cmd = {"action": "vbots_despawn", "count": count}
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_vbehavior(args):
    """Change visible bot behavior"""
    cmd = {
        "action": "vbots_behavior",
        "behavior": args.mode,
        "x": args.x,
        "y": args.y
    }
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_vstatus(args):
    """Get visible bot status"""
    cmd = {"action": "vbots_status"}
    result = send_command(cmd, args.host, args.port)
    print(json.dumps(result, indent=2))

def cmd_watch(args):
    """Live metrics display"""
    print("Watching metrics (Ctrl+C to stop)...\n")
    try:
        while True:
            cmd = {"action": "bots_status"}
            result = send_command(cmd, args.host, args.port)

            if "error" in result:
                print(f"Error: {result['error']}")
                time.sleep(1)
                continue

            # Clear screen and show metrics
            print("\033[2J\033[H", end="")  # Clear screen
            print("=" * 60)
            print("ASHBANE BOT MANAGER - STRESS TEST MONITOR")
            print("=" * 60)
            invisible = result.get('invisible_bot_count', result.get('bot_count', 0))
            visible = result.get('visible_bot_count', 0)
            total_bots = result.get('bot_count', invisible + visible)
            print(f"  Invisible Bots:  {invisible}")
            print(f"  Visible Bots:    {visible}")
            print(f"  Total Bots:      {total_bots}")
            print(f"  Real Players:    {result.get('real_players', 0)}")
            print(f"  Total Players:   {result.get('total_players', 0)}")
            print("-" * 60)
            print(f"  FPS:             {result.get('fps', 0):.1f}")
            print(f"  Tick Rate:       {result.get('player_tick_rate', 0):.1f} Hz")
            print(f"  AOI Radius:      {result.get('aoi_radius', 0):.0f} px")
            print(f"  Intensity:       {result.get('intensity_name', 'Unknown')} ({result.get('intensity_level', 0)})")
            print("-" * 60)
            print(f"  Behavior:        {result.get('behavior', 'Unknown')}")
            print(f"  Ramp Active:     {result.get('ramp_active', False)}")
            if result.get('ramp_active'):
                print(f"  Ramp Target:     {result.get('ramp_target', 0)}")
            print("-" * 60)
            print(f"  Memory:          {result.get('memory_mb', 0):.1f} MB")
            print("=" * 60)
            print("\nPress Ctrl+C to stop")

            time.sleep(1)

    except KeyboardInterrupt:
        print("\nStopped watching.")

def main():
    parser = argparse.ArgumentParser(
        description="Control Ashbane stress test bots",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("--host", default=DEFAULT_HOST, help="Server host")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Server port")

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # spawn
    p_spawn = subparsers.add_parser("spawn", help="Spawn bots")
    p_spawn.add_argument("count", type=int, help="Number of bots to spawn")
    p_spawn.add_argument("behavior", nargs="?", default="idle",
                         choices=["idle", "wander", "cluster", "combat", "reinforce"],
                         help="Bot behavior mode")
    p_spawn.add_argument("x", type=float, nargs="?", default=0.0, help="Target X position")
    p_spawn.add_argument("y", type=float, nargs="?", default=0.0, help="Target Y position")
    p_spawn.set_defaults(func=cmd_spawn)

    # despawn
    p_despawn = subparsers.add_parser("despawn", help="Despawn bots")
    p_despawn.add_argument("count", help="Number of bots to despawn, or 'all'")
    p_despawn.set_defaults(func=cmd_despawn)

    # behavior
    p_behavior = subparsers.add_parser("behavior", help="Change bot behavior")
    p_behavior.add_argument("mode", choices=["idle", "wander", "cluster", "combat", "reinforce"],
                           help="Behavior mode")
    p_behavior.add_argument("x", type=float, nargs="?", default=0.0, help="Target X position")
    p_behavior.add_argument("y", type=float, nargs="?", default=0.0, help="Target Y position")
    p_behavior.set_defaults(func=cmd_behavior)

    # ramp
    p_ramp = subparsers.add_parser("ramp", help="Ramp bot count over time")
    p_ramp.add_argument("target", type=int, help="Target bot count")
    p_ramp.add_argument("seconds", type=float, help="Duration in seconds")
    p_ramp.set_defaults(func=cmd_ramp)

    # stop
    p_stop = subparsers.add_parser("stop", help="Stop active ramp")
    p_stop.set_defaults(func=cmd_stop)

    # status
    p_status = subparsers.add_parser("status", help="Get current status")
    p_status.set_defaults(func=cmd_status)

    # metrics
    p_metrics = subparsers.add_parser("metrics", help="Get performance metrics")
    p_metrics.set_defaults(func=cmd_metrics)

    # watch
    p_watch = subparsers.add_parser("watch", help="Live metrics display")
    p_watch.set_defaults(func=cmd_watch)

    # ============== Visible Bot Commands ==============

    # vspawn
    p_vspawn = subparsers.add_parser("vspawn", help="Spawn visible bots (clients can see)")
    p_vspawn.add_argument("count", type=int, help="Number of visible bots to spawn")
    p_vspawn.add_argument("behavior", nargs="?", default="wander",
                          choices=["idle", "wander", "cluster", "combat", "reinforce"],
                          help="Bot behavior mode")
    p_vspawn.add_argument("x", type=float, nargs="?", default=0.0, help="Target X position")
    p_vspawn.add_argument("y", type=float, nargs="?", default=0.0, help="Target Y position")
    p_vspawn.set_defaults(func=cmd_vspawn)

    # vdespawn
    p_vdespawn = subparsers.add_parser("vdespawn", help="Despawn visible bots")
    p_vdespawn.add_argument("count", help="Number of visible bots to despawn, or 'all'")
    p_vdespawn.set_defaults(func=cmd_vdespawn)

    # vbehavior
    p_vbehavior = subparsers.add_parser("vbehavior", help="Change visible bot behavior")
    p_vbehavior.add_argument("mode", choices=["idle", "wander", "cluster", "combat", "reinforce"],
                             help="Behavior mode")
    p_vbehavior.add_argument("x", type=float, nargs="?", default=0.0, help="Target X position")
    p_vbehavior.add_argument("y", type=float, nargs="?", default=0.0, help="Target Y position")
    p_vbehavior.set_defaults(func=cmd_vbehavior)

    # vstatus
    p_vstatus = subparsers.add_parser("vstatus", help="Get visible bot status")
    p_vstatus.set_defaults(func=cmd_vstatus)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    args.func(args)

if __name__ == "__main__":
    main()
