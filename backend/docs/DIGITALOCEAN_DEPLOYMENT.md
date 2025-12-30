# Digital Ocean Deployment Guide

Deploy the Ashbane backend (FastAPI) to a Digital Ocean Droplet with PostgreSQL and Base Sepolia testnet.

---

## Prerequisites

Before starting:
- [ ] Digital Ocean account with payment method
- [ ] SSH key added to Digital Ocean (Settings > Security)
- [ ] Domain name (optional, but recommended for SSL)
- [ ] Steam API key from https://steamcommunity.com/dev/apikey
- [ ] Battle.net credentials from https://develop.battle.net (if using)

---

## 1. Create Droplet

### Digital Ocean Dashboard

1. Click **Create > Droplets**
2. Choose:
   - **Region**: Closest to your players
   - **Image**: Ubuntu 22.04 (LTS) x64
   - **Size**: Basic > Regular > **$12/mo (2GB RAM, 1 vCPU)** minimum
   - **Authentication**: SSH Key (select your key)
   - **Hostname**: `Ashbane-backend` or similar

3. Click **Create Droplet**
4. Note the IP address once created

### Initial SSH Connection

```bash
ssh root@YOUR_DROPLET_IP
```

---

## 2. Server Setup

### System Updates

```bash
apt update && apt upgrade -y
apt install -y software-properties-common curl git
```

### Create Application User

```bash
# Create non-root user for running the app
adduser Ashbane --disabled-password --gecos ""
usermod -aG sudo Ashbane

# Allow passwordless sudo for deployment (optional)
echo "Ashbane ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/Ashbane
```

### Install Python 3.11

```bash
add-apt-repository ppa:deadsnakes/ppa -y
apt update
apt install -y python3.11 python3.11-venv python3.11-dev
```

### Install PostgreSQL

```bash
apt install -y postgresql postgresql-contrib libpq-dev

# Start and enable
systemctl start postgresql
systemctl enable postgresql
```

### Install Nginx

```bash
apt install -y nginx
systemctl start nginx
systemctl enable nginx
```

### Configure Firewall

```bash
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw allow 8000/tcp  # Direct uvicorn access (optional, for testing)
ufw --force enable
ufw status
```

---

## 3. PostgreSQL Setup

### Create Database and User

```bash
sudo -u postgres psql
```

In PostgreSQL shell:

```sql
CREATE USER Ashbane WITH PASSWORD 'your_secure_password_here';
CREATE DATABASE Ashbanedb OWNER Ashbane;
GRANT ALL PRIVILEGES ON DATABASE Ashbanedb TO Ashbane;
\q
```

### Test Connection

```bash
psql -U Ashbane -d Ashbanedb -h localhost
# Enter password when prompted
# Type \q to exit
```

---

## 4. Application Deployment

### Switch to App User

```bash
su - Ashbane
```

### Clone Repository

```bash
cd ~
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git Ashbane-backend
cd Ashbane-backend/backend
```

### Create Virtual Environment

```bash
python3.11 -m venv venv
source venv/bin/activate
```

### Install Dependencies

```bash
# Install requirements + PostgreSQL driver
pip install --upgrade pip
pip install -r requirements.txt
pip install psycopg2-binary
```

### Configure Environment

```bash
cp .env.example .env
nano .env
```

Edit `.env` with production values:

```bash
# =============================================================================
# PRODUCTION ENVIRONMENT CONFIGURATION
# =============================================================================

# App Settings
APP_URL=https://your-domain.com  # Or http://YOUR_DROPLET_IP:8000 for testing
SESSION_SECRET=generate_a_random_32_char_string_here_use_openssl

# CORS - Add your Godot client domain/IP
CORS_ORIGINS=https://your-domain.com

# Database (PostgreSQL)
DATABASE_URL=postgresql://Ashbane:your_secure_password_here@localhost:5432/Ashbanedb

# =============================================================================
# PROVIDER API KEYS
# =============================================================================

# Steam API
STEAM_API_KEY=your_steam_api_key_here

# Battle.net (optional)
BATTLENET_CLIENT_ID=your_client_id
BATTLENET_CLIENT_SECRET=your_client_secret

# =============================================================================
# BLOCKCHAIN CONFIGURATION (Base Sepolia Testnet)
# =============================================================================

# Set to false to enable real testnet transactions
DEV_MODE=false

# Base Sepolia Testnet
CHAIN_ID=84532
RPC_URL=https://sepolia.base.org

# Contract (deploy first, then add address)
ACHIEVEMENT_CONTRACT_ADDRESS=

# Minter wallet (for forging achievements)
# Generate new wallet, fund with testnet ETH
MINTER_PRIVATE_KEY=

# Platform wallet (for bridge system)
PLATFORM_WALLET_ADDRESS=
PLATFORM_WALLET_KEY=
```

