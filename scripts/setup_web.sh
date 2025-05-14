#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Prérequis: root + /root/setup_env.sh
# ────────────────────────────────────────────────────────────────
if [[ $(id -u) -ne 0 ]]; then
  echo "❌ Ce script doit être lancé en root."
  exit 1
fi

if [ ! -f /root/setup_env.sh ]; then
  echo "❌ /root/setup_env.sh introuvable."
  exit 1
fi
source /root/setup_env.sh

: "${PRIVATE_SUBNET_CIDR:?PRIVATE_SUBNET_CIDR non défini}"
: "${SHARED_FOLDER:?SHARED_FOLDER non défini}"
: "${SMB_CONF:?SMB_CONF non défini}"
: "${EXPORTS_FILE:?EXPORTS_FILE non défini}"
: "${SHARED_GROUP:?SHARED_GROUP non défini}"
: "${FTP_PRIVATE_IP:?FTP_PRIVATE_IP non défini}"

# ────────────────────────────────────────────────────────────────
# 1. LVM pour /srv/www et /srv/share (avec quotas)
# ────────────────────────────────────────────────────────────────
echo "[+] Installation de lvm2"
dnf install -y lvm2

# Disques dédiés
DEV_WWW="/dev/nvme1n1"
DEV_SHARE="/dev/nvme2n1"

# PVs
echo "[+] Création des PVs : $DEV_WWW → srv_vg, $DEV_SHARE → share_vg"
for dev in "$DEV_WWW" "$DEV_SHARE"; do
  pvs --noheadings -o pv_name | grep -qw "$dev" || pvcreate -ff -y "$dev"
done

# VG + LV pour /srv/www
VG_WWW="srv_vg"
LV_WWW="srv_lv"
MOUNT_POINT="/srv/www"
echo "[+] Création VG $VG_WWW sur $DEV_WWW"
vgs --noheadings -o vg_name | grep -qw "$VG_WWW" || vgcreate "$VG_WWW" "$DEV_WWW"
echo "[+] Création LV $LV_WWW (100%FREE) → $MOUNT_POINT"
lvs --noheadings -n "$LV_WWW" "$VG_WWW" &>/dev/null || \
  lvcreate -n "$LV_WWW" -l 100%FREE "$VG_WWW"
echo "[+] Formatage ext4 de /dev/$VG_WWW/$LV_WWW"
blkid -o value -s TYPE "/dev/$VG_WWW/$LV_WWW" &>/dev/null || \
  mkfs.ext4 -F "/dev/$VG_WWW/$LV_WWW"

# VG + LV pour /srv/share
VG_SHARE="share_vg"
LV_SHARE="share_lv"
SHARE_MNT="$SHARED_FOLDER"
echo "[+] Création VG $VG_SHARE sur $DEV_SHARE"
vgs --noheadings -o vg_name | grep -qw "$VG_SHARE" || vgcreate "$VG_SHARE" "$DEV_SHARE"
echo "[+] Création LV $LV_SHARE (100%FREE) → $SHARE_MNT"
lvs --noheadings -n "$LV_SHARE" "$VG_SHARE" &>/dev/null || \
  lvcreate -n "$LV_SHARE" -l 100%FREE "$VG_SHARE"
echo "[+] Formatage ext4 de /dev/$VG_SHARE/$LV_SHARE avec quotas"
blkid -o value -s TYPE "/dev/$VG_SHARE/$LV_SHARE" &>/dev/null || \
  mkfs.ext4 -F -O quota /dev/$VG_SHARE/$LV_SHARE

# Montage
echo "[+] Montage permanent de $MOUNT_POINT et $SHARE_MNT"
mkdir -p "$MOUNT_POINT" "$SHARE_MNT"
grep -qxF "/dev/$VG_WWW/$LV_WWW $MOUNT_POINT ext4 defaults 0 2" /etc/fstab \
  || echo "/dev/$VG_WWW/$LV_WWW $MOUNT_POINT ext4 defaults 0 2" >> /etc/fstab
grep -qxF "/dev/$VG_SHARE/$LV_SHARE $SHARE_MNT ext4 defaults,usrquota,grpquota 0 2" /etc/fstab \
  || echo "/dev/$VG_SHARE/$LV_SHARE $SHARE_MNT ext4 defaults,usrquota,grpquota 0 2" >> /etc/fstab
mount -a

# Initialisation des quotas sur /srv/share
echo "[+] Initialisation des quotas sur $SHARE_MNT"
quotacheck -fgum "$SHARE_MNT"
quotaon "$SHARE_MNT"
echo "✅ /srv/www et /srv/share sont prêts (quotas actifs sur $SHARE_MNT)"


