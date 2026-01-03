#!/usr/bin/env python3
"""
Ashbane Server Monitor Agent

Collects system metrics and sends them to the Ashbane backend for monitoring.
Designed to run as a systemd service on game server droplets.

Usage:
    python3 ashbane_monitor.py --backend-url https://api.ashbane.net --server-id gameserver-1 --secret YOUR_SECRET

Environment variables (alternative to CLI args):
    ASHBANE_BACKEND_URL - Backend API URL
    ASHBANE_SERVER_ID - Unique identifier for this server
    ASHBANE_SERVER_SECRET - Shared secret for authentication
    ASHBANE_SERVER_TYPE - Server type (default: gameserver)
    ASHBANE_HEARTBEAT_INTERVAL - Seconds between heartbeats (default: 30)
"""

import argparse
import json
import logging
import os
import signal
import socket
import sys
import time
from datetime import datetime
from typing import Any, Dict, List, Optional

try:
    import psutil
except ImportError:
    print("Error: psutil is required. Install with: pip3 install psutil")
    sys.exit(1)

try:
    import requests
except ImportError:
    print("Error: requests is required. Install with: pip3 install requests")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Agent version
AGENT_VERSION = "1.0.1"

# Global flag for graceful shutdown
running = True


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    global running
    logger.info(f"Received signal {signum}, shutting down...")
    running = False


def get_hostname() -> str:
    """Get the system hostname."""
    return socket.gethostname()


def get_cpu_stats() -> Dict[str, Any]:
    """Collect CPU statistics."""
    cpu_percent = psutil.cpu_percent(interval=0.5)
    cpu_count = psutil.cpu_count()
    cpu_freq = psutil.cpu_freq()

    # Load averages (Linux/Mac only)
    load_avg = (0, 0, 0)
    if hasattr(psutil, 'getloadavg'):
        try:
            load_avg = psutil.getloadavg()
        except (OSError, AttributeError):
            pass

    return {
        "cpu_percent": cpu_percent,
        "cpu_count": cpu_count,
        "cpu_freq_mhz": cpu_freq.current if cpu_freq else None,
        "load_avg_1m": load_avg[0],
        "load_avg_5m": load_avg[1],
        "load_avg_15m": load_avg[2],
    }


def get_memory_stats() -> Dict[str, Any]:
    """Collect memory statistics."""
    mem = psutil.virtual_memory()
    swap = psutil.swap_memory()

    return {
        "memory_total_mb": mem.total / (1024 ** 2),
        "memory_used_mb": mem.used / (1024 ** 2),
        "memory_available_mb": mem.available / (1024 ** 2),
        "memory_percent": mem.percent,
        "swap_total_mb": swap.total / (1024 ** 2),
        "swap_used_mb": swap.used / (1024 ** 2),
    }


def get_disk_stats() -> List[Dict[str, Any]]:
    """Collect disk statistics."""
    disks = []

    for partition in psutil.disk_partitions():
        # Skip special filesystems
        if partition.fstype in ('squashfs', 'tmpfs', 'devtmpfs'):
            continue
        if partition.mountpoint.startswith(('/snap', '/boot/efi')):
            continue

        try:
            usage = psutil.disk_usage(partition.mountpoint)
            disks.append({
                "mount": partition.mountpoint,
                "total_gb": usage.total / (1024 ** 3),
                "used_gb": usage.used / (1024 ** 3),
                "free_gb": usage.free / (1024 ** 3),
                "percent": usage.percent,
            })
        except (PermissionError, OSError):
            continue

    return disks


def get_network_stats() -> Dict[str, Any]:
    """Collect network statistics."""
    net_io = psutil.net_io_counters()

    # Get listening connections
    connections = []
    try:
        for conn in psutil.net_connections(kind='inet'):
            if conn.status == 'LISTEN':
                proc_name = ""
                try:
                    if conn.pid:
                        proc = psutil.Process(conn.pid)
                        proc_name = proc.name()
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass

                connections.append({
                    "local_port": conn.laddr.port if conn.laddr else 0,
                    "remote_addr": None,
                    "remote_port": None,
                    "status": conn.status,
                    "pid": conn.pid,
                    "process_name": proc_name,
                })
    except (psutil.AccessDenied, OSError) as e:
        logger.debug(f"Could not get network connections: {e}")

    return {
        "net_bytes_sent": net_io.bytes_sent,
        "net_bytes_recv": net_io.bytes_recv,
        "connections": connections,
    }


