#!/bin/bash
#
# Ashbane Server Monitor - Installation Script
#
# This script installs the monitoring agent on a server.
# Run with sudo: sudo ./install.sh
#
# Prerequisites:
#   - Python 3.8+
#   - pip3
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

INSTALL_DIR="/opt/ashbane-monitor"
SERVICE_NAME="ashbane-monitor"

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  Ashbane Server Monitor Installer${NC}"
echo -e "${GREEN}======================================${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo ./install.sh)${NC}"
    exit 1
fi

# Check Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is required but not installed.${NC}"
    echo "Install with: apt install python3 python3-pip"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
echo -e "Found Python ${PYTHON_VERSION}"

# Get configuration from user or environment
echo
echo -e "${YELLOW}Configuration:${NC}"

# Backend URL
if [ -z "$ASHBANE_BACKEND_URL" ]; then
    read -p "Backend URL [https://api.ashbane.net]: " BACKEND_URL
    BACKEND_URL=${BACKEND_URL:-https://api.ashbane.net}
else
    BACKEND_URL=$ASHBANE_BACKEND_URL
    echo "Backend URL: $BACKEND_URL (from env)"
fi

# Server ID
DEFAULT_SERVER_ID=$(hostname)
if [ -z "$ASHBANE_SERVER_ID" ]; then
    read -p "Server ID [$DEFAULT_SERVER_ID]: " SERVER_ID
    SERVER_ID=${SERVER_ID:-$DEFAULT_SERVER_ID}
else
    SERVER_ID=$ASHBANE_SERVER_ID
    echo "Server ID: $SERVER_ID (from env)"
fi

# Server Secret
if [ -z "$ASHBANE_SERVER_SECRET" ]; then
    read -sp "Server Secret: " SERVER_SECRET
    echo
    if [ -z "$SERVER_SECRET" ]; then
        echo -e "${RED}Error: Server secret is required.${NC}"
        exit 1
    fi
else
    SERVER_SECRET=$ASHBANE_SERVER_SECRET
    echo "Server Secret: ******* (from env)"
fi

# Server Type
if [ -z "$ASHBANE_SERVER_TYPE" ]; then
    read -p "Server Type [gameserver/backend/worker] (gameserver): " SERVER_TYPE
    SERVER_TYPE=${SERVER_TYPE:-gameserver}
else
    SERVER_TYPE=$ASHBANE_SERVER_TYPE
    echo "Server Type: $SERVER_TYPE (from env)"
fi

# Heartbeat interval
if [ -z "$ASHBANE_HEARTBEAT_INTERVAL" ]; then
    read -p "Heartbeat Interval in seconds [30]: " HEARTBEAT_INTERVAL
    HEARTBEAT_INTERVAL=${HEARTBEAT_INTERVAL:-30}
else
    HEARTBEAT_INTERVAL=$ASHBANE_HEARTBEAT_INTERVAL
    echo "Heartbeat Interval: $HEARTBEAT_INTERVAL (from env)"
fi

echo
echo -e "${GREEN}Installing...${NC}"

# Create install directory
mkdir -p $INSTALL_DIR
echo "Created $INSTALL_DIR"

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install psutil requests --quiet

# Copy the monitor script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/ashbane_monitor.py" $INSTALL_DIR/
chmod +x $INSTALL_DIR/ashbane_monitor.py
echo "Copied monitor script"

# Create environment file
cat > $INSTALL_DIR/monitor.env << EOF
# Ashbane Server Monitor Configuration
# Generated: $(date)

ASHBANE_BACKEND_URL=$BACKEND_URL
ASHBANE_SERVER_ID=$SERVER_ID
ASHBANE_SERVER_SECRET=$SERVER_SECRET
ASHBANE_SERVER_TYPE=$SERVER_TYPE
ASHBANE_HEARTBEAT_INTERVAL=$HEARTBEAT_INTERVAL
EOF

chmod 600 $INSTALL_DIR/monitor.env
echo "Created configuration file"

# Install systemd service
cp "$SCRIPT_DIR/ashbane-monitor.service" /etc/systemd/system/
systemctl daemon-reload
echo "Installed systemd service"

# Enable and start the service
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo "Commands:"
echo "  sudo systemctl status $SERVICE_NAME   # Check status"
echo "  sudo systemctl restart $SERVICE_NAME  # Restart"
echo "  sudo journalctl -u $SERVICE_NAME -f   # View logs"
echo
echo "Configuration: $INSTALL_DIR/monitor.env"
echo

# Show current status
echo -e "${YELLOW}Current Status:${NC}"
systemctl status $SERVICE_NAME --no-pager || true