# ────────────────────────────────────────────────────────────────
# 2. FTPS + HTTPD + PHP
# ────────────────────────────────────────────────────────────────
echo "[+] Installation vsftpd, httpd, PHP, firewalld"
dnf install -y vsftpd openssl firewalld httpd php php-mysqlnd php-mbstring php-xml php-cli php-common

echo "[+] Activation et ouverture des ports HTTP/FTP"
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=21/tcp
firewall-cmd --permanent --add-port=40000-40100/tcp
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

echo "[+] Génération certificat SSL pour FTPS"
mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout /etc/pki/tls/private/vsftpd.key \
  -out /etc/pki/tls/certs/vsftpd.pem \
  -subj "/C=BE/ST=Hainaut/L=Mons/O=FTPServer/OU=IT/CN=$(curl -s ifconfig.me)"

echo "[+] Configuration vsftpd"
cat > /etc/vsftpd/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=$MOUNT_POINT/\$USER
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES
ssl_enable=YES
rsa_cert_file=/etc/pki/tls/certs/vsftpd.pem
rsa_private_key_file=/etc/pki/tls/private/vsftpd.key
force_local_logins_ssl=YES
force_local_data_ssl=YES
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=$FTP_PRIVATE_IP
pam_service_name=vsftpd
userlist_enable=NO
EOF

systemctl enable --now vsftpd

echo "[+] Activation Apache + inclusion vhosts"
mkdir -p /etc/httpd/sites-available /etc/httpd/sites-enabled
grep -q '^IncludeOptional sites-enabled' /etc/httpd/conf/httpd.conf \
  || echo "IncludeOptional sites-enabled/*.conf" >> /etc/httpd/conf/httpd.conf

# Désactiver le vhost SSL par défaut pour ne pas ouvrir 443 en double
if [ -f /etc/httpd/conf.d/ssl.conf ]; then
  mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.disabled
  echo "[+] ssl.conf par défaut désactivé"
fi

# S'assurer qu'on n'a pas plusieurs Listen 443
sed -i '/^Listen 443/d' /etc/httpd/conf/httpd.conf
grep -qxF 'Listen 443' /etc/httpd/conf/httpd.conf \
  || echo 'Listen 443' >> /etc/httpd/conf/httpd.conf

systemctl enable --now httpd

echo "[+] Ajout des droits d'accès pour le user backup"
sudo setfacl -R -m u:backup:rx /etc/httpd/sites-available
sudo setfacl -R -m u:backup:rx /srv/www

