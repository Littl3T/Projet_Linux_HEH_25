#!/bin/bash

set -euo pipefail

# === General Configuration ===
DATE=$(date +%F)
BACKUP_HOME="/home/backup"
BACKUP_DIR="$BACKUP_HOME/backups/$DATE"
REMOTE_USER="backup"
SSH_KEY="$BACKUP_HOME/.ssh/id_backup"

# === Hostnames ===
WEB_HOST="web-ftp-01.tomananas.lan"
DNS_HOST="dns-ntp-02.tomananas.lan"
DB_HOST="mysql-mail-04.tomananas.lan"

# === Files to back up per host ===
WEB_FILES=(/etc/httpd/sites-available/ /srv/www/)
DNS_FILES=(/etc/named.conf /var/named/)
DB_DUMP="$BACKUP_DIR/${DB_HOST%%.*}-mysql-$DATE.sql.gz"

# Load variables from setup_env.sh file
if [ ! -f "/root/setup_env.sh" ]; then
  echo "❌ setup_env.sh file not found. Create one with the necessary variables."
  exit 1
else
  source /root/setup_env.sh
fi

# Required environment variables
: "${NFS_PRIVATE_IP:?NFS_PRIVATE_IP is not set}"
: "${SHARED_FOLDER:?SHARED_FOLDER is not set}"
: "${MOUNT_ROOT:?MOUNT_ROOT is not set}"
: "${MOUNT_NAME:?MOUNT_NAME is not set}"
: "${TIMEOUT:?TIMEOUT is not set}"
: "${AUTO_MASTER:?AUTO_MASTER is not set}"
: "${AUTO_MAP:?AUTO_MAP is not set}"

# === Prepare backup directory ===
mkdir -p "$BACKUP_DIR"
chown backup:backup "$BACKUP_DIR"

# DNS fix (AWS context)
echo -e "nameserver 172.31.5.243\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null

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
