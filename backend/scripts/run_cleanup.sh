#!/bin/bash
# Wrapper script for log cleanup cron job
cd /root/ashbane-backend/backend
./venv/bin/python scripts/cleanup_old_logs.py --days 30