def get_process_stats() -> List[Dict[str, Any]]:
    """Collect top process statistics by CPU usage."""
    processes = []

    for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info', 'status', 'cmdline']):
        try:
            pinfo = proc.info
            mem_mb = pinfo['memory_info'].rss / (1024 ** 2) if pinfo['memory_info'] else 0

            # Get ports for this process
            proc_ports = []
            try:
                for conn in proc.connections(kind='inet'):
                    if conn.laddr:
                        proc_ports.append(conn.laddr.port)
            except (psutil.AccessDenied, psutil.NoSuchProcess):
                pass

            # Truncate cmdline
            cmdline = " ".join(pinfo['cmdline'][:5]) if pinfo['cmdline'] else ""

            processes.append({
                "pid": pinfo['pid'],
                "name": pinfo['name'],
                "cpu_percent": pinfo['cpu_percent'] or 0,
                "memory_mb": mem_mb,
                "status": pinfo['status'],
                "ports": proc_ports[:5],  # Limit to 5 ports
                "cmdline": cmdline[:200],  # Truncate to 200 chars
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    # Sort by CPU and take top 15
    processes.sort(key=lambda x: x['cpu_percent'], reverse=True)
    return processes[:15]


def get_uptime() -> float:
    """Get system uptime in seconds."""
    return time.time() - psutil.boot_time()


def get_game_server_stats() -> Dict[str, Any]:
    """
    Get game-specific stats by checking for Godot processes.

    This looks for running Godot server processes and extracts
    player counts if available (requires the game to expose this somehow).
    Also tracks individual game server instances with their uptimes.
    """
    game_stats = {
        "players_online": None,
        "players_max": None,
        "shard_id": None,
        "game_version": None,
        "game_instances": [],  # List of running game server instances
    }

    now = time.time()

    # Look for all Godot server processes
    for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'memory_info', 'create_time']):
        try:
            pinfo = proc.info
            cmdline = pinfo.get('cmdline', [])
            cmdline_str = " ".join(cmdline) if cmdline else ""
            proc_name = pinfo.get('name', '').lower()

            # Check if this is a Godot server (binary name or --server flag)
            is_game_server = (
                'godot' in proc_name or
                'ashbane' in proc_name or
                '--server' in cmdline_str
            )

            if is_game_server:
                # Extract shard from cmdline
                shard_id = None
                port = None
                if '--shard' in cmdline_str:
                    for i, arg in enumerate(cmdline):
                        if arg == '--shard' and i + 1 < len(cmdline):
                            shard_id = cmdline[i + 1]
                            break
                if '--port' in cmdline_str:
                    for i, arg in enumerate(cmdline):
                        if arg == '--port' and i + 1 < len(cmdline):
                            try:
                                port = int(cmdline[i + 1])
                            except ValueError:
                                pass
                            break

                # Get process ports
                proc_ports = []
                try:
                    for conn in proc.connections(kind='inet'):
                        if conn.laddr and conn.status == 'LISTEN':
                            proc_ports.append(conn.laddr.port)
                except (psutil.AccessDenied, psutil.NoSuchProcess):
                    pass

                # Calculate process uptime
                create_time = pinfo.get('create_time', now)
                instance_uptime = now - create_time

                # Memory
                mem_info = pinfo.get('memory_info')
                memory_mb = mem_info.rss / (1024 ** 2) if mem_info else 0

                # Get accurate CPU - must call with interval for real measurement
                # process_iter's cpu_percent returns stale/cached values
                cpu_pct = proc.cpu_percent(interval=0.1)

                instance = {
                    "pid": pinfo['pid'],
                    "name": pinfo.get('name', 'unknown'),
                    "shard_id": shard_id,
                    "port": port or (proc_ports[0] if proc_ports else None),
                    "ports": proc_ports,
                    "uptime_seconds": instance_uptime,
                    "cpu_percent": cpu_pct,
                    "memory_mb": memory_mb,
                    "cmdline": cmdline_str[:300],
                }

                game_stats['game_instances'].append(instance)

                # Use first instance's shard as the primary (for backwards compat)
                if game_stats['shard_id'] is None and shard_id:
                    game_stats['shard_id'] = shard_id

        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    # Sort instances by uptime (oldest first)
    game_stats['game_instances'].sort(key=lambda x: x['uptime_seconds'], reverse=True)

    # Try to read status file if it exists (game server can write this)
    status_file = "/tmp/ashbane-server-status.json"
    if os.path.exists(status_file):
        try:
            with open(status_file, 'r') as f:
                status_data = json.load(f)
                game_stats['players_online'] = status_data.get('players_online')
                game_stats['players_max'] = status_data.get('players_max', 50)
                game_stats['shard_id'] = status_data.get('shard_id') or game_stats['shard_id']
                game_stats['game_version'] = status_data.get('version')
        except (json.JSONDecodeError, IOError):
            pass

    return game_stats


