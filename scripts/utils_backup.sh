#!/bin/bash

set -euo pipefail

# Load variables from setup_env.sh file
if [ ! -f "/home/backup/scripts/setup_env.sh" ]; then
  echo "❌ setup_env.sh file not found. Create one with the necessary variables."
  exit 1
else
  source /home/backup/scripts/setup_env.sh
fi

# Required environment variables
: "${BACKUP_HOME:?BACKUP_HOME is not set}"
: "${REMOTE_USER:?REMOTE_USER is not set}"
: "${SSH_KEY:?SSH_KEY is not set}"
: "${WEB_HOST:?WEB_HOST is not set}"
: "${DNS_HOST:?DNS_HOST is not set}"
: "${DB_HOST:?DB_HOST is not set}"
: "${WEB_FILES:?WEB_FILES is not set}"
: "${DNS_FILES:?DNS_FILES is not set}"
: "${DNS_PRIVATE_IP:?DNS_PRIVATE_IP is not set}"

# === General Configuration ===
DATE=$(date +%F)
BACKUP_DIR="$BACKUP_HOME/backups/$DATE"
DB_DUMP="$BACKUP_DIR/${DB_HOST%%.*}-mysql-$DATE.sql.gz"

# === Prepare backup directory ===
mkdir -p "$BACKUP_DIR"
chown backup:backup "$BACKUP_DIR"

# === Remote backup function ===
backup_host() {
  local HOST="$1"
  local ARCHIVE="$2"
  shift 2
  local FILES=("$@")

  echo "📦 Backing up $HOST..."
  ssh -i "$SSH_KEY" "$REMOTE_USER@$HOST" "tar czf - ${FILES[*]}" > "$ARCHIVE"

  if [[ ! -s "$ARCHIVE" ]]; then
    echo "❌ ERROR: Archive $ARCHIVE is empty or corrupted."
    rm -f "$ARCHIVE"
    return 1
  else
    echo "✅ Archive created: $ARCHIVE"
  fi
}

# === MySQL dump ===
echo "🗄️ Dumping MySQL from $DB_HOST..."
ssh -i "$SSH_KEY" "$REMOTE_USER@$DB_HOST" \
"mysqldump -u admin -p'AdminStrongPwd!2025' --all-databases" \
| gzip > "$DB_DUMP"

if [[ ! -s "$DB_DUMP" ]]; then
  echo "❌ ERROR: MySQL dump is empty!"
  rm -f "$DB_DUMP"
else
  echo "✅ MySQL dump saved: $DB_DUMP"
fi

# === Backup service files ===
backup_host "$WEB_HOST" "$BACKUP_DIR/${WEB_HOST%%.*}-$DATE.tar.gz" "${WEB_FILES[@]}"
backup_host "$DNS_HOST" "$BACKUP_DIR/${DNS_HOST%%.*}-$DATE.tar.gz" "${DNS_FILES[@]}"

# === Cleanup old backups ===
echo "🧹 Removing backups older than 30 days..."
find "$BACKUP_HOME/backups/" -type f -mtime +30 -exec rm -f {} \;
find "$BACKUP_HOME/backups/" -type d -empty -mtime +30 -exec rmdir {} \;

echo "✅ Backup completed on $DATE."
