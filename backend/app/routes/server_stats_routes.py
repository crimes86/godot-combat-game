"""
Server statistics routes for monitoring game servers and backend health.

Receives heartbeats from remote monitoring agents and provides
dashboard endpoints for system health visualization.
"""
from fastapi import APIRouter, Depends, HTTPException, Request, Header
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session as DbSession
from typing import Optional, Callable, List, Dict, Any
from datetime import datetime, timedelta
from pydantic import BaseModel, Field
import logging
import os
import psutil
import time

from app.models import User
from app.database import SessionLocal

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/server-stats", tags=["server-stats"])

# Injected from main app
_get_current_user_func: Callable = None

# Configuration
GAME_SERVER_SECRET = os.environ.get("GAME_SERVER_SECRET", "change-me-in-production")
HEARTBEAT_STALE_SECONDS = 120  # Mark as stale if no heartbeat for 2 minutes
HEARTBEAT_DEAD_SECONDS = 300   # Mark as dead if no heartbeat for 5 minutes

# In-memory storage for server stats (server_id -> stats)
_server_stats: Dict[str, Dict[str, Any]] = {}
_backend_stats_cache: Dict[str, Any] = {}
_backend_stats_cache_time: float = 0
BACKEND_STATS_CACHE_TTL = 5  # Cache local stats for 5 seconds


# ═══════════════════════════════════════════════════════════════════════════
# REQUEST/RESPONSE MODELS
# ═══════════════════════════════════════════════════════════════════════════

class ProcessInfo(BaseModel):
    pid: int
    name: str
    cpu_percent: float = 0
    memory_mb: float = 0
    status: str = "unknown"
    ports: List[int] = []
    cmdline: str = ""


class GameInstanceInfo(BaseModel):
    pid: int
    name: str = "unknown"
    shard_id: Optional[str] = None
    port: Optional[int] = None
    ports: List[int] = []
    uptime_seconds: float = 0
    cpu_percent: float = 0
    memory_mb: float = 0
    cmdline: str = ""


class NetworkConnection(BaseModel):
    local_port: int
    remote_addr: Optional[str] = None
    remote_port: Optional[int] = None
    status: str
    pid: Optional[int] = None
    process_name: Optional[str] = None


class DiskInfo(BaseModel):
    mount: str
    total_gb: float
    used_gb: float
    free_gb: float
    percent: float


class HeartbeatRequest(BaseModel):
    server_id: str = Field(..., description="Unique identifier for this server (e.g., 'gameserver-1', 'backend')")
    server_type: str = Field(..., description="Type of server: 'gameserver', 'backend', etc.")
    hostname: str = ""

    # CPU metrics
    cpu_percent: float = 0
    cpu_count: int = 1
    cpu_freq_mhz: Optional[float] = None
    load_avg_1m: Optional[float] = None
    load_avg_5m: Optional[float] = None
    load_avg_15m: Optional[float] = None

    # Memory metrics
    memory_total_mb: float = 0
    memory_used_mb: float = 0
    memory_available_mb: float = 0
    memory_percent: float = 0
    swap_total_mb: float = 0
    swap_used_mb: float = 0

    # Disk metrics
    disks: List[DiskInfo] = []

    # Network metrics
    net_bytes_sent: int = 0
    net_bytes_recv: int = 0
    connections: List[NetworkConnection] = []

    # Process list (top consumers)
    processes: List[ProcessInfo] = []

    # Uptime
    uptime_seconds: float = 0
    agent_uptime_seconds: float = 0

    # Optional game-specific metrics
    players_online: Optional[int] = None
    players_max: Optional[int] = None
    shard_id: Optional[str] = None
    game_version: Optional[str] = None
    game_instances: List[GameInstanceInfo] = []  # Running game server instances

    # Agent metadata
    agent_version: str = "1.0.0"


class HeartbeatResponse(BaseModel):
    status: str
    server_id: str
    received_at: str


