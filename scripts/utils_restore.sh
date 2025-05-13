#!/bin/bash

set -euo pipefail

# === Load environment ===
if [ ! -f "/home/backup/scripts/setup_env.sh" ]; then
  echo "❌ setup_env.sh not found."
  exit 1
else
  source /home/backup/scripts/setup_env.sh
fi

# === Ask for backup date ===
read -p "📅 Enter backup date (YYYY-MM-DD): " BACKUP_DATE
BACKUP_DIR="$BACKUP_HOME/backups/$BACKUP_DATE"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "❌ Backup folder not found: $BACKUP_DIR"
  exit 1
fi

# === Prompt user for services to restore ===
echo "🛠️ Select services to restore:"
echo "1. Web"
echo "2. DNS"
echo "3. MySQL"
echo "4. All"
read -p "➡️ Enter choice (1-4): " CHOICE

# === Prompt for target hostnames ===
ask_target() {
  local service="$1"
  read -p "🌐 Target host for $service? (ex: web-ftp-01.tomananas.lan): " target
  echo "$target"
}

RESTORE_WEB=false
RESTORE_DNS=false
RESTORE_DB=false

case "$CHOICE" in
  1) RESTORE_WEB=true ;;
  2) RESTORE_DNS=true ;;
  3) RESTORE_DB=true ;;
  4) RESTORE_WEB=true; RESTORE_DNS=true; RESTORE_DB=true ;;
  *) echo "❌ Invalid choice." && exit 1 ;;
esac

echo ""

# === SSH + Restore ===
remote_restore_tar() {
  local archive="$1"
  local target_host="$2"
  local label="$3"

  if [ -f "$archive" ]; then
    echo "🔁 Restoring $label to $target_host..."
    cat "$archive" | ssh -i "$SSH_KEY" "$REMOTE_USER@$target_host" "sudo tar xzf - -C /"
    echo "✅ $label restored to $target_host."
  else
    echo "⚠️ Archive not found: $archive"
  fi
}

# === Restore each selected service ===
if [ "$RESTORE_WEB" = true ]; then
  WEB_ARCHIVE="$BACKUP_DIR/${WEB_HOST%%.*}-$BACKUP_DATE.tar.gz"
  WEB_TARGET=$(ask_target "Web")
  remote_restore_tar "$WEB_ARCHIVE" "$WEB_TARGET" "Web files"
fi

if [ "$RESTORE_DNS" = true ]; then
  DNS_ARCHIVE="$BACKUP_DIR/${DNS_HOST%%.*}-$BACKUP_DATE.tar.gz"
  DNS_TARGET=$(ask_target "DNS")
  remote_restore_tar "$DNS_ARCHIVE" "$DNS_TARGET" "DNS files"
fi

if [ "$RESTORE_DB" = true ]; then
  DB_DUMP="$BACKUP_DIR/${DB_HOST%%.*}-mysql-$BACKUP_DATE.sql.gz"
  DB_TARGET=$(ask_target "MySQL")
  if [ -f "$DB_DUMP" ]; then
    echo "🗄️ Restoring MySQL to $DB_TARGET..."
    gunzip -c "$DB_DUMP" | ssh -i "$SSH_KEY" "$REMOTE_USER@$DB_TARGET" "mysql -u root -p"
    echo "✅ MySQL restored to $DB_TARGET."
  else
    echo "⚠️ MySQL dump not found: $DB_DUMP"
  fi
fi

echo "🎉 Remote restoration complete."
