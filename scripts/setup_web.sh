#!/bin/bash
set -euo pipefail

##################################
# -1. Installer LVM / dépendances
##################################
echo "[+] Installation des paquets LVM et autres dépendances"
dnf install -y lvm2

##################################
# 0. Variables LVM et montage
##################################
DEVICES=(/dev/nvme1n1 /dev/nvme2n1)
VG_NAME="srv_vg"
LV_NAME="srv_lv"
MOUNT_POINT="/srv/www"
FSTAB="/etc/fstab"

##################################
# 1. Préparation LVM pour /srv/www
##################################
echo "[+] Création des PVs"
for dev in "${DEVICES[@]}"; do
  if ! pvs --noheadings -o pv_name | grep -qw "$dev"; then
    pvcreate -ff -y "$dev"
  fi
done

echo "[+] Création du VG '$VG_NAME'"
if ! vgs --noheadings -o vg_name | grep -qw "$VG_NAME"; then
  vgcreate "$VG_NAME" "${DEVICES[@]}"
fi

echo "[+] Création du LV '$LV_NAME' (100% du VG)"
if ! lvs --noheadings -o lv_name "$VG_NAME" | grep -qw "$LV_NAME"; then
  lvcreate -n "$LV_NAME" -l 100%FREE "$VG_NAME"
fi

echo "[+] Formatage en ext4 (/dev/$VG_NAME/$LV_NAME)"
if ! blkid -o value -s TYPE "/dev/$VG_NAME/$LV_NAME"; then
  mkfs.ext4 -F "/dev/$VG_NAME/$LV_NAME"
fi

echo "[+] Création du point de montage '$MOUNT_POINT' et mise à jour de fstab"
mkdir -p "$MOUNT_POINT"
grep -qxF "/dev/$VG_NAME/$LV_NAME $MOUNT_POINT ext4 defaults 0 2" "$FSTAB" \
  || echo "/dev/$VG_NAME/$LV_NAME $MOUNT_POINT ext4 defaults 0 2" >> "$FSTAB"

echo "[+] Montage de /srv/www"
mount -a

##################################
# 2. Installation FTPS + HTTPD + PHP
##################################
echo "[+] Installation des paquets nécessaires"
dnf install -y vsftpd openssl firewalld httpd php php-mysqlnd php-mbstring php-xml php-cli php-common

echo "[+] Activation et configuration du pare-feu"
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=21/tcp
firewall-cmd --permanent --add-port=40000-40100/tcp
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

##################################
# 3. Certificat SSL FTPS
##################################
echo "[+] Préparation des répertoires SSL"
mkdir -p /etc/pki/tls/certs /etc/pki/tls/private

echo "[+] Génération d'un certificat auto-signé"
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout /etc/pki/tls/private/vsftpd.key \
  -out /etc/pki/tls/certs/vsftpd.pem \
  -subj "/C=BE/ST=Hainaut/L=Mons/O=FTPServer/OU=IT/CN=$(curl -s ifconfig.me)"

##################################
# 4. Configuration vsftpd
##################################
echo "[+] Écriture de /etc/vsftpd/vsftpd.conf"
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
pasv_address=$(curl -s ifconfig.me)
pam_service_name=vsftpd
userlist_enable=NO
EOF

systemctl enable --now vsftpd

##################################
# 5. Configuration HTTPD + PHP
##################################
echo "[+] Préparation des sites Apache"
mkdir -p /etc/httpd/sites-available /etc/httpd/sites-enabled
grep -q '^IncludeOptional sites-enabled' /etc/httpd/conf/httpd.conf \
  || echo "IncludeOptional sites-enabled/*.conf" >> /etc/httpd/conf/httpd.conf

systemctl enable --now httpd

echo "✅ Déploiement terminé — /srv/www est désormais sur un LV LVM séparé."
