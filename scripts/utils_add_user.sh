#!/bin/bash

# Script d'ajout d'un utilisateur FTP chrooté dans /srv/www/<utilisateur> avec VirtualHost HTTPD associé

if [ -z "$1" ]; then
    echo "❌ Utilisation : $0 <nom_utilisateur>"
    exit 1
fi

USERNAME=$1
USERDIR="/srv/www/$USERNAME"

echo "[+] Création de l'utilisateur $USERNAME (sans shell)"
useradd -m "$USERNAME"

echo "[+] Définir le mot de passe pour $USERNAME"
passwd "$USERNAME"

echo "[+] Création du dossier de l'utilisateur $USERNAME"
mkdir -p "$USERDIR"

echo "[+] Attribution des permissions"
chown "$USERNAME:$USERNAME" "$USERDIR"
chmod 755 "$USERDIR"

# Configuration HTTPD du VirtualHost
VHOSTCONF="/etc/httpd/sites-available/$USERNAME.conf"
echo "[+] Création du VirtualHost HTTPD pour $USERNAME"
cat > "$VHOSTCONF" <<EOF
<VirtualHost *:80>
    ServerName $USERNAME.tomananas.lan
    DocumentRoot $USERDIR
    <Directory "$USERDIR">
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/${USERNAME}_error.log
    CustomLog /var/log/httpd/${USERNAME}_access.log combined
</VirtualHost>
EOF

echo "[+] Activation du VirtualHost pour $USERNAME"
ln -s "$VHOSTCONF" /etc/httpd/sites-enabled/

echo "[+] Rechargement de la configuration HTTPD"
systemctl reload httpd

echo "[+] Utilisateur $USERNAME prêt avec FTP et HTTPD (VirtualHost chrooté dans $USERDIR)"
