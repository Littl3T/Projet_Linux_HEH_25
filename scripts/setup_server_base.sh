#!/bin/bash
set -euo pipefail


# === Chargement des variables d'environnement ===

if [ ! -f "setup_env.sh" ]; then
  echo "❌ setup_env.sh introuvable. Crée-le avec ces variables :"
  echo "   DNS_PRIVATE_IP, PROJ_DOMAIN, NTP_PRIVATE_IP"
  exit 1
fi
source setup_env.sh

# enlève tout \r traînant dans tes variables
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
echo "🧹 Suppression de l'ancien /etc/resolv.conf..."
sudo rm -f /etc/resolv.conf
echo "📝 Rédaction d'une configuration DNS statique..."
echo -e "nameserver $DNS_PRIVATE_IP\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
echo "🔒 Protection de /etc/resolv.conf en écriture..."
sudo chattr +i /etc/resolv.conf
echo "✅ /etc/resolv.conf est protégé."

# === Configuration NTP (chrony) ===
echo "[+] Installation et configuration de Chrony"
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
    echo "✅ Règle SSH ajoutée"
fi

sudo firewall-cmd --reload

# === Antivirus (ClamAV + Linux Malware Detect) ===
# Demande des chemins à scanner
read -rp "🛡️  Entrez les chemins à scanner (séparés par des espaces) : " SCAN_PATHS
echo "[+] Dossiers à vérifier : $SCAN_PATHS"

# 1. Installation de ClamAV
echo "[+] Installation de ClamAV"
sudo dnf install -y clamav clamav-update

echo "[+] Configuration de freshclam (mise à jour des signatures)"
# décommente la ligne Example pour activer freshclam
sudo sed -i 's/^Example/#Example/' /etc/freshclam.conf
# mise à jour immédiate
sudo freshclam
sudo systemctl enable --now clamav-freshclam

# 2. Installation non-interactive de Linux Malware Detect
echo "[+] Installation de Linux Malware Detect (LMD)"
cd /opt
sudo dnf install -y wget unzip cronie                  # s’assure que wget/unzip/cron sont là
sudo wget -q https://www.rfxn.com/downloads/maldetect-current.tar.gz
sudo tar zxvf maldetect-current.tar.gz
DIR=$(tar tzf maldetect-current.tar.gz | head -1 | cut -d'/' -f1)
cd "$DIR"

echo "[+] Installation non-interactive de LMD (valeurs par défaut)"
yes '' | sudo ./install.sh

echo "[+] Configuration de LMD pour passer par ClamAV"
sudo sed -i 's/^scanner clamav$/scanner clamav --stdout/' /usr/local/maldetect/conf.maldet

# 3. Création du script de scan unifié
echo "[+] Création du script de scan /usr/local/bin/antivirus-scan.sh"
sudo tee /usr/local/bin/antivirus-scan.sh > /dev/null <<EOF
#!/usr/bin/env bash
# Mise à jour des signatures ClamAV
freshclam --quiet

# Scan ClamAV (via démon, multithread, ne remonte que les infectés)
clamdscan --fdpass --multiscan --infected $SCAN_PATHS

# Scan LMD
maldet --quiet --scan-all $SCAN_PATHS
EOF
sudo chmod +x /usr/local/bin/antivirus-scan.sh

# 4. Planification 2×/jour dans /etc/cron.d
echo "[+] Planification du scan 2×/jour dans /etc/cron.d/antivirus-scan"
sudo tee /etc/cron.d/antivirus-scan > /dev/null <<EOF
# Syntaxe cron : minute heure jour mois jour_de_semaine utilisateur commande
0 10,18 * * * root /usr/local/bin/antivirus-scan.sh >> /var/log/antivirus-scan.log 2>&1
EOF

echo "✅ Antivirus configuré :"
echo "   • ClamAV → freshclam (daemon)"
echo "   • LMD      → installé et configuré"
echo "   • Scan     → /usr/local/bin/antivirus-scan.sh"
echo "   • Planifié → 10:00 et 18:00 tous les jours"

# === Configuration du user de backup ===
echo "[+] Configuration du user de backup"
sudo useradd -m -s /bin/bash backup 2>/dev/null || echo "User 'backup' already exists"
sudo mkdir -p /home/backup/.ssh
sudo chmod 700 /home/backup/.ssh
sudo cp /home/ec2-user/.ssh/authorized_keys /home/backup/.ssh/authorized_keys 
sudo chown -R backup:backup /home/backup/.ssh
# === Donner les droits sudo pour pouvoir tar ===
echo "backup ALL=(ALL) NOPASSWD: /bin/tar" | sudo tee /etc/sudoers.d/backup


# === Mot de passe root ===
echo "[+] Définition du mot de passe root"
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

✅ Netdata installé et inscrit sur Netdata Cloud !
Pour changer de token ou d'espace :  
  modifiez simplement les arguments --claim-xxxx dans ce script.

✅ Mise en place terminée pour $NEW_HOSTNAME

INFO
