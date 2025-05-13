#!/bin/bash
set -euo pipefail

# === Paramètres ===
USERNAME="$1"
DATE=$(date +%F)

# Chargement des variables d'environnement
if [ ! -f "/home/backup/scripts/setup_env.sh" ]; then
  echo "❌ setup_env.sh est introuvable. "
  exit 1
fi
source /home/backup/scripts/setup_env.sh

: "${WEB_PRIVATE_IP:?}"
: "${BACKEND_PRIVATE_IP:?}"
: "${DNS_PRIVATE_IP:?}"
: "${BACKUP_HOSTNAME:?}"              # Exemple : backup-01.tomananas.lan
: "${SSH_KEY:?}"                  # Clé SSH utilisée pour se connecter
: "${REMOTE_USER:=backup}"        # Nom de l'utilisateur sur le serveur de backup
: "${SQL_ADMIN_USER:=admin}"

SQL_DB="${USERNAME}_db"
SQL_USER="${USERNAME}_sql"
ARCHIVE_DIR="/home/backup/archives/$USERNAME"
ARCHIVE_NAME="${USERNAME}_${DATE}.tar.gz"
SQL_DUMP_NAME="${USERNAME}_${DATE}.sql.gz"

# === Creation du dossier archive ===
echo "📁 Création du dossier $ARCHIVE_DIR sur le serveur de backup si nécessaire..."
ssh -i "$SSH_KEY" $REMOTE_USER@$BACKUP_HOSTNAME "mkdir -p '$ARCHIVE_DIR'"

# === Étapes sur le serveur Web ===
echo "📡 Suppression de $USERNAME sur $WEB_PRIVATE_IP..."
ssh -i "$SSH_KEY" ec2-user@$WEB_PRIVATE_IP bash -s <<EOF
sudo tar czf "/tmp/$ARCHIVE_NAME" "/srv/www/$USERNAME"
sudo userdel -r "$USERNAME" || true
sudo smbpasswd -x "$USERNAME" || true
sudo rm -f /etc/httpd/sites-available/${USERNAME}*.conf /etc/httpd/sites-enabled/${USERNAME}*.conf
sudo systemctl reload httpd
EOF

# === Transfert de l'archive web vers serveur backup ===
echo "📦 Transfert de l’archive web vers $BACKUP_HOSTNAME..."
ssh -i "$SSH_KEY" $REMOTE_USER@$BACKUP_HOSTNAME "mkdir -p '$ARCHIVE_DIR'"
scp -i "$SSH_KEY" ec2-user@$WEB_PRIVATE_IP:/tmp/$ARCHIVE_NAME $REMOTE_USER@$BACKUP_HOSTNAME:$ARCHIVE_DIR/

# === Suppression de l’archive temporaire côté Web ===
ssh -i "$SSH_KEY" ec2-user@$WEB_PRIVATE_IP "sudo rm -f /tmp/$ARCHIVE_NAME"

# === Export SQL depuis le backend ===
echo "🗄 Dump SQL de $SQL_DB..."
ssh -i "$SSH_KEY" ec2-user@$BACKEND_PRIVATE_IP bash -s <<EOF
mysqldump -u "$SQL_ADMIN_USER" -p'AdminStrongPwd!2025' "$SQL_DB" | gzip > "/tmp/$SQL_DUMP_NAME"
mysql -u "$SQL_ADMIN_USER" -p'AdminStrongPwd!2025' -e "DROP DATABASE IF EXISTS \\\`$SQL_DB\\\`;"
mysql -u "$SQL_ADMIN_USER" -p'AdminStrongPwd!2025' -e "DROP USER IF EXISTS '$SQL_USER'@'%';"
EOF

# === Transfert du dump SQL vers serveur backup ===
scp -i "$SSH_KEY" ec2-user@$BACKEND_PRIVATE_IP:/tmp/$SQL_DUMP_NAME $REMOTE_USER@$BACKUP_HOSTNAME:$ARCHIVE_DIR/

# === Suppression du fichier temporaire SQL ===
ssh -i "$SSH_KEY" ec2-user@$BACKEND_PRIVATE_IP "rm -f /tmp/$SQL_DUMP_NAME"

# === Suppression DNS ===
echo "🧹 Suppression de l'entrée DNS..."
ssh -i "$SSH_KEY" ec2-user@$DNS_PRIVATE_IP bash -s <<EOF
ZONE_FILE="$ZONE_DIR/forward.tomananas.lan"
TMP_FILE=\$(mktemp)
sudo awk '!/^$USERNAME\s+IN\s+A\s+/' "\$ZONE_FILE" > "\$TMP_FILE"
sudo mv "\$TMP_FILE" "\$ZONE_FILE"
sudo chown named:named "\$ZONE_FILE"
sudo systemctl restart named
EOF

echo "✅ Utilisateur $USERNAME supprimé, données archivées sur $BACKUP_HOSTNAME:$ARCHIVE_DIR/"