class ServerStatus(BaseModel):
    server_id: str
    server_type: str
    hostname: str
    status: str  # "online", "stale", "offline"
    last_heartbeat: Optional[str]
    seconds_since_heartbeat: Optional[float]

    # Metrics (from last heartbeat)
    cpu_percent: float = 0
    memory_percent: float = 0
    memory_used_mb: float = 0
    memory_total_mb: float = 0
    disk_percent: float = 0

    # Game-specific
    players_online: Optional[int] = None
    players_max: Optional[int] = None
    shard_id: Optional[str] = None
    game_instances_count: int = 0  # Number of running game server instances

    # Full data available via detail endpoint
    uptime_seconds: float = 0


# ═══════════════════════════════════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════

def get_db():
    """Database session dependency."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user_dep(request: Request, db: DbSession = Depends(get_db)):
    """Get current user - wraps the main app's auth logic."""
    if _get_current_user_func is None:
        raise HTTPException(status_code=500, detail="Server stats routes not initialized")
    return _get_current_user_func(request, db)


def require_admin(user: User):
    """Verify user is an admin."""
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")


def verify_server_secret(authorization: Optional[str] = Header(None)):
    """Verify the game server secret for heartbeat endpoints."""
    if not authorization:
        raise HTTPException(status_code=401, detail="Authorization header required")

    # Support both "Bearer <token>" and raw token
    token = authorization
    if authorization.lower().startswith("bearer "):
        token = authorization[7:]

    if token != GAME_SERVER_SECRET:
        logger.warning(f"Invalid server secret attempted")
        raise HTTPException(status_code=403, detail="Invalid server secret")

    return True


def init_server_stats_routes(get_current_user: Callable):
    """Initialize server stats routes with dependencies from main app."""
    global _get_current_user_func
    _get_current_user_func = get_current_user


# ═══════════════════════════════════════════════════════════════════════════
# LOCAL STATS COLLECTION
# ═══════════════════════════════════════════════════════════════════════════

def collect_local_stats() -> Dict[str, Any]:
    """Collect system stats for the local (backend) server."""
    global _backend_stats_cache, _backend_stats_cache_time

    now = time.time()
    if now - _backend_stats_cache_time < BACKEND_STATS_CACHE_TTL:
        return _backend_stats_cache

    try:
        # CPU
        cpu_percent = psutil.cpu_percent(interval=0.1)
        cpu_count = psutil.cpu_count()
        cpu_freq = psutil.cpu_freq()
        load_avg = psutil.getloadavg() if hasattr(psutil, 'getloadavg') else (0, 0, 0)

        # Memory
        mem = psutil.virtual_memory()
        swap = psutil.swap_memory()

        # Disk
        disks = []
        for part in psutil.disk_partitions():
            try:
                usage = psutil.disk_usage(part.mountpoint)
                disks.append({
                    "mount": part.mountpoint,
                    "total_gb": usage.total / (1024**3),
                    "used_gb": usage.used / (1024**3),
                    "free_gb": usage.free / (1024**3),
                    "percent": usage.percent
                })
            except (PermissionError, OSError):
                continue

        # Network
        net_io = psutil.net_io_counters()

        # Connections (listening ports)
        connections = []
        for conn in psutil.net_connections(kind='inet'):
            if conn.status == 'LISTEN':
                proc_name = ""
                try:
                    if conn.pid:
                        proc_name = psutil.Process(conn.pid).name()
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass

                connections.append({
                    "local_port": conn.laddr.port if conn.laddr else 0,
                    "remote_addr": conn.raddr.ip if conn.raddr else None,
                    "remote_port": conn.raddr.port if conn.raddr else None,
                    "status": conn.status,
                    "pid": conn.pid,
                    "process_name": proc_name
                })

        # Top processes by CPU/memory
        processes = []
        for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info', 'status', 'cmdline']):
            try:
                pinfo = proc.info
                mem_mb = pinfo['memory_info'].rss / (1024**1024) if pinfo['memory_info'] else 0

                # Get ports for this process
                proc_ports = []
                try:
                    for conn in proc.connections(kind='inet'):
                        if conn.laddr:
                            proc_ports.append(conn.laddr.port)
                except (psutil.AccessDenied, psutil.NoSuchProcess):
                    pass

                cmdline = " ".join(pinfo['cmdline'][:5]) if pinfo['cmdline'] else ""

                processes.append({
                    "pid": pinfo['pid'],
                    "name": pinfo['name'],
                    "cpu_percent": pinfo['cpu_percent'] or 0,
                    "memory_mb": mem_mb,
                    "status": pinfo['status'],
                    "ports": proc_ports[:5],  # Limit ports
                    "cmdline": cmdline[:200]  # Truncate
                })
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue

        # Sort by CPU, take top 15
        processes.sort(key=lambda x: x['cpu_percent'], reverse=True)
        processes = processes[:15]

        # Uptime
        boot_time = psutil.boot_time()
        uptime = time.time() - boot_time

        stats = {
            "server_id": "backend",
            "server_type": "backend",
            "hostname": os.uname().nodename if hasattr(os, 'uname') else "backend",
            "timestamp": datetime.utcnow().isoformat(),
            "cpu_percent": cpu_percent,
            "cpu_count": cpu_count,
            "cpu_freq_mhz": cpu_freq.current if cpu_freq else None,
            "load_avg_1m": load_avg[0],
            "load_avg_5m": load_avg[1],
            "load_avg_15m": load_avg[2],
            "memory_total_mb": mem.total / (1024**2),
            "memory_used_mb": mem.used / (1024**2),
            "memory_available_mb": mem.available / (1024**2),
            "memory_percent": mem.percent,
            "swap_total_mb": swap.total / (1024**2),
            "swap_used_mb": swap.used / (1024**2),
            "disks": disks,
            "net_bytes_sent": net_io.bytes_sent,
            "net_bytes_recv": net_io.bytes_recv,
            "connections": connections,
            "processes": processes,
            "uptime_seconds": uptime,
        }

        _backend_stats_cache = stats
        _backend_stats_cache_time = now

        return stats

    except Exception as e:
        logger.error(f"Error collecting local stats: {e}")
        return {}


