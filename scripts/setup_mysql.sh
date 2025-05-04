#!/usr/bin/env bash
set -euo pipefail

NEW_ROOT_PWD="Tomval03+!"
REMOTE_ADMIN_USER="admin"
REMOTE_ADMIN_PWD="AdminStrongPwd!2025"

echo "[+] Installation du dépôt MySQL Community…"
wget -q https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2023
dnf install -y mysql80-community-release-el9-1.noarch.rpm

echo "[+] Installation du serveur MySQL Community…"
dnf install -y mysql-community-server

echo "[+] Activation et démarrage de mysqld…"
systemctl enable --now mysqld

echo "[+] Récupération du mot de passe temporaire…"
TEMP_PWD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
if [[ -z "$TEMP_PWD" ]]; then
  echo "!! Impossible de trouver le mot de passe temporaire dans /var/log/mysqld.log" >&2
  exit 1
fi

echo "[+] Sécurisation de l'installation et changement de mot de passe root…"
mysql --connect-expired-password -uroot -p"$TEMP_PWD" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$NEW_ROOT_PWD';
UNINSTALL COMPONENT 'file://component_validate_password';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

echo "[+] Création d'un utilisateur administrateur distant sécurisé…"
mysql -uroot -p"$NEW_ROOT_PWD" <<EOF
CREATE USER IF NOT EXISTS '$REMOTE_ADMIN_USER'@'%' IDENTIFIED WITH mysql_native_password BY '$REMOTE_ADMIN_PWD';
GRANT ALL PRIVILEGES ON *.* TO '$REMOTE_ADMIN_USER'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

echo "[+] Configuration réseau (bind-address)…"
cat >> /etc/my.cnf.d/server.cnf <<CNF

[mysqld]
bind-address = 0.0.0.0
CNF

echo "[+] Redémarrage de MySQL…"
systemctl restart mysqld

echo "[+] Installation et configuration du pare-feu (firewalld)…"
dnf install -y firewalld
systemctl enable --now firewalld

firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

echo "[+] Installation de Apache, PHP et modules nécessaires…"
dnf install -y httpd php php-mysqlnd php-json php-mbstring php-zip php-gd php-common
systemctl enable --now httpd

echo "[+] Téléchargement manuel de phpMyAdmin…"
cd /var/www/html
PHPMYADMIN_VERSION="5.2.1"
wget https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.tar.gz

echo "[+] Extraction de phpMyAdmin…"
tar xzf phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.tar.gz
rm -f phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.tar.gz
mv phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages phpmyadmin

echo "[+] Configuration de phpMyAdmin (blowfish secret)…"
cp phpmyadmin/config.sample.inc.php phpmyadmin/config.inc.php
BLOWFISH_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
awk -v key="$BLOWFISH_SECRET" '
  /blowfish_secret/ {
    print "$cfg[\"blowfish_secret\"] = \"" key "\";";
    next
  }
  { print }
' phpmyadmin/config.inc.php > phpmyadmin/config.inc.php.tmp && mv phpmyadmin/config.inc.php.tmp phpmyadmin/config.inc.php

chown -R apache:apache /var/www/html/phpmyadmin

echo "[+] phpMyAdmin installé et prêt."
echo "✅ MySQL + phpMyAdmin sont prêts."
echo "🌐 Accès phpMyAdmin : http://<adresse_IP_publique>/phpmyadmin"
echo "   Utilisateur : $REMOTE_ADMIN_USER"
echo "   Mot de passe : $REMOTE_ADMIN_PWD"
