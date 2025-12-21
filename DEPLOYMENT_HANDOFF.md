# Deployment Handoff - DigitalOcean Server

## Current Status
Deploying Ashbane backend to DigitalOcean droplet. Most setup complete, stuck on `.env` parsing issue.

---

## What's Done
- [x] DigitalOcean droplet created (Ubuntu 22.04)
- [x] Python 3.11, PostgreSQL, Nginx installed
- [x] Firewall configured (UFW)
- [x] PostgreSQL database `ashbanedb` and user `ashbane` created
- [x] Repo cloned to `~/ashbane-backend`
- [x] Python venv created at `~/ashbane-backend/backend/venv`
- [x] Dependencies installed via `pip install -r requirements.txt`
- [x] Cloudflare configured with domain
- [x] API keys rotated and ready

---

## Current Issue
**Alembic migrations failing** - DATABASE_URL is being parsed incorrectly.

Error shows the URL string includes the variable name:
```
'DATABASE_URL=postgresql://ashbane:...'
```

The `.env` file at `~/ashbane-backend/backend/.env` likely has a formatting issue. Need to check and fix it.

**Correct format:**
```
DATABASE_URL=postgresql://ashbane:PASSWORD@localhost:5432/ashbanedb
```

---

## What's Left To Do

1. **Fix `.env` file** - ensure DATABASE_URL is formatted correctly
2. **Run migrations:**
   ```bash
   cd ~/ashbane-backend/backend
   source venv/bin/activate
   alembic upgrade head
   ```

3. **Test the app manually:**
   ```bash
   uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```
   Visit `http://DROPLET_IP:8000` to verify

4. **Create systemd service:**
   ```bash
   sudo nano /etc/systemd/system/ashbane.service
   ```
   Contents:
   ```ini
   [Unit]
   Description=Ashbane Backend API
   After=network.target postgresql.service

   [Service]
   User=root
   Group=root
   WorkingDirectory=/root/ashbane-backend/backend
   Environment="PATH=/root/ashbane-backend/backend/venv/bin"
   ExecStart=/root/ashbane-backend/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 2
   Restart=always
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```
   Then:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable ashbane
   sudo systemctl start ashbane
   sudo systemctl status ashbane
   ```

5. **Configure Nginx reverse proxy:**
   ```bash
   sudo nano /etc/nginx/sites-available/ashbane
   ```
   Contents (replace YOUR_DOMAIN):
   ```nginx
   server {
       listen 80;
       server_name YOUR_DOMAIN;

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

       location /static {
           alias /root/ashbane-backend/backend/static;
       }
   }
   ```
   Then:
   ```bash
   sudo ln -s /etc/nginx/sites-available/ashbane /etc/nginx/sites-enabled/
   sudo nginx -t
   sudo systemctl reload nginx
   ```

6. **Update OAuth redirect URIs** at all providers to use production domain:
   - Battle.net
   - Discord
   - GitHub
   - Facebook
   - Roblox
   - OpenXBL (App URI + Redirect URI)
   - Steam (just domain name, no redirect)

7. **Test full auth flow** with each provider

---

## Key Files
- Backend code: `~/ashbane-backend/backend/`
- Environment config: `~/ashbane-backend/backend/.env`
- Alembic config: `~/ashbane-backend/backend/alembic/`
- Main app: `~/ashbane-backend/backend/app/main.py`

---

## Environment Variables Required in `.env`
```bash
APP_URL=https://YOUR_DOMAIN
DATABASE_URL=postgresql://ashbane:PASSWORD@localhost:5432/ashbanedb
DEV_MODE=false
SESSION_SECRET=<64 char hex from: openssl rand -hex 32>
ADMIN_SECRET=<32 char hex from: openssl rand -hex 16>
CORS_ORIGINS=https://YOUR_DOMAIN
CHAIN_ID=84532

# Provider API Keys
STEAM_API_KEY=xxx
BATTLENET_CLIENT_ID=xxx
BATTLENET_CLIENT_SECRET=xxx
OPENXBL_API_KEY=xxx
DISCORD_CLIENT_ID=xxx
DISCORD_CLIENT_SECRET=xxx
GITHUB_CLIENT_ID=xxx
GITHUB_CLIENT_SECRET=xxx
FACEBOOK_APP_ID=xxx
FACEBOOK_APP_SECRET=xxx
ROBLOX_CLIENT_ID=xxx
ROBLOX_CLIENT_SECRET=xxx
```

---

## Commands to Resume
```bash
cd ~/ashbane-backend/backend
source venv/bin/activate
cat .env  # Check the file
nano .env  # Fix if needed
alembic upgrade head  # Run migrations
```
