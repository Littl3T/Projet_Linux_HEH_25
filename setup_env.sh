#!/usr/bin/env bash
###################################
# 0.  Global project identifiers  #
###################################
export PROJ_NAME="linux_heh_25"
export PROJ_DOMAIN="tomananas.lan"
export TZ="Europe/Brussels"
###################################
# 1.  VPC & network layout        #
###################################
export PRIVATE_SUBNET_CIDR="10.42.0.0/24"
###################################
# 2.  DNS server (Bind)           #
###################################
export DNS_HOSTNAME="dns-ntp-01"
export DNS_PRIVATE_IP="10.42.0.37"
export DNS_DOMAIN="${PROJ_DOMAIN}"
export ZONE_DIR="/srv/dns-zones"
###################################
# 3.  Web server (HTTPS)          #
###################################
export WEB_HOSTNAME="web-ftp-01"
export WEB_PRIVATE_IP="10.42.0.87"
###################################
# 4.  ntp server (chrony)         #
###################################
export NTP_PRIVATE_IP="10.42.0.37"
###################################
# 5.  FTP server (vsftpd)         #
###################################
export FTP_HOSTNAME="web-ftp-01"
export FTP_PRIVATE_IP="10.42.0.87"
###################################
# 6.  Samba                      #
###################################
export SHARED_FOLDER="/srv/share"
export SMB_CONF="/etc/samba/smb.conf"
export EXPORTS_FILE="/etc/exports"
export SHARED_GROUP="publicshare"
###################################
# 7.  Backend server (mysql)      #
###################################
export BACKEND_HOSTNAME="mysql-01"
export BACKEND_PRIVATE_IP="10.42.0.170"
###################################
# 8.  NFS client autofs           #
###################################
export NFS_PRIVATE_IP="10.42.0.207"
export MOUNT_ROOT="/mnt/nfs"
export MOUNT_NAME="share"  
export TIMEOUT=60
export AUTO_MASTER="/etc/auto.master"
export AUTO_MAP="/etc/auto.nfs"
###################################
# 8.  Backup                      #
###################################
export BACKUP_HOSTNAME="admin-backup-01"
export BACKUP_PRIVATE_IP="10.42.0.113"
export BACKUP_HOME="/home/backup"
export REMOTE_USER="backup"
export SSH_KEY="$BACKUP_HOME/scripts/labsuser.pem"
export WEB_HOST="${WEB_HOSTNAME}.${PROJ_DOMAIN}"
export DNS_HOST="${DNS_HOSTNAME}.${PROJ_DOMAIN}"
export DB_HOST="${BACKEND_HOSTNAME}.${PROJ_DOMAIN}"
export WEB_FILES=(/etc/httpd/sites-available/ /srv/www/)
export DNS_FILES=(/etc/named.conf /var/named/)
###################################
# 9.  Quotas                      #
###################################
export SOFT_LIMIT=50000
export HARD_LIMIT=60000

