#!/usr/bin/env bash

###################################
# 0.  Global project identifiers  #
###################################
export PROJ_NAME="linux_heh_25"      # Used in tags & resource names
export PROJ_DOMAIN="tomananas.lan"   # DNS zone
export TZ="Europe/Brussels"          # VM timezone

###################################
# 1.  VPC & network layout        #
###################################
export PRIVATE_SUBNET_CIDR="172.31.0.0/20"

###################################
# 2.  Bastion host (public SSH)   #
###################################
export BASTION_HOSTNAME="bastion-01"
export BASTION_PUBLIC_IP="198.51.100.10"   # ⇦ remplace par ton Elastic IP
export BASTION_PRIVATE_IP="10.0.0.10"

###################################
# 3.  DNS server (Bind)           #
###################################
export DNS_HOSTNAME="dns-ntp-01"
export DNS_PRIVATE_IP="172.31.15.99"
export DNS_PUBLIC_IP="13.53.60.206"
export DNS_DOMAIN="${PROJ_DOMAIN}"
export ZONE_DIR="/var/named"

###################################
# 4.  Web server (HTTPS)          #
###################################
export WEB_HOSTNAME="web-ftp-04"
export WEB_PRIVATE_IP="10.0.1.4"
export WEB_PUBLIC_IP="13.49.221.174"
export WEB_DOCROOT="/var/www/html"

###################################
# 5.  FTP server (vsftpd)         #
###################################
export FTP_HOSTNAME="ftp-01"
export FTP_PRIVATE_IP="10.0.1.5"
export FTP_PUBLIC_IP="198.51.100.40"
export FTP_PASV_MIN="42000"
export FTP_PASV_MAX="43000"
export FTP_UPLOAD_GROUP="ftp_upload_access"
export FTP_TLS_ENABLE="yes"          # yes | no

###################################
# 6.  Certificate Authority (Step CA)
###################################
export CA_HOSTNAME="ca-01"
export CA_PRIVATE_IP="10.0.1.6"
export CA_PUBLIC_IP="198.51.100.50"
export CA_PORT="9000"                # step-ca listen port

###################################
# 7.  Database (MariaDB)          #
###################################
export DB_HOSTNAME="db-01"
export DB_PRIVATE_IP="10.0.1.7"
export DB_PUBLIC_IP=""              # vide ⇒ DB uniquement interne
export DB_PORT="3306"

###################################
# 8.  Security Group identifiers  #
###################################
export SG_DNS="sg-dns"              # names or IDs; referenced by Terraform/CLI
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