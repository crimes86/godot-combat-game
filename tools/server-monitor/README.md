# Ashbane Server Monitor Agent

Lightweight Python agent that collects system metrics and sends them to the Ashbane backend for monitoring.

## Features

- CPU usage (overall, per-core, load averages)
- Memory usage (RAM, swap)
- Disk usage (per mount point)
- Network I/O and listening ports
- Process list with resource consumption
- Game server detection (players, shard ID)

## Installation

### On the Game Server Droplet

1. Copy this directory to the game server:
   ```bash
   scp -r tools/server-monitor root@gameserver:/tmp/
   ```

2. SSH into the game server and run the installer:
   ```bash
   ssh root@gameserver
   cd /tmp/server-monitor
   sudo ./install.sh
   ```

3. Follow the prompts to configure:
   - Backend URL: `https://api.ashbane.net`
   - Server ID: A unique name (e.g., `gameserver-1`)
   - Server Secret: The `GAME_SERVER_SECRET` from your backend `.env`
   - Server Type: `gameserver`
   - Heartbeat Interval: `30` (seconds)

### Quick Install (Non-Interactive)

```bash
export ASHBANE_BACKEND_URL=https://api.ashbane.net
export ASHBANE_SERVER_ID=gameserver-1
export ASHBANE_SERVER_SECRET=your-secret-here
export ASHBANE_SERVER_TYPE=gameserver
export ASHBANE_HEARTBEAT_INTERVAL=30

sudo -E ./install.sh
```

## Managing the Service

```bash
# Check status
sudo systemctl status ashbane-monitor

# View logs
sudo journalctl -u ashbane-monitor -f

# Restart
sudo systemctl restart ashbane-monitor

# Stop
sudo systemctl stop ashbane-monitor

# Disable
sudo systemctl disable ashbane-monitor
```

## Configuration

Configuration is stored in `/opt/ashbane-monitor/monitor.env`:

```env
ASHBANE_BACKEND_URL=https://api.ashbane.net
ASHBANE_SERVER_ID=gameserver-1
ASHBANE_SERVER_SECRET=your-secret
ASHBANE_SERVER_TYPE=gameserver
ASHBANE_HEARTBEAT_INTERVAL=30
```

After editing, restart the service:
```bash
sudo systemctl restart ashbane-monitor
```

## Game Server Integration

The monitor can detect game-specific stats if the game server writes a status file:

**File:** `/tmp/ashbane-server-status.json`
```json
{
    "players_online": 32,
    "players_max": 50,
    "shard_id": "us-west-1",
    "version": "0.1.0"
}
```

This can be written by a GDScript autoload on the game server that updates periodically.

## Viewing Stats

Stats appear in the Ashbane admin dashboard at `/logs`:

1. Log in as admin
2. The "Server Infrastructure" section shows all monitored servers
3. Click a server card for detailed stats

## Troubleshooting

### Agent not starting
```bash
journalctl -u ashbane-monitor -n 50
```

### Can't connect to backend
- Check the backend URL is correct
- Verify the secret matches `GAME_SERVER_SECRET` on the backend
- Ensure the server can reach the backend (firewall, DNS)

### High CPU usage
The agent should use < 1% CPU. If higher:
- Increase `ASHBANE_HEARTBEAT_INTERVAL` to 60+ seconds
- Check for runaway processes on the system

## Uninstall

```bash
sudo systemctl stop ashbane-monitor
sudo systemctl disable ashbane-monitor
sudo rm /etc/systemd/system/ashbane-monitor.service
sudo rm -rf /opt/ashbane-monitor
sudo systemctl daemon-reload
```
