#!/bin/bash
set -euo pipefail


# === Chargement des variables d'environnement ===

if [ ! -f "setup_env.sh" ]; then
  echo "❌ setup_env.sh introuvable. Crée-le avec ces variables :"
  echo "   DNS_PRIVATE_IP, PROJ_DOMAIN, NTP_PRIVATE_IP"
  exit 1
fi
source setup_env.sh

#   enlève tout \r traînant dans tes variables
for var in DNS_PRIVATE_IP PROJ_DOMAIN NTP_PRIVATE_IP; do
  eval "$var"="${!var//$'\r'/}"
done

: "\${DNS_PRIVATE_IP:?}"
: "\${PROJ_DOMAIN:?}"
: "\${NTP_PRIVATE_IP:?}"

# === 🧠 Début du script ===
# Définition du hostname
read -rp "🖥️  Entrez le hostname souhaité: " NEW_HOSTNAME
NEW_HOSTNAME=${NEW_HOSTNAME}
# Définition du password
read -rp "🖥️  Entrez le mot de passe souhaité: " ROOT_DEFAULT_PASSWORD
ROOT_DEFAULT_PASSWORD=${ROOT_DEFAULT_PASSWORD}

echo "[+] Définition du hostname : $NEW_HOSTNAME"
sudo hostnamectl set-hostname "$NEW_HOSTNAME"

# Configuration DNS (/etc/resolv.conf)
echo "[+] Configuration DNS pour rejoindre le domaine $PROJ_DOMAIN"
echo -e "nameserver $DNS_PRIVATE_IP\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null

# === Configuration NTP (chrony) ===
echo "[+] Installation et configuration du client NTP (chrony)"
sudo dnf install -y chrony

# Configuration complète du fichier chrony.conf
sudo tee /etc/chrony.conf > /dev/null <<EOF
# Use the private NTP server (Chrony server internal IP in AWS ntp-01)
server $NTP_PRIVATE_IP iburst

# Step the system clock if the offset is too large (up to 3 times)
makestep 1.0 3

# Synchronize the system clock with the hardware clock (RTC)
rtcsync

# Record frequency offset to improve sync after reboot
driftfile /var/lib/chrony/drift

# Enable logging (useful for debugging sync issues)
logdir /var/log/chrony
EOF

# Activer et démarrer chronyd
sudo systemctl enable --now chronyd

# Configuration de fuseau horaire
echo "[+] Configuration du fuseau horaire : Europe/Brussels"
sudo timedatectl set-timezone Europe/Brussels

# Afficher les sources NTP
sleep 2
chronyc sources || echo "⚠️ chronyc failed, vérifiez la connectivité NTP"

# === Installation et activation de fail2ban ===
echo "[+] Installation et activation de fail2ban"
sudo dnf install -y fail2ban
sudo bash -c 'cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
EOF'
sudo systemctl enable --now fail2ban

# === Pare-feu (firewalld) ===
echo "[+] Installation et configuration de firewalld"
sudo dnf install -y firewalld
sudo systemctl enable --now firewalld

if ! sudo firewall-cmd --list-services | grep -qw ssh; then
    sudo firewall-cmd --permanent --add-service=ssh
    echo "✅ Règle SSH ajoutée au firewall"
fi

sudo firewall-cmd --reload

# === Configuration du user de backup ===
echo "[+] Configuration du user de backup"
sudo useradd -m -s /bin/bash backup 2>/dev/null || echo "User 'backup' already exists"
sudo mkdir -p /home/backup/.ssh
sudo chmod 700 /home/backup/.ssh
sudo cp /home/ec2-user/.ssh/authorized_keys /home/backup/.ssh/authorized_keys 
sudo chown -R backup:backup /home/backup/.ssh

# === Mot de passe root ===
echo "[+] Définition du mot de passe root par défaut"
echo "root:$ROOT_DEFAULT_PASSWORD" | sudo chpasswd

# ────────────────────────────────────────────────────────────────
# Installation & enregistrement automatique sur Netdata Cloud
# ────────────────────────────────────────────────────────────────
echo "[+] Installation de Netdata avec inscription sur Netdata Cloud"
curl https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh && sh /tmp/netdata-kickstart.sh --stable-channel --claim-token qLJ6N91iNhe9fyPhWzVe0AjWnM3895IwOJam2iApYmHgyiDW1qwvk3CT46VZKGPxdHZpppc4EZ6u2ve0Br0zYwZ5sETWCxStRXXbiI1P-eVvsmDzVlAm9VPFYK6Je89BM96SYxY --claim-rooms 3db515f7-2058-48a3-b3f8-0c0ef773d79f --claim-url https://app.netdata.cloud

echo "[+] Activation du service Netdata"
systemctl enable --now netdata

echo "[+] Ouverture du port Netdata (19999)"
firewall-cmd --permanent --add-port=19999/tcp
firewall-cmd --reload

cat <<INFO

✅ Netdata installé et enregistré automatiquement sur Netdata Cloud !

Si jamais vous voulez changer de token ou de Space,  
modifiez simplement les valeurs de --claim-xxxx dans ce script.

INFO


echo "✅ Setup de base terminé pour $NEW_HOSTNAME"