# ═══════════════════════════════════════════════════════════════════════════
# ROUTES
# ═══════════════════════════════════════════════════════════════════════════

@router.post("/heartbeat", response_model=HeartbeatResponse)
async def receive_heartbeat(
    request: Request,
    heartbeat: HeartbeatRequest,
    _: bool = Depends(verify_server_secret)
):
    """
    Receive heartbeat from a monitoring agent.

    Game servers and other monitored hosts push stats here periodically.
    Authenticated via GAME_SERVER_SECRET in Authorization header.
    """
    now = datetime.utcnow()

    # Store the heartbeat data
    _server_stats[heartbeat.server_id] = {
        "server_id": heartbeat.server_id,
        "server_type": heartbeat.server_type,
        "hostname": heartbeat.hostname,
        "last_heartbeat": now.isoformat(),
        "last_heartbeat_ts": time.time(),
        "data": heartbeat.dict()
    }

    logger.info(f"Heartbeat received from {heartbeat.server_id} ({heartbeat.server_type})")

    return HeartbeatResponse(
        status="ok",
        server_id=heartbeat.server_id,
        received_at=now.isoformat()
    )


@router.get("/servers", response_model=List[ServerStatus])
async def list_servers(
    current_user: User = Depends(get_current_user_dep)
):
    """
    List all monitored servers with their current status.

    Admin only.
    """
    require_admin(current_user)

    now = time.time()
    servers = []

    # Add backend (local) stats
    local_stats = collect_local_stats()
    if local_stats:
        primary_disk = local_stats.get("disks", [{}])[0] if local_stats.get("disks") else {}
        servers.append(ServerStatus(
            server_id="backend",
            server_type="backend",
            hostname=local_stats.get("hostname", "backend"),
            status="online",
            last_heartbeat=local_stats.get("timestamp"),
            seconds_since_heartbeat=0,
            cpu_percent=local_stats.get("cpu_percent", 0),
            memory_percent=local_stats.get("memory_percent", 0),
            memory_used_mb=local_stats.get("memory_used_mb", 0),
            memory_total_mb=local_stats.get("memory_total_mb", 0),
            disk_percent=primary_disk.get("percent", 0),
            uptime_seconds=local_stats.get("uptime_seconds", 0)
        ))

    # Add remote servers from heartbeats
    for server_id, stats in _server_stats.items():
        last_ts = stats.get("last_heartbeat_ts", 0)
        seconds_ago = now - last_ts

        # Determine status
        if seconds_ago < HEARTBEAT_STALE_SECONDS:
            status = "online"
        elif seconds_ago < HEARTBEAT_DEAD_SECONDS:
            status = "stale"
        else:
            status = "offline"

        data = stats.get("data", {})
        primary_disk = data.get("disks", [{}])[0] if data.get("disks") else {}

        servers.append(ServerStatus(
            server_id=server_id,
            server_type=stats.get("server_type", "unknown"),
            hostname=stats.get("hostname", ""),
            status=status,
            last_heartbeat=stats.get("last_heartbeat"),
            seconds_since_heartbeat=seconds_ago,
            cpu_percent=data.get("cpu_percent", 0),
            memory_percent=data.get("memory_percent", 0),
            memory_used_mb=data.get("memory_used_mb", 0),
            memory_total_mb=data.get("memory_total_mb", 0),
            disk_percent=primary_disk.get("percent", 0),
            players_online=data.get("players_online"),
            players_max=data.get("players_max"),
            shard_id=data.get("shard_id"),
            game_instances_count=len(data.get("game_instances", [])),
            uptime_seconds=data.get("uptime_seconds", 0)
        ))

    return servers