Generate a secure session secret:
```bash
openssl rand -hex 32
```

### Fix Alembic for PostgreSQL

Edit `alembic/env.py` line ~55 if it hardcodes SQLite:

```bash
nano alembic/env.py
# Ensure it uses DATABASE_URL from environment
```

### Run Database Migrations

```bash
alembic upgrade head
```

### Test Application

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Visit `http://YOUR_DROPLET_IP:8000` - you should see the dashboard.

Press `Ctrl+C` to stop.

---

## 5. Systemd Service

### Create Service Files

Two services are needed:
1. **ashbane.service** - Main API workers (handles HTTP requests)
2. **ashbane-worker.service** - Background worker (chain batching, transfer indexer)

```bash
# Copy service files from repo
sudo cp docs/systemd/ashbane.service /etc/systemd/system/
sudo cp docs/systemd/ashbane-worker.service /etc/systemd/system/
```

Or create manually:

**Main API Service** (`/etc/systemd/system/ashbane.service`):
```ini
[Unit]
Description=Ashbane Backend API
After=network.target postgresql.service

[Service]
User=Ashbane
Group=Ashbane
WorkingDirectory=/home/Ashbane/Ashbane-backend/backend
EnvironmentFile=/home/Ashbane/Ashbane-backend/backend/.env
Environment="PATH=/home/Ashbane/Ashbane-backend/backend/venv/bin"
ExecStart=/home/Ashbane/Ashbane-backend/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 2
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Background Worker Service** (`/etc/systemd/system/ashbane-worker.service`):
```ini
[Unit]
Description=Ashbane Background Worker
After=network.target postgresql.service ashbane.service

[Service]
User=Ashbane
Group=Ashbane
WorkingDirectory=/home/Ashbane/Ashbane-backend/backend
EnvironmentFile=/home/Ashbane/Ashbane-backend/backend/.env
Environment="PATH=/home/Ashbane/Ashbane-backend/backend/venv/bin"
Environment="BACKGROUND_WORKER=true"
ExecStart=/home/Ashbane/Ashbane-backend/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8001 --workers 1
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable ashbane ashbane-worker
sudo systemctl start ashbane ashbane-worker
sudo systemctl status ashbane ashbane-worker
```

---

## 6. Nginx Reverse Proxy

### Create Site Config

```bash
sudo nano /etc/nginx/sites-available/Ashbane
```

Paste (replace `your-domain.com` with your domain or IP):

```nginx
server {
    listen 80;
    server_name your-domain.com;  # Or YOUR_DROPLET_IP

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }

    # Static files
    location /static {
        alias /home/Ashbane/Ashbane-backend/backend/static;
    }
}
```

### Enable Site

```bash
sudo ln -s /etc/nginx/sites-available/Ashbane /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 7. SSL Certificate (If Using Domain)

### Install Certbot

```bash
sudo apt install -y certbot python3-certbot-nginx
```

### Get Certificate

```bash
sudo certbot --nginx -d your-domain.com
```

Follow prompts. Certbot will auto-configure nginx for HTTPS.

### Auto-Renewal

```bash
sudo certbot renew --dry-run
```

Certbot adds a cron job automatically.

---

## 8. Blockchain Testnet Setup

### Get Testnet RPC URL

1. Create account at https://www.alchemy.com/ or https://infura.io/
2. Create new app for **Base Sepolia**
3. Copy the HTTPS endpoint
4. Update `RPC_URL` in `.env`

