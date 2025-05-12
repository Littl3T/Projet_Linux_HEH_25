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
export DNS_HOSTNAME="Server2"
export DNS_PRIVATE_IP="10.42.0.37"
export DNS_DOMAIN="${PROJ_DOMAIN}"
export ZONE_DIR="/srv/dns-zones"
###################################
# 3.  Web server (HTTPS)          #
###################################
export WEB_HOSTNAME="Server1"
export WEB_PRIVATE_IP="10.42.0.87"
###################################
# 5.  FTP server (vsftpd)         #
###################################
export FTP_HOSTNAME="Server1"
export FTP_PRIVATE_IP="10.42.0.87"
export FTP_PASV_MIN="42000"
export FTP_PASV_MAX="43000"
export FTP_UPLOAD_GROUP="ftp_upload_access"
export FTP_TLS_ENABLE="yes"
###################################
# 6.  Certificate Authority (Step CA)
###################################
export CA_HOSTNAME="ca-01"
export CA_PRIVATE_IP="10.0.1.6"
export CA_PUBLIC_IP="198.51.100.50"
export CA_PORT="9000"
###################################
# 7.  Database (MariaDB)          #
###################################
export DB_HOSTNAME="db-01"
export DB_PRIVATE_IP="10.0.1.7"
export DB_PUBLIC_IP=""
export DB_PORT="3306"
###################################
# 8.  Security Group identifiers  #
###################################
export SG_DNS="sg-dns"
export SG_WEB="sg-web"
export SG_FTP="sg-ftp"
export SG_CA="sg-ca"
export SG_BASTION="sg-bastion"
###################################
# 9.  Constant ports              #
###################################
export PORT_DNS="53"
export PORT_WEB_HTTPS="443"
export PORT_FTP_COMMAND="21"
export PORT_FTP_PASV_RANGE="${FTP_PASV_MIN}-${FTP_PASV_MAX}"
export PORT_CA_API="${CA_PORT}"