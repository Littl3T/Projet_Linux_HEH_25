#!/bin/bash
set -euo pipefail

# === Chargement de l’environnement ===
# Load variables from setup_env.sh file
if [ ! -f "/home/backup/scripts/setup_env.sh" ]; then
  echo "❌ setup_env.sh file not found. Create one with the necessary variables."
  exit 1
else
  source /home/backup/scripts/setup_env.sh
fi

: "${WEB_PRIVATE_IP:?}"
: "${BACKEND_PRIVATE_IP:?}"
: "${DNS_PRIVATE_IP:?}"
: "${BACKUP_HOSTNAME:?}"
: "${SSH_KEY:?}"
: "${REMOTE_USER:=backup}"
: "${SQL_ADMIN_USER:=admin}"

# === Argument obligatoire ===
USERNAME="$1"
USERDIR="/srv/www/$USERNAME"
SQL_DB="${USERNAME}_db"
SQL_USER="${USERNAME}_sql"
ARCHIVE_DIR="/home/backup/archives/$USERNAME"
LATEST_TAR=$(ls -t "$ARCHIVE_DIR/$USERNAME"*.tar.gz | head -1)
LATEST_SQL=$(ls -t "$ARCHIVE_DIR/$USERNAME"*.sql.gz | head -1)

if [[ ! -f "$LATEST_TAR" || ! -f "$LATEST_SQL" ]]; then
  echo "❌ Archive introuvable dans $ARCHIVE_DIR"
  exit 1
fi

# === Saisie mot de passe FTP/Samba ===
read -s -p "🔑 Mot de passe FTP/Samba pour '$USERNAME' : " FTP_PWD
echo
read -s -p "🔁 Confirmez : " FTP_PWD_CONFIRM
echo
[[ "$FTP_PWD" != "$FTP_PWD_CONFIRM" ]] && echo "❌ Les mots de passe ne correspondent pas." && exit 1

# === Saisie mot de passe SQL ===
read -s -p "🔑 Mot de passe SQL pour '$SQL_USER' : " SQL_PWD
echo
read -s -p "🔁 Confirmez : " SQL_PWD_CONFIRM
echo
[[ "$SQL_PWD" != "$SQL_PWD_CONFIRM" ]] && echo "❌ Les mots de passe ne correspondent pas." && exit 1

# === Copie temporaire locale ===
cp "$LATEST_TAR" /tmp/
cp "$LATEST_SQL" /tmp/
TAR_FILE=$(basename "$LATEST_TAR")
SQL_FILE=$(basename "$LATEST_SQL")

scp -i "$SSH_KEY" /tmp/$TAR_FILE ec2-user@"$WEB_PRIVATE_IP":/tmp/
scp -i "$SSH_KEY" /tmp/$SQL_FILE ec2-user@$BACKEND_PRIVATE_IP:/tmp/


# === Serveur Web ===
echo "🌐 Restauration web sur $WEB_PRIVATE_IP..."
ssh -i "$SSH_KEY" ec2-user@$WEB_PRIVATE_IP bash -s <<EOF
sudo useradd -m "$USERNAME" || true
echo "$USERNAME:$FTP_PWD" | sudo chpasswd
echo "[+] Extraction de l'archive dans /"
sudo tar xzf /tmp/$TAR_FILE -C /
sudo chown -R "$USERNAME:$USERNAME" "$USERDIR"

# Vhosts
sudo mkdir -p /etc/httpd/sites-available /etc/httpd/sites-enabled

sudo tee /etc/httpd/sites-available/${USERNAME}-ssl.conf > /dev/null <<VHSSL
<VirtualHost *:443>
    ServerName $USERNAME.tomananas.lan
    DocumentRoot $USERDIR
    SSLEngine on
    SSLCertificateFile      /etc/pki/tls/certs/wildcard.crt.pem
    SSLCertificateKeyFile   /etc/pki/tls/private/wildcard.key.pem
    <Directory "$USERDIR">
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
VHSSL

sudo ln -sf /etc/httpd/sites-available/$USERNAME.conf /etc/httpd/sites-enabled/
sudo ln -sf /etc/httpd/sites-available/${USERNAME}-ssl.conf /etc/httpd/sites-enabled/
sudo systemctl reload httpd

# Samba
printf "%s\n%s\n" "$FTP_PWD" "$FTP_PWD" | sudo smbpasswd -s -a "$USERNAME"
sudo smbpasswd -e "$USERNAME"
EOF

# === Base de données ===
echo "🗄️ Restauration SQL sur $BACKEND_PRIVATE_IP..."
ssh -i "$SSH_KEY" ec2-user@$BACKEND_PRIVATE_IP bash -s <<EOF
sudo mysql  <<SQL
DROP USER IF EXISTS '$SQL_USER'@'%';
CREATE USER '$SQL_USER'@'%' IDENTIFIED BY '$SQL_PWD';
CREATE DATABASE IF NOT EXISTS \\\`$SQL_DB\\\`;
GRANT ALL PRIVILEGES ON \\\`$SQL_DB\\\`.* TO '$SQL_USER'@'%';
FLUSH PRIVILEGES;
SQL

gunzip -c /tmp/$SQL_FILE | sudo mysql "$SQL_DB"
EOF

# === DNS ===
echo "🌐 Réinsertion DNS sur $DNS_PRIVATE_IP..."
ssh -i "$SSH_KEY" ec2-user@$DNS_PRIVATE_IP bash -s <<EOF
ZONE_FILE="$ZONE_DIR/forward.tomananas.lan"
TMP=\$(mktemp)
sudo awk '!/^$USERNAME\s+IN\s+A\s+/' "\$ZONE_FILE" > "\$TMP"
echo "$USERNAME IN A $WEB_PRIVATE_IP" >> "\$TMP"
sudo mv "\$TMP" "\$ZONE_FILE"
sudo chown named:named "\$ZONE_FILE"
sudo systemctl restart named
EOF

# === Nettoyage temporaire ===
rm -f /tmp/"$TAR_FILE" /tmp/"$SQL_FILE"

echo "✅ Restauration complète de l’utilisateur $USERNAME"