### Fund Wallets with Testnet ETH

1. Generate wallet addresses (or use existing dev wallets)
2. Get Base Sepolia ETH from faucets:
   - https://www.coinbase.com/faucets/base-ethereum-goerli-faucet
   - https://faucet.quicknode.com/base/sepolia

3. Update `.env`:
   - `MINTER_PRIVATE_KEY` - Wallet that mints forged achievements
   - `PLATFORM_WALLET_ADDRESS` - Wallet for bridge custody
   - `PLATFORM_WALLET_KEY` - Private key for platform wallet

### Deploy Contract (If Needed)

See `backend/contracts/README.md` for contract deployment instructions.

After deployment, update `ACHIEVEMENT_CONTRACT_ADDRESS` in `.env`.

### Restart Service

```bash
sudo systemctl restart Ashbane
```

---

## 9. Godot Client Configuration

### Update API URL

Edit `scripts/systems/AshbaneAuth.gd`:

```gdscript
const API_BASE_PROD = "https://your-domain.com"  # Or http://YOUR_DROPLET_IP

func get_api_base() -> String:
    # For production builds, return API_BASE_PROD
    return API_BASE_PROD
```

### Update CORS

In `.env` on server, ensure your game client origin is allowed:

```bash
CORS_ORIGINS=https://your-domain.com,http://localhost:8000
```

Restart after changes:
```bash
sudo systemctl restart Ashbane
```

---

## 10. Maintenance Commands

### View Logs

```bash
# Service logs
sudo journalctl -u Ashbane -f

# Last 100 lines
sudo journalctl -u Ashbane -n 100

# Application logs (if configured)
tail -f /home/Ashbane/Ashbane-backend/backend/logs/app.log
```

### Service Management

```bash
sudo systemctl status Ashbane    # Check status
sudo systemctl restart Ashbane   # Restart
sudo systemctl stop Ashbane      # Stop
sudo systemctl start Ashbane     # Start
```

### Database Backup

```bash
# Create backup
pg_dump -U Ashbane -d Ashbanedb > backup_$(date +%Y%m%d).sql

# Restore
psql -U Ashbane -d Ashbanedb < backup_20241212.sql
```

### Update Deployment

```bash
cd /home/Ashbane/Ashbane-backend
git pull origin main

cd backend
source venv/bin/activate
pip install -r requirements.txt
alembic upgrade head

sudo systemctl restart Ashbane
```

---

## Troubleshooting

### Service Won't Start

```bash
sudo journalctl -u Ashbane -n 50 --no-pager
```

Common issues:
- Wrong Python path in service file
- Missing environment variables
- Database connection failed
- Port already in use

### Database Connection Failed

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Check connection
psql -U Ashbane -d Ashbanedb -h localhost

# Check pg_hba.conf allows local connections
sudo nano /etc/postgresql/14/main/pg_hba.conf
# Ensure line: local all all md5
sudo systemctl restart postgresql
```

### 502 Bad Gateway

```bash
# Check if uvicorn is running
sudo systemctl status Ashbane

# Check nginx config
sudo nginx -t

# Check port
curl http://127.0.0.1:8000
```

### Blockchain Transactions Failing

1. Check wallet has testnet ETH for gas
2. Verify RPC_URL is correct and accessible
3. Check contract address is deployed
4. Review logs for specific error messages

---

## Security Checklist

- [ ] SSH key authentication only (disable password)
- [ ] UFW firewall enabled
- [ ] Non-root user for application
- [ ] SSL/HTTPS enabled
- [ ] Strong database password
- [ ] SESSION_SECRET is unique and random
- [ ] Private keys not in git
- [ ] Rate limiting enabled (already in FastAPI)
- [ ] Regular backups configured

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `sudo systemctl restart Ashbane` | Restart backend |
| `sudo journalctl -u Ashbane -f` | Live logs |
| `sudo nginx -t && sudo systemctl reload nginx` | Reload nginx |
| `source venv/bin/activate && alembic upgrade head` | Run migrations |
| `pg_dump -U Ashbane -d Ashbanedb > backup.sql` | Backup database |

---

*Last updated: December 2024*
