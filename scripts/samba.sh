#!/bin/bash

# === CONFIGURATION ===
NETWORK="10.42.0.0/24"
SHARED_FOLDER="/srv/public"
SMB_CONF="/etc/samba/smb.conf"
EXPORTS_FILE="/etc/exports"

# Load variables from setup_env.sh file
if [ ! -f "setup_env.sh" ]; then
  echo "❌ setup_env.sh file not found. Create one with the necessary variables."
  exit 1
else
  source setup_env.sh
fi

# Required environment variables
: "${SHARE_NETWORK:?SHARE_NETWORK is not set}"
: "${SHARED_FOLDER:?SHARED_FOLDER is not set}"
: "${SMB_CONF:?SMB_CONF is not set}"
: "${EXPORTS_FILE:?EXPORTS_FILE is not set}"

# === Root check ===
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ This script must be run as root."
  exit 1
fi

echo "📦 Installing Samba and NFS packages..."
yum install -y samba samba-client nfs-utils

echo "📁 Creating shared folder at $SHARED_FOLDER..."
mkdir -p "$SHARED_FOLDER"
chmod 777 "$SHARED_FOLDER"
chown nobody:nogroup "$SHARED_FOLDER" 2>/dev/null || chown nobody:nobody "$SHARED_FOLDER"

# === Configure Samba ===
echo "⚙️ Writing Samba configuration to $SMB_CONF..."
cat > "$SMB_CONF" <<EOF
[global]
  workgroup = WORKGROUP
  security = user
  map to guest = Bad User
  server string = Samba + NFS Shared Server
  netbios name = samba-nfs-server
  dns proxy = no
  guest account = nobody

[www]
  path = /srv/www/%U
  comment = Personal web folder
  valid users = %U
  browseable = no
  writable = yes
  create mask = 0700
  directory mask = 0700

[public]
  path = /srv/public
  comment = Public shared folder
  public = yes
  guest ok = yes
  writable = yes
  browseable = yes
  force user = nobody
  force group = nogroup
  create mask = 0666
  directory mask = 0777
EOF

echo "🚀 Enabling Samba services..."
systemctl enable --now smb nmb

# === Configure firewall for Samba ===
if systemctl is-active --quiet firewalld; then
  echo "🔓 Configuring firewall for Samba..."
  firewall-cmd --add-service=samba --permanent
  firewall-cmd --reload
fi

# === Configure NFS ===
echo "🛠️ Writing NFS export to $EXPORTS_FILE..."
grep -q "^$SHARED_FOLDER" "$EXPORTS_FILE" && \
  sed -i "s|^$SHARED_FOLDER.*|$SHARED_FOLDER $SHARE_NETWORK(rw,sync,no_root_squash,no_subtree_check)|" "$EXPORTS_FILE" || \
  echo "$SHARED_FOLDER $SHARE_NETWORK(rw,sync,no_root_squash,no_subtree_check)" >> "$EXPORTS_FILE"

exportfs -rav

echo "🚀 Enabling NFS services..."
systemctl enable --now nfs-server

# === Configure firewall for NFS ===
if systemctl is-active --quiet firewalld; then
  echo "🔓 Configuring firewall for NFS..."
  firewall-cmd --add-service=nfs --permanent
  firewall-cmd --add-service=mountd --permanent
  firewall-cmd --add-service=rpc-bind --permanent
  firewall-cmd --reload
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
echo "✅ Shared folder deployed successfully!"
echo "📂 Access via:"
echo "  - Windows (Samba): \\\\$SERVER_IP\\public"
echo "  - Linux (NFS):     mount $SERVER_IP:/srv/public /mnt"
