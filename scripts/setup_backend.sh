#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Variables
# ────────────────────────────────────────────────────────────────
NEW_ROOT_PWD="Toto123*"
REMOTE_ADMIN_USER="admin"
REMOTE_ADMIN_PWD="AdminStrongPwd!2025"

# Disques à utiliser pour LVM
DEVICES=(/dev/nvme1n1 /dev/nvme2n1)
VG_NAME="mysql_vg"
LV_NAME="mysql_lv"
MOUNT_POINT="/var/lib/mysql"
FSTAB="/etc/fstab"

# ────────────────────────────────────────────────────────────────
# 1. Préparation du LVM et montage /var/lib/mysql
# ────────────────────────────────────────────────────────────────
echo "[+] Installation de lvm2"
dnf install -y lvm2

echo "[+] Création des Physical Volumes sur ${DEVICES[*]}"
for dev in "${DEVICES[@]}"; do
  # Si le PV n'existe pas encore
  if ! pvs --noheadings -o pv_name | grep -qx "$dev"; then
    echo "    → Nettoyage des signatures existantes sur $dev"
    wipefs -a "$dev"
    echo "    → Création du PV sur $dev"
    pvcreate -ff -y "$dev"
  else
    echo "    → PV existe déjà sur $dev, on skip"
  fi
done

echo "[+] Création du Volume Group $VG_NAME"
if ! vgs --noheadings -o vg_name | grep -qx "$VG_NAME"; then
  vgcreate "$VG_NAME" "${DEVICES[@]}"
else
  echo "    → VG $VG_NAME existe déjà, on skip"
fi

echo "[+] Création du Logical Volume $LV_NAME (100%FREE)"
if ! lvs --noheadings -o lv_name "$VG_NAME" | grep -qx "$LV_NAME"; then
  lvcreate -n "$LV_NAME" -l 100%FREE "$VG_NAME"
else
  echo "    → LV $LV_NAME existe déjà, on skip"
fi

echo "[+] Formatage ext4 du LV"
if ! blkid -o value -s TYPE "/dev/$VG_NAME/$LV_NAME" >/dev/null 2>&1; then
  mkfs.ext4 -F "/dev/$VG_NAME/$LV_NAME"
else
  echo "    → /dev/$VG_NAME/$LV_NAME est déjà formaté, on skip"
fi

echo "[+] Montage permanent de /dev/$VG_NAME/$LV_NAME sur $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
grep -qxF "/dev/$VG_NAME/$LV_NAME $MOUNT_POINT ext4 defaults 0 2" "$FSTAB" \
  || echo "/dev/$VG_NAME/$LV_NAME $MOUNT_POINT ext4 defaults 0 2" >> "$FSTAB"
mount -a


# ────────────────────────────────────────────────────────────────
# 2. Installation et configuration de MySQL
# ────────────────────────────────────────────────────────────────
echo "[+] Installation du dépôt MySQL Community…"
wget -q https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2023
dnf install -y mysql80-community-release-el9-1.noarch.rpm

echo "[+] Installation du serveur MySQL Community…"
dnf install -y mysql-community-server

echo "[+] Activation et démarrage de mysqld…"
# Le data dir est déjà monté, mysqld initialisera la base à cet emplacement
systemctl enable --now mysqld

echo "[+] Ajustement des permissions sur $MOUNT_POINT"
# L'utilisateur mysql doit pouvoir écrire
chown -R mysql:mysql "$MOUNT_POINT"

echo "[+] Récupération du mot de passe temporaire…"
TEMP_PWD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
if [[ -z "$TEMP_PWD" ]]; then
  echo "!! Impossible de trouver le mot de passe temporaire" >&2
  exit 1
fi

echo "[+] Sécurisation de l'installation et changement de mot de passe root…"
mysql --connect-expired-password -uroot -p"$TEMP_PWD" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$NEW_ROOT_PWD';
UNINSTALL COMPONENT 'file://component_validate_password';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\\_%';
FLUSH PRIVILEGES;
EOF

echo "[+] Création d'un utilisateur administrateur distant…"
mysql -uroot -p"$NEW_ROOT_PWD" <<EOF
CREATE USER IF NOT EXISTS '$REMOTE_ADMIN_USER'@'%' IDENTIFIED WITH mysql_native_password BY '$REMOTE_ADMIN_PWD';
GRANT ALL PRIVILEGES ON *.* TO '$REMOTE_ADMIN_USER'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# Crée le fichier .my.cnf avec les droits appropriés
echo "[+] Création d'un fichier .my.cnf"
sudo tee /root/.my.cnf > /dev/null <<EOF
[client]
user=$MYSQL_ADMIN_USER
password=$MYSQL_ADMIN_PWD
EOF

# Applique les bonnes permissions (lecture seule pour root)
sudo chmod 600 /root/.my.cnf

echo "[+] Configuration réseau (bind-address)…"
cat >> /etc/my.cnf.d/server.cnf <<CNF

[mysqld]
bind-address = 0.0.0.0
CNF

echo "[+] Redémarrage de MySQL…"
systemctl restart mysqld

# ────────────────────────────────────────────────────────────────
# 3. Installation d'Apache, PHP et phpMyAdmin
# ────────────────────────────────────────────────────────────────
echo "[+] Installation et configuration du pare-feu (firewalld)…"
dnf install -y firewalld
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

echo "[+] Installation de Apache, PHP et modules…"
dnf install -y httpd php php-mysqlnd php-json php-mbstring php-zip php-gd php-common
systemctl enable --now httpd

echo "[+] Téléchargement et installation de phpMyAdmin…"
cd /var/www/html
PHPMYADMIN_VERSION="5.2.1"
wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.tar.gz"
tar xzf "phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.tar.gz"
rm -f "phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.tar.gz"
mv "phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages" phpmyadmin

echo "[+] Configuration de phpMyAdmin (blowfish secret)…"
cp phpmyadmin/config.sample.inc.php phpmyadmin/config.inc.php
BLOWFISH_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
awk -v key="$BLOWFISH_SECRET" '
  /blowfish_secret/ {
    print "$cfg[\"blowfish_secret\"] = \"" key "\";";
    next
  }
  { print }
' phpmyadmin/config.inc.php > phpmyadmin/config.inc.php.tmp
mv phpmyadmin/config.inc.php.tmp phpmyadmin/config.inc.php
chown -R apache:apache /var/www/html/phpmyadmin

echo "✅ MySQL + phpMyAdmin prêts."
echo "🌐 Accès phpMyAdmin : http://<IP_SERVER>/phpmyadmin"
echo "   Admin distant : $REMOTE_ADMIN_USER / $REMOTE_ADMIN_PWD"
