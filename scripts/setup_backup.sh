#!/bin/bash
# Backup script must be in /home/backup/scripts/backup.sh
set -euo pipefail

BACKUP_HOME="/home/backup"
BACKUP_ROOT="$BACKUP_HOME/backups"
SCRIPTS_DIR="$BACKUP_HOME/scripts"
LOG_DIR="$BACKUP_HOME/logs"

echo "🔧 Installing cronie..."
sudo yum install cronie -y

echo "▶️ Enabling and starting cron service..."
sudo systemctl enable crond
sudo systemctl start crond

echo "🔧 Creating 'backup' user..."
sudo useradd -m -s /bin/bash backup 2>/dev/null || echo "'backup' user already exists"

echo "📁 Creating working directories..."
sudo mkdir -p "$BACKUP_ROOT"
sudo mkdir -p "$LOG_DIR"

echo "🔒 Setting permissions..."
sudo chown -R backup:backup "$BACKUP_HOME"
sudo chmod 700 "$BACKUP_HOME/.ssh" 2>/dev/null || true

BACKUP_SCRIPT="$SCRIPTS_DIR/backup.sh"

sudo chmod +x "$BACKUP_SCRIPT"
sudo chown backup:backup "$BACKUP_SCRIPT"

echo "🕑 Adding automatic backup to user's crontab..."
( sudo crontab -u backup -l 2>/dev/null; echo "0 3 * * * $BACKUP_SCRIPT >> $LOG_DIR/backup.log 2>&1" ) | sudo crontab -u backup -

echo "✅ Backup server initialized and ready."
