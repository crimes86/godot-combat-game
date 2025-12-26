"""
Scanner Detection Service

Detects and logs IPs exhibiting vulnerability scanning behavior.
Tracks suspicious IPs in the database for later investigation.
"""

import logging
from datetime import datetime, timedelta
from collections import defaultdict
from typing import Optional
from sqlalchemy.orm import Session

from app.models import SuspiciousIP

logger = logging.getLogger(__name__)

# In-memory tracker for rapid 404s (before committing to DB)
# Format: {ip: [(timestamp, path), ...]}
_ip_tracker: dict[str, list[tuple[datetime, str]]] = defaultdict(list)

# Known attack paths that indicate scanning
ATTACK_PATHS = {
    '/wp-admin', '/wp-content', '/wp-includes', '/wordpress',
    '/phpmyadmin', '/pma', '/mysql', '/adminer',
    '/admin', '/administrator', '/login.php', '/admin.php',
    '/.env', '/.git', '/.svn', '/config.php', '/config.json',
    '/actuator', '/swagger', '/api-docs', '/openapi.json',
    '/solr', '/jenkins', '/hudson', '/manager',
    '/cgi-bin', '/scripts', '/shell', '/cmd',
    '/phpinfo', '/info.php', '/test.php',
    '/backup', '/dump', '/db', '/database',
    '/.aws', '/.ssh', '/id_rsa',
    '/nifi', '/ignite', '/sap', '/ScadaBR',
}

# Thresholds
MAX_404S_PER_MINUTE = 5  # More than this = scanner
TRACKER_CLEANUP_SECONDS = 120  # Keep tracking data for 2 minutes


def _cleanup_old_entries(ip: str) -> None:
    """Remove entries older than cleanup window."""
    cutoff = datetime.utcnow() - timedelta(seconds=TRACKER_CLEANUP_SECONDS)
    _ip_tracker[ip] = [(ts, path) for ts, path in _ip_tracker[ip] if ts > cutoff]
    if not _ip_tracker[ip]:
        del _ip_tracker[ip]


def is_attack_path(path: str) -> bool:
    """Check if path matches known attack patterns."""
    path_lower = path.lower()
    for attack_path in ATTACK_PATHS:
        if attack_path in path_lower:
            return True
    return False


def record_404(ip: str, path: str, user_agent: Optional[str], db: Session) -> bool:
    """
    Record a 404 hit and check if IP should be flagged as suspicious.

    Returns True if this IP was flagged as suspicious.
    """
    # Skip localhost/internal IPs
    if ip in ('127.0.0.1', '::1', 'localhost'):
        return False

    now = datetime.utcnow()

    # Track this 404
    _ip_tracker[ip].append((now, path))
    _cleanup_old_entries(ip)

    # Check if this is a known attack path
    is_attack = is_attack_path(path)

    # Count recent 404s
    one_minute_ago = now - timedelta(minutes=1)
    recent_hits = [(ts, p) for ts, p in _ip_tracker[ip] if ts > one_minute_ago]

    # Determine if suspicious
    is_suspicious = False
    detection_type = None
    threat_level = 'low'

    if len(recent_hits) >= MAX_404S_PER_MINUTE:
        is_suspicious = True
        detection_type = 'scanner'
        threat_level = 'medium'
    elif is_attack:
        is_suspicious = True
        detection_type = 'scanner'
        threat_level = 'low'

    if is_suspicious:
        _log_suspicious_ip(ip, detection_type, threat_level,
                          [p for _, p in recent_hits], user_agent, db)
        return True

    return False


def _log_suspicious_ip(
    ip: str,
    detection_type: str,
    threat_level: str,
    paths: list[str],
    user_agent: Optional[str],
    db: Session
) -> None:
    """Log or update suspicious IP in database."""
    try:
        # Check if we already have this IP
        existing = db.query(SuspiciousIP).filter(
            SuspiciousIP.ip_address == ip
        ).first()

        if existing:
            # Update existing record
            existing.hit_count += 1
            existing.last_seen = datetime.utcnow()

            # Update threat level if higher
            levels = {'low': 1, 'medium': 2, 'high': 3}
            if levels.get(threat_level, 0) > levels.get(existing.threat_level, 0):
                existing.threat_level = threat_level

            # Append new paths (keep last 50)
            current_paths = existing.paths_hit or []
            new_paths = list(set(current_paths + paths))[-50:]
            existing.paths_hit = new_paths

            # Track user agents
            current_agents = existing.user_agents or []
            if user_agent and user_agent not in current_agents:
                existing.user_agents = (current_agents + [user_agent])[-10:]

            logger.warning(f"[Scanner] Updated suspicious IP {ip}: {existing.hit_count} hits, level={threat_level}")
        else:
            # Create new record
            suspicious = SuspiciousIP(
                ip_address=ip,
                detection_type=detection_type,
                threat_level=threat_level,
                hit_count=1,
                paths_hit=paths[:50],
                user_agents=[user_agent] if user_agent else [],
            )
            db.add(suspicious)
            logger.warning(f"[Scanner] New suspicious IP detected: {ip} ({detection_type}, level={threat_level})")

        db.commit()

    except Exception as e:
        logger.error(f"[Scanner] Failed to log suspicious IP {ip}: {e}")
        db.rollback()


def get_suspicious_ips(db: Session, limit: int = 100) -> list[SuspiciousIP]:
    """Get recent suspicious IPs for review."""
    return db.query(SuspiciousIP)\
        .order_by(SuspiciousIP.last_seen.desc())\
        .limit(limit)\
        .all()


def get_ip_stats(db: Session) -> dict:
    """Get summary stats for suspicious IPs."""
    from sqlalchemy import func

    total = db.query(func.count(SuspiciousIP.id)).scalar()
    high_threat = db.query(func.count(SuspiciousIP.id))\
        .filter(SuspiciousIP.threat_level == 'high').scalar()
    blocked = db.query(func.count(SuspiciousIP.id))\
        .filter(SuspiciousIP.is_blocked == True).scalar()

    return {
        'total_suspicious_ips': total,
        'high_threat_count': high_threat,
        'blocked_count': blocked,
    }
