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
: "${BACKUP_HOSTNAME:?}"             
: "${SSH_KEY:?}"                  
: "${REMOTE_USER:=backup}"       
: "${SQL_ADMIN_USER:=admin}"

SQL_DB="${USERNAME}_db"
SQL_USER="${USERNAME}_sql"
ARCHIVE_DIR="/home/backup/archives/$USERNAME"
ARCHIVE_NAME="${USERNAME}_${DATE}.tar.gz"
SQL_DUMP_NAME="${USERNAME}_${DATE}.sql.gz"

# === Creation du dossier archive ===
echo "📁 Création du dossier $ARCHIVE_DIR sur le serveur de backup si nécessaire..."
mkdir -p $ARCHIVE_DIR
sudo chown -R backup:backup $ARCHIVE_DIR


# === Étapes sur le serveur Web ===
echo "📡 Suppression de $USERNAME sur $WEB_PRIVATE_IP..."
ssh -i "$SSH_KEY" ec2-user@$WEB_PRIVATE_IP bash -s <<EOF
sudo tar czf "/tmp/$ARCHIVE_NAME" "/srv/www/$USERNAME"
sudo smbpasswd -x "$USERNAME" || true
sudo userdel -r "$USERNAME" || true
sudo rm -rf /etc/httpd/sites-available/${USERNAME}*.conf /etc/httpd/sites-enabled/${USERNAME}*.conf /srv/www/${USERNAME}
sudo systemctl reload httpd
EOF

# === Transfert de l'archive web vers serveur backup ===
echo "📦 Transfert de l’archive web vers $BACKUP_HOSTNAME..."
scp -i "$SSH_KEY" ec2-user@$WEB_PRIVATE_IP:/tmp/$ARCHIVE_NAME $REMOTE_USER@$BACKUP_HOSTNAME:$ARCHIVE_DIR/

# === Suppression de l’archive temporaire côté Web ===
ssh -i "$SSH_KEY" ec2-user@$WEB_PRIVATE_IP "sudo rm -f /tmp/$ARCHIVE_NAME"

# === Export SQL depuis le backend ===
ssh -i "$SSH_KEY" ec2-user@$BACKEND_PRIVATE_IP bash -s <<EOF
if sudo mysql -e "USE \\\`$SQL_DB\\\`;" 2>/dev/null; then
  echo "[+] Dump SQL de $SQL_DB..."
  sudo mysqldump --databases "$SQL_DB" | gzip > "/tmp/$SQL_DUMP_NAME"
  sudo mysql -e "DROP DATABASE \\\`$SQL_DB\\\`;"
else
  echo "⚠️ Base $SQL_DB introuvable, pas de dump."
fi
sudo mysql -e "DROP USER IF EXISTS '$SQL_USER'@'%';"
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
