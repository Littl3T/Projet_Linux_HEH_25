#!/bin/bash

# === Constants ===
SHARE_BASE="/srv/www"
SMB_CONF="/etc/samba/smb.conf"

# === Must run as root ===
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# === Install Samba ===
echo "🔧 Installing Samba..."
yum install -y samba samba-client

# === Enable and start Samba services ===
echo "🚀 Enabling Samba services..."
systemctl enable --now smb nmb

# === Configure firewall if firewalld is active ===
if systemctl is-active --quiet firewalld; then
  echo "🔓 Opening firewall for Samba..."
  firewall-cmd --add-service=samba --permanent
  firewall-cmd --reload
fi

# === Write smb.conf ===
echo "🛠️ Writing /etc/samba/smb.conf..."
cat > "$SMB_CONF" <<EOF
[global]
  workgroup = WORKGROUP
  security = user
  map to guest = bad user
  server string = Samba Server for Tomananas
  netbios name = samba01
  dns proxy = no

[www]
  path = /srv/www/%U
  comment = Personal web folder
  valid users = %U
  browseable = no
  writable = yes
  create mask = 0700
  directory mask = 0700
EOF

# === Create base share directory ===
mkdir -p "$SHARE_BASE"
chmod 755 "$SHARE_BASE"

# === Restart Samba services ===
echo "🔄 Restarting Samba services..."
systemctl restart smb nmb

echo "✅ Samba server setup complete."
