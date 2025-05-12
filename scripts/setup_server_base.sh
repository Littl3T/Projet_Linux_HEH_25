#!/bin/bash
set -euo pipefail

# === 🔧 Variables à modifier si besoin ===
DNS_IP="172.31.5.243"
DOMAIN="tomananas.lan"
NTP_SERVER="172.31.5.243"
ROOT_DEFAULT_PASSWORD="Tomval03+-"

# === 🧠 Début du script ===

# Définition du hostname (interactif avec valeur par défaut)
read -rp "🖥️  Entrez le hostname souhaité: " NEW_HOSTNAME
NEW_HOSTNAME=${NEW_HOSTNAME}

echo "[+] Définition du hostname : $NEW_HOSTNAME"
sudo hostnamectl set-hostname "$NEW_HOSTNAME"

# Configuration DNS (/etc/resolv.conf)
echo "[+] Configuration DNS pour rejoindre le domaine $DOMAIN"
echo -e "nameserver $DNS_IP\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null

# === Configuration NTP (chrony) ===
echo "[+] Installation et configuration du client NTP (chrony)"
sudo dnf install -y chrony

# Configuration complète du fichier chrony.conf
sudo tee /etc/chrony.conf > /dev/null <<EOF
# Use the private NTP server (Chrony server internal IP in AWS ntp-01)
server $NTP_SERVER iburst

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

# Afficher les sources NTP
sleep 2
chronyc sources || echo "⚠️ chronyc failed, vérifiez la connectivité NTP"


# Installation de fail2ban
echo "[+] Installation et activation de fail2ban"
sudo dnf install -y fail2ban
sudo bash -c 'cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
EOF'
sudo systemctl enable --now fail2ban

# Pare-feu (firewalld)
echo "[+] Installation et configuration de firewalld"
sudo dnf install -y firewalld
sudo systemctl enable --now firewalld

if ! sudo firewall-cmd --list-services | grep -qw ssh; then
    sudo firewall-cmd --permanent --add-service=ssh
    echo "✅ Règle SSH ajoutée au firewall"
fi

sudo firewall-cmd --reload

echo "[+] Configuration du user de backup"
sudo useradd -m -s /bin/bash backup 2>/dev/null || echo "User 'backup' already exists"
sudo mkdir -p /home/backup/.ssh
sudo chmod 700 /home/backup/.ssh
sudo cp /home/ec2-user/.ssh/authorized_keys /home/backup/.ssh/authorized_keys 
sudo chown -R backup:backup /home/backup/.ssh

# Mot de passe root
echo "[+] Définition du mot de passe root par défaut"
echo "root:$ROOT_DEFAULT_PASSWORD" | sudo chpasswd

echo "✅ Setup de base terminé pour $NEW_HOSTNAME"