@router.get("/servers/{server_id}")
async def get_server_detail(
    server_id: str,
    current_user: User = Depends(get_current_user_dep)
):
    """
    Get detailed stats for a specific server.

    Admin only.
    """
    require_admin(current_user)

    # Handle backend (local) server
    if server_id == "backend":
        return collect_local_stats()

    # Handle remote servers
    if server_id not in _server_stats:
        raise HTTPException(status_code=404, detail=f"Server '{server_id}' not found")

    stats = _server_stats[server_id]
    now = time.time()
    seconds_ago = now - stats.get("last_heartbeat_ts", 0)

    return {
        **stats.get("data", {}),
        "status": "online" if seconds_ago < HEARTBEAT_STALE_SECONDS else ("stale" if seconds_ago < HEARTBEAT_DEAD_SECONDS else "offline"),
        "seconds_since_heartbeat": seconds_ago
    }


@router.get("")
async def get_all_stats(
    current_user: User = Depends(get_current_user_dep)
):
    """
    Get summary stats for all servers (for dashboard).

    Admin only.
    """
    require_admin(current_user)

    now = time.time()

    # Collect all server statuses
    servers = []

    # Backend
    local = collect_local_stats()
    if local:
        servers.append({
            "server_id": "backend",
            "server_type": "backend",
            "status": "online",
            "cpu_percent": local.get("cpu_percent", 0),
            "memory_percent": local.get("memory_percent", 0),
            "disk_percent": local.get("disks", [{}])[0].get("percent", 0) if local.get("disks") else 0
        })

    # Remote servers
    online_count = 1 if local else 0  # Backend counts as online
    total_players = 0

    for server_id, stats in _server_stats.items():
        last_ts = stats.get("last_heartbeat_ts", 0)
        seconds_ago = now - last_ts
        data = stats.get("data", {})

        status = "online" if seconds_ago < HEARTBEAT_STALE_SECONDS else ("stale" if seconds_ago < HEARTBEAT_DEAD_SECONDS else "offline")

        if status == "online":
            online_count += 1

        if data.get("players_online"):
            total_players += data.get("players_online", 0)

        servers.append({
            "server_id": server_id,
            "server_type": stats.get("server_type", "unknown"),
            "status": status,
            "cpu_percent": data.get("cpu_percent", 0),
            "memory_percent": data.get("memory_percent", 0),
            "disk_percent": data.get("disks", [{}])[0].get("percent", 0) if data.get("disks") else 0,
            "players_online": data.get("players_online"),
            "seconds_since_heartbeat": seconds_ago
        })

    return {
        "summary": {
            "total_servers": len(servers),
            "online_servers": online_count,
            "total_players": total_players,
        },
        "servers": servers
    }
