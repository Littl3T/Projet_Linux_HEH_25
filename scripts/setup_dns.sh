#!/bin/bash

set -euo pipefail

# Load variables from setup_env.sh file
if [ ! -f "setup_env.sh" ]; then
  echo "❌ setup_env.sh file not found. Create one with the necessary variables."
  exit 1
else
  source setup_env.sh
fi

# Required environment variables
: "${DNS_DOMAIN:?DNS_DOMAIN is not set}"
: "${DNS_HOSTNAME:?DNS_HOSTNAME is not set}"
: "${DNS_PRIVATE_IP:?DNS_PRIVATE_IP is not set}"
: "${WEB_PUBLIC_IP:?WEB_PUBLIC_IP is not set}"
: "${ZONE_DIR:?ZONE_DIR is not set}"

# Date-based serial generator
SERIAL=$(date +%Y%m%d)01

# Install BIND
sudo dnf install -y bind bind-utils || sudo apt install -y bind9 dnsutils

# Extract reverse zone name from DNS_PRIVATE_IP (e.g. 172.31.5.243 → 5.31.172.in-addr.arpa)
REVERSE_ZONE=$(echo $DNS_PRIVATE_IP | awk -F. '{print $2 "." $1 ".in-addr.arpa"}')

# Create named.conf
sudo tee /etc/named.conf > /dev/null <<EOF
options {
    directory "$ZONE_DIR";
    allow-query { any; };
    recursion yes;
    dnssec-validation auto;
};

dnssec-policy "default-policy" {
    keys {
        ksk lifetime P10Y algorithm RSASHA256;
        zsk lifetime P1Y algorithm RSASHA256;
    };
};

zone "$DNS_DOMAIN" IN {
    type master;
    file "forward.$DNS_DOMAIN";
    dnssec-policy "default-policy";
    inline-signing yes;
};

zone "$REVERSE_ZONE" IN {
    type master;
    file "reverse.$DNS_DOMAIN";
    dnssec-policy "default-policy";
    inline-signing yes;
};
EOF

# Create forward zone file
REVERSE_FILE="$ZONE_DIR/forward.$DNS_DOMAIN"

sudo tee "$REVERSE_FILE" > /dev/null <<EOF
\$TTL 86400
@   IN  SOA $DNS_HOSTNAME.$DNS_DOMAIN. root.$DNS_DOMAIN. (
        $SERIAL ; Serial
        3600       ; Refresh
        1800       ; Retry
        604800     ; Expire
        86400 )    ; Minimum TTL

    IN  NS $DNS_HOSTNAME.$DNS_DOMAIN.
$DNS_HOSTNAME IN A $DNS_PRIVATE_IP
www IN A $WEB_PUBLIC_IP
EOF

# Create reverse zone file (basic manual reverse)
REVERSE_FILE="$ZONE_DIR/reverse.$DNS_DOMAIN"
REV_NS_LAST=$(echo $DNS_PRIVATE_IP | awk -F. '{print $4}')
REV_WWW_LAST=$(echo $WEB_PUBLIC_IP | awk -F. '{print $4}')

sudo tee "$REVERSE_FILE" > /dev/null <<EOF
\$TTL 86400
@   IN  SOA $DNS_HOSTNAME.$DNS_DOMAIN. root.$DNS_DOMAIN. (
        $SERIAL ; Serial
        3600       ; Refresh
        1800       ; Retry
        604800     ; Expire
        86400 )    ; Minimum TTL

    IN  NS $DNS_HOSTNAME.$DNS_DOMAIN.
$REV_NS_LAST IN PTR $DNS_HOSTNAME.$DNS_DOMAIN.
$REV_WWW_LAST IN PTR www.$DNS_DOMAIN.
EOF

# Set permissions
sudo chown named:named $ZONE_DIR/forward.$DNS_DOMAIN
sudo chown named:named $REVERSE_FILE

# Restart named
sudo systemctl enable named
sudo systemctl restart named

# Print success
echo "✅ BIND DNS setup complete with zone $DNS_DOMAIN and serial $SERIAL."
