#!/bin/bash

# === Configuration ===
WEB_SERVER="172.31.10.47"             # IP ou nom DNS du serveur web+ftp
SQL_SERVER="172.31.7.29"              # IP ou nom DNS du serveur MySQL
SQL_ADMIN_USER="admin"
SQL_ADMIN_PWD="AdminStrongPwd!2025"

# === Vérification des arguments ===
if [ -z "$1" ]; then
    echo "❌ Utilisation : $0 <nom_utilisateur>"
    exit 1
fi

USERNAME=$1
USERDIR="/srv/www/$USERNAME"
SQL_DB="${USERNAME}_db"
SQL_USER="${USERNAME}_sql"

# === Saisie manuelle du mot de passe FTP (Linux) ===
read -s -p "🔑 Entrez le mot de passe FTP pour l'utilisateur Linux '$USERNAME' : " FTP_PWD
echo
read -s -p "🔁 Confirmez le mot de passe FTP : " FTP_PWD_CONFIRM
echo

if [ "$FTP_PWD" != "$FTP_PWD_CONFIRM" ]; then
    echo "❌ Les mots de passe ne correspondent pas."
    exit 1
fi

# === Saisie manuelle du mot de passe SQL ===
read -s -p "🔑 Entrez le mot de passe SQL pour l'utilisateur '$SQL_USER' : " SQL_PWD
echo
read -s -p "🔁 Confirmez le mot de passe SQL : " SQL_PWD_CONFIRM
echo

if [ "$SQL_PWD" != "$SQL_PWD_CONFIRM" ]; then
    echo "❌ Les mots de passe ne correspondent pas."
    exit 1
fi

# === Création utilisateur sur serveur Web+FTP ===
echo "📡 Connexion à $WEB_SERVER pour créer l’utilisateur système et le VirtualHost…"
ssh ec2-user@$WEB_SERVER bash -s <<EOF
echo "[+] Création de l'utilisateur Linux $USERNAME"
sudo useradd -m "$USERNAME"

echo "[+] Définition du mot de passe FTP"
echo "$USERNAME:$FTP_PWD" | sudo chpasswd

echo "[+] Création du répertoire et permissions"
sudo mkdir -p "$USERDIR"
sudo chown "$USERNAME:$USERNAME" "$USERDIR"
sudo chmod 755 "$USERDIR"

echo "[+] Configuration du VirtualHost Apache"
sudo mkdir -p /etc/httpd/sites-available /etc/httpd/sites-enabled
sudo tee /etc/httpd/sites-available/$USERNAME.conf > /dev/null <<VHCONF
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
VHCONF

sudo ln -sf /etc/httpd/sites-available/$USERNAME.conf /etc/httpd/sites-enabled/
sudo grep -q 'IncludeOptional sites-enabled/\*\.conf' /etc/httpd/conf/httpd.conf || \
  echo 'IncludeOptional sites-enabled/*.conf' | sudo tee -a /etc/httpd/conf/httpd.conf > /dev/null

sudo systemctl reload httpd
EOF

echo "✅ Utilisateur Linux $USERNAME créé sur le serveur Web/FTP"

# === Création de l’utilisateur SQL ===
echo "🗄 Connexion à $SQL_SERVER pour créer la base SQL et l’utilisateur…"
ssh ec2-user@$SQL_SERVER bash -s <<EOF
sudo mysql -u$SQL_ADMIN_USER -p$SQL_ADMIN_PWD <<MYSQL
CREATE DATABASE IF NOT EXISTS \\\`$SQL_DB\\\`;
CREATE USER IF NOT EXISTS '$SQL_USER'@'%' IDENTIFIED BY '$SQL_PWD';
GRANT ALL PRIVILEGES ON \\\`$SQL_DB\\\`.* TO '$SQL_USER'@'%';
FLUSH PRIVILEGES;
MYSQL
EOF

echo "✅ Base de données $SQL_DB et utilisateur $SQL_USER créés sur le serveur SQL"

# === Résumé ===
echo "🎉 Client $USERNAME ajouté avec succès !"
echo "🔐 Informations de connexion :"
echo "🖥 FTP (serveur Web) :"
echo "    Utilisateur : $USERNAME"
echo "    Mot de passe : (défini manuellement)"
echo "🗄 MySQL (phpMyAdmin) :"
echo "    Hôte         : $SQL_SERVER"
echo "    Base         : $SQL_DB"
echo "    Utilisateur  : $SQL_USER"
echo "    Mot de passe : $SQL_PWD"
