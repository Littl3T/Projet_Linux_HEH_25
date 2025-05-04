#!/bin/bash

set -euo pipefail

# === Configuration ===
DATE=$(date +%F)
BACKUP_HOME="/home/backup"
BACKUP_DIR="$BACKUP_HOME/backups/$DATE"
REMOTE_USER="backup"
SSH_KEY="$BACKUP_HOME/.ssh/id_backup"

# Créer le répertoire du jour avec les bons droits
mkdir -p "$BACKUP_DIR"
chown backup:backup "$BACKUP_DIR"

echo -e "nameserver 172.31.5.243\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null

# === Hôtes ===
WEB_HOST="web-ftp-01.tomananas.lan"
DNS_HOST="dns-ntp-02.tomananas.lan"
DB_HOST="mysql-mail-04.tomananas.lan"

# === Fichiers à sauvegarder ===
WEB_FILES=(/etc/httpd/sites-available/ /srv/www/)
DNS_FILES=(/etc/named.conf /var/named/)
DB_DUMP="$BACKUP_DIR/mysql-mail-04-mysql-$DATE.sql.gz"

# === Fonction de sauvegarde distante ===
backup_host() {
  local HOST="$1"
  local ARCHIVE="$2"
  shift 2
  local FILES=("$@")

  echo "📦 Sauvegarde de $HOST..."

  ssh -i "$SSH_KEY" "$REMOTE_USER@$HOST" "tar czf - ${FILES[*]}" > "$ARCHIVE"

  if [[ ! -s "$ARCHIVE" ]]; then
    echo "❌ ERREUR : l’archive $ARCHIVE est vide ou corrompue"
    rm -f "$ARCHIVE"
    return 1
  else
    echo "✅ Archive créée : $ARCHIVE"
  fi
}

# === Dump MySQL compressé ===
ssh -i "$SSH_KEY" "$REMOTE_USER@$DB_HOST" \
"mysqldump -u admin -p'AdminStrongPwd!2025' --all-databases" \
| gzip > "$DB_DUMP"

if [[ ! -s "$DB_DUMP" ]]; then
  echo "❌ ERREUR : le dump MySQL est vide !"
  rm -f "$DB_DUMP"
else
  echo "✅ Dump compressé : $DB_DUMP"
fi

# === Sauvegardes fichiers de services ===
backup_host "$WEB_HOST" "$BACKUP_DIR/web-ftp-01-$DATE.tar.gz" "${WEB_FILES[@]}"
backup_host "$DNS_HOST" "$BACKUP_DIR/dns-ntp-02-$DATE.tar.gz" "${DNS_FILES[@]}"

# === Nettoyage des anciennes sauvegardes ===
echo "🧹 Suppression des backups de plus de 30 jours..."
find "$BACKUP_HOME/backups/" -type f -mtime +30 -exec rm -f {} \;
find "$BACKUP_HOME/backups/" -type d -empty -mtime +30 -exec rmdir {} \;

echo "✅ Sauvegarde complète terminée le $DATE."
