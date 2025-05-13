#!/bin/bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# 0. Chargement des variables d'environnement
# ────────────────────────────────────────────────────────────────
if [ ! -f "setup_env.sh" ]; then
  echo "❌ setup_env.sh introuvable. Crée-le avec ces variables :"
  echo "   DNS_DOMAIN, DNS_HOSTNAME, DNS_PRIVATE_IP, WEB_PRIVATE_IP,"
  echo "   ZONE_DIR, PRIVATE_SUBNET_CIDR"
  exit 1
fi
source setup_env.sh

#   enlève tout \r traînant dans tes variables
for var in DNS_DOMAIN DNS_HOSTNAME DNS_PRIVATE_IP WEB_PRIVATE_IP ZONE_DIR PRIVATE_SUBNET_CIDR; do
  eval "$var"="${!var//$'\r'/}"
done

: "\${DNS_DOMAIN:?}"
: "\${DNS_HOSTNAME:?}"
: "\${DNS_PRIVATE_IP:?}"
: "\${WEB_PRIVATE_IP:?}"
: "\${ZONE_DIR:?}"
: "\${PRIVATE_SUBNET_CIDR:?}"

# ────────────────────────────────────────────────────────────────
# 1. Préparation du LVM pour les fichiers de zone DNS
# ────────────────────────────────────────────────────────────────
echo "[+] Installation de lvm2"
dnf install -y lvm2

DEVICES=(/dev/nvme1n1 /dev/nvme2n1)
VG_NAME="dns_vg"
LV_NAME="zone_lv"
FSTAB="/etc/fstab"

echo "[+] Création des Physical Volumes sur ${DEVICES[*]}"
for dev in "${DEVICES[@]}"; do
  # nettoyer signatures LVM si nécessaire
  wipefs -a "$dev" || true
  pvs --noheadings -o pv_name | grep -qw "$dev" || pvcreate -ff -y "$dev"
done

echo "[+] Création du Volume Group $VG_NAME"
vgs --noheadings -o vg_name | grep -qw "$VG_NAME" || vgcreate "$VG_NAME" "${DEVICES[@]}"

echo "[+] Création du Logical Volume $LV_NAME (100%FREE)"
lvs --noheadings -o lv_name "$VG_NAME" | grep -qw "$LV_NAME" \
  || lvcreate -n "$LV_NAME" -l 100%FREE "$VG_NAME"

echo "[+] Formatage ext4 du LV"
blkid -o value -s TYPE "/dev/$VG_NAME/$LV_NAME" 2>/dev/null \
  || mkfs.ext4 -F "/dev/$VG_NAME/$LV_NAME"

echo "[+] Montage permanent de /dev/$VG_NAME/$LV_NAME sur $ZONE_DIR"
mkdir -p "$ZONE_DIR"
grep -qxF "/dev/$VG_NAME/$LV_NAME $ZONE_DIR ext4 defaults 0 2" "$FSTAB" \
  || echo "/dev/$VG_NAME/$LV_NAME $ZONE_DIR ext4 defaults 0 2" >> "$FSTAB"
mount -a

# ────────────────────────────────────────────────────────────────
# 2. Installation et configuration de BIND
# ────────────────────────────────────────────────────────────────
echo "[+] Installation de BIND"
dnf install -y bind bind-utils || apt-get install -y bind9 dnsutils

SERIAL=$(date +%Y%m%d)01
REVERSE_ZONE=$(echo "$DNS_PRIVATE_IP" | awk -F. '{print $2 "." $1 ".in-addr.arpa"}')

# named.conf principal
tee /etc/named.conf > /dev/null <<EOF
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

FORWARD_FILE="$ZONE_DIR/forward.$DNS_DOMAIN"
REVERSE_FILE="$ZONE_DIR/reverse.$DNS_DOMAIN"
REV_NS_LAST=$(echo "$DNS_PRIVATE_IP" | awk -F. '{print $4}')
REV_WWW_LAST=$(echo "$WEB_PRIVATE_IP"  | awk -F. '{print $4}')
REV_BACKEND_LAST=$(echo "$BACKEND_PRIVATE_IP"  | awk -F. '{print $4}')
REV_BACKUP_LAST=$(echo "$BACKUP_PRIVATE_IP"  | awk -F. '{print $4}')

