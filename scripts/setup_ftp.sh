#!/bin/bash

# Script de déploiement FTP sécurisé (FTPS) avec vsftpd
# Chroot des utilisateurs dans /srv/www/$USER
# Compatible FileZilla avec TLS explicite

set -e

echo "[+] Installation des paquets nécessaires"
dnf install -y vsftpd openssl firewalld

echo "[+] Activation du pare-feu et des ports nécessaires"
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=21/tcp
firewall-cmd --permanent --add-port=40000-40100/tcp
firewall-cmd --reload

echo "[+] Création des dossiers pour les certificats SSL"
mkdir -p /etc/pki/tls/certs
mkdir -p /etc/pki/tls/private

echo "[+] Génération du certificat SSL auto-signé"
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout /etc/pki/tls/private/vsftpd.key \
  -out /etc/pki/tls/certs/vsftpd.pem \
  -subj "/C=BE/ST=Hainaut/L=Mons/O=FTPServer/OU=IT/CN=$(curl -s ifconfig.me)"

echo "[+] Configuration de vsftpd"
cat > /etc/vsftpd/vsftpd.conf <<EOF
# Base
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES

# Répertoire web chrooté
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=$USER
local_root=/srv/www/$USER

# Journalisation
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES

# TLS (FTPS explicite)
ssl_enable=YES
rsa_cert_file=/etc/pki/tls/certs/vsftpd.pem
rsa_private_key_file=/etc/pki/tls/private/vsftpd.key
force_local_logins_ssl=YES
force_local_data_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO

# FTP passif
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=16.16.110.31
# PAM & liste d'utilisateurs
pam_service_name=vsftpd
userlist_enable=NO
EOF

echo "[+] Activation de vsftpd"
systemctl enable vsftpd
systemctl restart vsftpd

echo "[+] Déploiement terminé."
