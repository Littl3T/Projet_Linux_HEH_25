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
# 1. LVM pour /srv/www
# ────────────────────────────────────────────────────────────────
echo "[+] Installation de lvm2"
dnf install -y lvm2

DEVICES=(/dev/nvme1n1 /dev/nvme2n1)
VG_NAME="srv_vg"
LV_NAME="srv_lv"
MOUNT_POINT="/srv/www"
FSTAB="/etc/fstab"

echo "[+] Création des PVs sur ${DEVICES[*]}"
for dev in "${DEVICES[@]}"; do
  pvs --noheadings -o pv_name | grep -qw "$dev" || pvcreate -ff -y "$dev"
done

echo "[+] Création du VG '$VG_NAME'"
vgs --noheadings -o vg_name | grep -qw "$VG_NAME" || vgcreate "$VG_NAME" "${DEVICES[@]}"

echo "[+] Création du LV '$LV_NAME' (100%FREE)"
lvs --noheadings -o lv_name "$VG_NAME" | grep -qw "$LV_NAME" \
  || lvcreate -n "$LV_NAME" -l 100%FREE "$VG_NAME"

echo "[+] Formatage ext4 de /dev/$VG_NAME/$LV_NAME"
blkid -o value -s TYPE "/dev/$VG_NAME/$LV_NAME" 2>/dev/null \
  || mkfs.ext4 -F "/dev/$VG_NAME/$LV_NAME"

echo "[+] Montage permanent de /srv/www"
mkdir -p "$MOUNT_POINT"
grep -qxF "/dev/$VG_NAME/$LV_NAME $MOUNT_POINT ext4 defaults 0 2" "$FSTAB" \
  || echo "/dev/$VG_NAME/$LV_NAME $MOUNT_POINT ext4 defaults 0 2" >> "$FSTAB"
mount -a

# ────────────────────────────────────────────────────────────────
# 2. FTPS + HTTPD + PHP
# ────────────────────────────────────────────────────────────────
echo "[+] Installation vsftpd, httpd, PHP, firewalld"
dnf install -y vsftpd openssl firewalld httpd php php-mysqlnd php-mbstring php-xml php-cli php-common

echo "[+] Activation et ouverture des ports"
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

systemctl enable --now httpd

echo "[+] Ajout des droits d'accès pour le user backup"
sudo setfacl -R -m u:backup:rx /etc/httpd/sites-available
sudo setfacl -R -m u:backup:rx /srv/www

# ────────────────────────────────────────────────────────────────
# 3. Samba + NFS share
# ────────────────────────────────────────────────────────────────
echo "[+] Installation Samba et NFS"
dnf install -y samba samba-client nfs-utils

echo "[+] Création du groupe '$SHARED_GROUP'"
getent group "$SHARED_GROUP" >/dev/null || groupadd "$SHARED_GROUP"

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
echo "  • HTTPD disponible sur /srv/www/<user>"
echo "  • Samba : \\\\\\$SERVER_IP\\public et \\\\\\$SERVER_IP\\www"
echo "  • NFS : mount $SERVER_IP:$SHARED_FOLDER /mnt"
