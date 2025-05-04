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

# ⚠️ Modifier cette ligne pour restreindre l'accès uniquement à TON IP publique :
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --reload

echo "✅ MySQL est prêt."
echo "ℹ️  Connexion à distance via phpMyAdmin :"
echo "    Hôte      : <adresse_IP_publique>"
echo "    Utilisateur : $REMOTE_ADMIN_USER"
echo "    Mot de passe : $REMOTE_ADMIN_PWD"