tee "$FORWARD_FILE" > /dev/null <<EOF
\$TTL 86400
@   IN  SOA $DNS_HOSTNAME.$DNS_DOMAIN. root.$DNS_DOMAIN. (
        $SERIAL ; Serial
        3600    ; Refresh
        1800    ; Retry
        604800  ; Expire
        86400 ) ; Minimum TTL

    IN  NS  $DNS_HOSTNAME.$DNS_DOMAIN.
$DNS_HOSTNAME IN A $DNS_PRIVATE_IP
www           IN A $WEB_PRIVATE_IP
$BACKEND_HOSTNAME IN A $BACKEND_PRIVATE_IP
$WEB_HOSTNAME IN A $WEB_PRIVATE_IP
$BACKUP_HOSTNAME IN A $BACKUP_PRIVATE_IP
EOF

tee "$REVERSE_FILE" > /dev/null <<EOF
\$TTL 86400
@   IN  SOA $DNS_HOSTNAME.$DNS_DOMAIN. root.$DNS_DOMAIN. (
        $SERIAL ; Serial
        3600    ; Refresh
        1800    ; Retry
        604800  ; Expire
        86400 ) ; Minimum TTL

    IN  NS  $DNS_HOSTNAME.$DNS_DOMAIN.
$REV_NS_LAST IN PTR $DNS_HOSTNAME.$DNS_DOMAIN.
$REV_WWW_LAST IN PTR www.$DNS_DOMAIN.
$REV_BACKEND_LAST IN PTR $BACKEND_HOSTNAME.$DNS_DOMAIN.
$REV_NS_LAST IN PTR $BACKUP_HOSTNAME.$DNS_DOMAIN.
EOF

chown named:named "$REVERSE_FILE"
chown named:named "$FORWARD_FILE"
chown named:named "$ZONE_DIR"
chmod 750 "$ZONE_DIR"

systemctl enable named
systemctl restart named

echo "✅ Zones DNS installées et signées dans $ZONE_DIR (serial $SERIAL)."

# ────────────────────────────────────────────────────────────────
# 2.5. Configuration du pare-feu pour DNS
# ────────────────────────────────────────────────────────────────
echo "[+] Configuration du pare-feu pour DNS"

# S'assure que firewalld tourne
if ! systemctl is-active --quiet firewalld; then
  echo "ℹ️  Démarrage de firewalld…"
  systemctl enable --now firewalld
fi

# Ajoute le service DNS (53/TCP+UDP)
if ! firewall-cmd --permanent --list-services | grep -qw dns; then
  firewall-cmd --permanent --add-service=dns
  firewall-cmd --add-service=ntp --permanent
sudo firewall-cmd --reload

  echo "✅ Règle DNS ajoutée (service=dns)"
else
  echo "ℹ️  Le service DNS est déjà autorisé."
fi

# Recharge la configuration
firewall-cmd --reload
echo "✅ Pare-feu mis à jour pour DNS."

# ────────────────────────────────────────────────────────────────
# 3. Installation et configuration de Chrony (NTP)
# ────────────────────────────────────────────────────────────────
echo "[+] Installation de Chrony"
dnf install -y chrony || apt-get install -y chrony

echo "[+] Sauvegarde de la conf existante"
CONFIG="/etc/chrony.conf"
BACKUP="/etc/chrony.conf.bak"
[ -f "$BACKUP" ] || cp "$CONFIG" "$BACKUP"

echo "[+] Écriture de la configuration Chrony"
tee "$CONFIG" > /dev/null <<EOF
# Serveur NTP AWS interne
server 169.254.169.123 iburst

# Pool publics
server 0.europe.pool.ntp.org iburst
server 1.europe.pool.ntp.org iburst

# Autoriser la sync depuis ce sous-réseau
allow $PRIVATE_SUBNET_CIDR

# Fallback local
local stratum 8

makestep 1.0 3
rtcsync
driftfile /var/lib/chrony/drift
logdir /var/log/chrony
EOF

echo "[+] Activation et démarrage de chronyd"
systemctl enable chronyd
systemctl restart chronyd

echo "✅ Chrony configuré en serveur NTP pour $PRIVATE_SUBNET_CIDR."


# ────────────────────────────────────────────────────────────────
# 4. Droits d'accès pour le user backup
# ────────────────────────────────────────────────────────────────
echo "[+] Ajout des droits d'accès pour le user backup"
sudo setfacl -m u:backup:r /etc/named.conf
sudo setfacl -R -m u:backup:rx /var/named

# ────────────────────────────────────────────────────────────────
# Fin
# ────────────────────────────────────────────────────────────────
echo "🎉 Configuration DNS + NTP + stockage LVM terminée."