# ────────────────────────────────────────────────────────────────
# 2.5. VHost HTTP & HTTPS de fallback (catch-all)
# ────────────────────────────────────────────────────────────────
echo "[+] Création du site de fallback (404) dans /srv/www/default"
sudo mkdir -p /srv/www/default
sudo tee /srv/www/default/index.html > /dev/null <<'HTML'
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>tomananas.lan – Hébergement et Services</title>
  <style>
    body { font-family: 'Segoe UI', sans-serif; background: #f5f7fa; color: #333; margin: 0; padding: 0; }
    header { background: #005a9c; color: #fff; padding: 2em 1em; text-align: center; }
    main { max-width: 800px; margin: 2em auto; background: #fff; padding: 2em; box-shadow: 0 2px 8px rgba(0,0,0,0.1); border-radius: 8px; }
    h1 { margin-top: 0; font-size: 2em; color: white; }
    ul.services { list-style: none; padding: 0; }
    ul.services li { margin: 0.5em 0; padding-left: 1.5em; position: relative; }
    ul.services li:before { content: "✓"; position: absolute; left: 0; color: #28a745; }
    footer { text-align: center; padding: 1em; font-size: 0.9em; color: #666; }
    a { color: #005a9c; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <header>
    <h1>Bienvenue sur <strong>tomananas.lan</strong></h1>
    <p>Votre plateforme d’hébergement interne sécurisée</p>
  </header>
  <main>
    <p>Nous proposons une offre complète pour vos services Linux :</p>
    <ul class="services">
      <li>Hébergement FTP/FTPS sécurisé</li>
      <li>Sites web en HTTP & HTTPS</li>
      <li>Partage de fichiers via Samba & NFS</li>
      <li>Bases de données MySQL dédiées</li>
      <li>Antivirus & pare-feu configuré</li>
      <li>Alertes temps-réel via Netdata</li>
      <li>Backups automatisées et restaurations</li>
    </ul>
    <p>Pour toute demande, contactez :</p>
    <ul>
      <li><a href="mailto:tom.deneyer@std.heh.be">tom.deneyer@std.heh.be</a></li>
      <li><a href="mailto:anastasiia.kozlenko@std.heh.be">anastasiia.kozlenko@std.heh.be</a></li>
    </ul>
  </main>
  <footer>&copy; 2025 tomananas.lan — Tous droits réservés</footer>
</body>
</html>
HTML
sudo chmod -R 755 /srv/www/default

echo "[+] Configuration du fallback HTTP (000-default.conf)"
sudo tee /etc/httpd/sites-available/000-default.conf > /dev/null <<CONF
<VirtualHost *:80>
    ServerName fallback.${PROJ_DOMAIN}
    DocumentRoot /srv/www/default

    <Directory "/srv/www/default">
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>

    ErrorDocument 404 /index.html
</VirtualHost>
CONF
sudo ln -sf /etc/httpd/sites-available/000-default.conf \
            /etc/httpd/sites-enabled/000-default.conf

echo "[+] Configuration du fallback HTTPS (000-default-ssl.conf)"
sudo tee /etc/httpd/sites-available/000-default-ssl.conf > /dev/null <<CONF
<VirtualHost *:443>
    ServerName fallback.${PROJ_DOMAIN}
    DocumentRoot /srv/www/default

    SSLEngine on
    SSLCertificateFile    /etc/pki/tls/certs/wildcard.crt.pem
    SSLCertificateKeyFile /etc/pki/tls/private/wildcard.key.pem

    <Directory "/srv/www/default">
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>

    ErrorDocument 404 /index.html
</VirtualHost>
CONF
sudo ln -sf /etc/httpd/sites-available/000-default-ssl.conf \
            /etc/httpd/sites-enabled/000-default-ssl.conf

echo "[+] Reload Apache pour prendre en compte le fallback"
sudo systemctl reload httpd

# ────────────────────────────────────────────────────────────────
# 3. Samba + NFS share
# ────────────────────────────────────────────────────────────────
echo "[+] Installation Samba et NFS"
dnf install -y samba samba-client nfs-utils

echo "[+] Création du dossier public $SHARED_FOLDER"
mkdir -p "$SHARED_FOLDER"
chmod 2775 "$SHARED_FOLDER"
chown root:"$SHARED_GROUP" "$SHARED_FOLDER"

echo "[+] Écriture de la config Samba dans $SMB_CONF"
cat > "$SMB_CONF" <<EOF
[global]
  workgroup = WORKGROUP
  security = user
  map to guest = Bad User
  guest account = nobody
  server string = Samba + NFS Shared Server
  dns proxy = no

[www]
  path = $MOUNT_POINT/%U
  comment = Dossier web perso de %U
  valid users = %U
  browseable = no
  writable = yes
  create mask = 0700
  directory mask = 0700

[public]
  path = $SHARED_FOLDER
  comment = Partage public
  guest ok = yes
  browseable = yes
  writable = yes
  create mask = 0664
  directory mask = 2775
EOF

echo "[+] Activation des services smb/nmb"
systemctl enable --now smb nmb

echo "[+] Ouverture du firewall pour Samba"
firewall-cmd --permanent --add-service=samba
firewall-cmd --reload

echo "[+] Écriture de l’export NFS dans $EXPORTS_FILE"
grep -q "^$SHARED_FOLDER" "$EXPORTS_FILE" \
  && sed -i "s|^$SHARED_FOLDER.*|$SHARED_FOLDER $PRIVATE_SUBNET_CIDR(rw,sync,no_root_squash,no_subtree_check)|" "$EXPORTS_FILE" \
  || echo "$SHARED_FOLDER $PRIVATE_SUBNET_CIDR(rw,sync,no_root_squash,no_subtree_check)" >> "$EXPORTS_FILE"

exportfs -rav
echo "[+] Activation du service NFS"
systemctl enable --now nfs-server

echo "[+] Ouverture du firewall pour NFS"
firewall-cmd --permanent --add-service=nfs
firewall-cmd --permanent --add-service=mountd
firewall-cmd --permanent --add-service=rpc-bind
firewall-cmd --reload

SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "✅ Déploiement terminé !"
echo "  • FTPS disponible sur port 21 (TLS exigé)"
echo "  • HTTPD disponible sur /srv/www/<user> et en HTTPS sur port 443"
echo "  • Samba : \\\\\\$SERVER_IP\\public et \\\\\\$SERVER_IP\\www"
echo "  • NFS : mount $SERVER_IP:$SHARED_FOLDER /mnt"
