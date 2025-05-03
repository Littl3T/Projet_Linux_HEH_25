#!/bin/bash

# Script de déploiement FTP sécurisé (FTPS) avec vsftpd et HTTPD
# Chroot des utilisateurs dans /srv/www/$USER
# Compatible FileZilla avec TLS explicite

set -e

echo "[+] Installation des paquets nécessaires"
dnf install -y vsftpd openssl firewalld httpd

echo "[+] Activation du pare-feu et des ports nécessaires"
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=21/tcp
firewall-cmd --permanent --add-port=40000-40100/tcp
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

echo "[+] Création des dossiers pour les certificats SSL"
mkdir -p /etc/pki/tls/certs
mkdir -p /etc/pki/tls/private

echo "[+] Génération du certificat SSL auto-signé pour vsftpd"
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout /etc/pki/tls/private/vsftpd.key \
  -out /etc/pki/tls/certs/vsftpd.pem \
  -subj "/C=BE/ST=Hainaut/L=Mons/O=FTPServer/OU=IT/CN=$(curl -s ifconfig.me)"

echo "[+] Configuration de vsftpd"
cat > /etc/vsftpd/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/srv/www/\$USER
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES
ssl_enable=YES
rsa_cert_file=/etc/pki/tls/certs/vsftpd.pem
rsa_private_key_file=/etc/pki/tls/private/vsftpd.key
force_local_logins_ssl=YES
force_local_data_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=13.53.136.242
pam_service_name=vsftpd
userlist_enable=NO
EOF

# Configuration HTTPD
mkdir -p /etc/httpd/sites-available /etc/httpd/sites-enabled

# Activation de l'inclusion des vhosts
if ! grep -q 'sites-enabled' /etc/httpd/conf/httpd.conf; then
  echo "IncludeOptional sites-enabled/*.conf" >> /etc/httpd/conf/httpd.conf
fi

echo "[+] Activation des services vsftpd et httpd"
systemctl enable vsftpd httpd
systemctl restart vsftpd httpd

echo "[+] Déploiement FTP & HTTPD terminé."
