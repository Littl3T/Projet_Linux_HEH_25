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
# 6.  Backend server (mysql)      #
###################################
export BACKEND_HOSTNAME="mysql-01"
export BACKEND_PRIVATE_IP="10.42.0.170"