def collect_all_stats(server_id: str, server_type: str, agent_start_time: float) -> Dict[str, Any]:
    """Collect all system statistics."""
    stats = {
        "server_id": server_id,
        "server_type": server_type,
        "hostname": get_hostname(),
        "agent_version": AGENT_VERSION,
        "uptime_seconds": get_uptime(),
        "agent_uptime_seconds": time.time() - agent_start_time,
    }

    # Collect all metrics
    stats.update(get_cpu_stats())
    stats.update(get_memory_stats())
    stats["disks"] = get_disk_stats()
    stats.update(get_network_stats())
    stats["processes"] = get_process_stats()

    # Game server specific
    if server_type == "gameserver":
        stats.update(get_game_server_stats())

    return stats


def send_heartbeat(backend_url: str, secret: str, stats: Dict[str, Any]) -> bool:
    """Send heartbeat to backend."""
    url = f"{backend_url.rstrip('/')}/api/server-stats/heartbeat"
    headers = {
        "Authorization": f"Bearer {secret}",
        "Content-Type": "application/json",
    }

    try:
        response = requests.post(url, json=stats, headers=headers, timeout=10)

        if response.status_code == 200:
            logger.debug(f"Heartbeat sent successfully")
            return True
        else:
            logger.warning(f"Heartbeat failed: {response.status_code} - {response.text[:200]}")
            return False

    except requests.exceptions.Timeout:
        logger.warning("Heartbeat timeout")
        return False
    except requests.exceptions.ConnectionError as e:
        logger.warning(f"Heartbeat connection error: {e}")
        return False
    except Exception as e:
        logger.error(f"Heartbeat error: {e}")
        return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Ashbane Server Monitor Agent")
    parser.add_argument(
        "--backend-url",
        default=os.environ.get("ASHBANE_BACKEND_URL", "https://api.ashbane.net"),
        help="Ashbane backend URL"
    )
    parser.add_argument(
        "--server-id",
        default=os.environ.get("ASHBANE_SERVER_ID", socket.gethostname()),
        help="Unique server identifier"
    )
    parser.add_argument(
        "--secret",
        default=os.environ.get("ASHBANE_SERVER_SECRET", ""),
        help="Shared secret for authentication"
    )
    parser.add_argument(
        "--server-type",
        default=os.environ.get("ASHBANE_SERVER_TYPE", "gameserver"),
        choices=["gameserver", "backend", "worker"],
        help="Type of server"
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=int(os.environ.get("ASHBANE_HEARTBEAT_INTERVAL", "30")),
        help="Heartbeat interval in seconds"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug logging"
    )

    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    if not args.secret:
        logger.error("Server secret is required. Set --secret or ASHBANE_SERVER_SECRET")
        sys.exit(1)

    # Set up signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    logger.info("=" * 60)
    logger.info(f"Ashbane Server Monitor Agent v{AGENT_VERSION}")
    logger.info("=" * 60)
    logger.info(f"  Server ID: {args.server_id}")
    logger.info(f"  Server Type: {args.server_type}")
    logger.info(f"  Backend URL: {args.backend_url}")
    logger.info(f"  Heartbeat Interval: {args.interval}s")
    logger.info("=" * 60)

    agent_start_time = time.time()
    consecutive_failures = 0
    max_backoff = 300  # Max 5 minutes between retries on failure

    while running:
        try:
            # Collect stats
            stats = collect_all_stats(args.server_id, args.server_type, agent_start_time)

            # Send heartbeat
            if send_heartbeat(args.backend_url, args.secret, stats):
                consecutive_failures = 0
            else:
                consecutive_failures += 1
                if consecutive_failures >= 5:
                    logger.warning(f"5 consecutive heartbeat failures, backing off...")

            # Calculate sleep time with backoff on failures
            sleep_time = args.interval
            if consecutive_failures > 0:
                backoff = min(args.interval * (2 ** consecutive_failures), max_backoff)
                sleep_time = backoff
                logger.debug(f"Backoff sleep: {sleep_time}s")

            # Sleep in small increments to allow graceful shutdown
            for _ in range(int(sleep_time)):
                if not running:
                    break
                time.sleep(1)

        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            time.sleep(10)

    logger.info("Agent stopped")


if __name__ == "__main__":
    main()
