#!/bin/bash

set -euo pipefail

# Load variables from .env
if [ ! -f "setup_env.sh" ]; then
  echo "❌ setup_env.sh file not found. Create one with the necessary variables."
  exit 1
else
  source setup_env.sh
fi

echo "🕒 Setting up Chrony NTP server..."

# Install Chrony if not present
if ! command -v chronyd &>/dev/null; then
    echo "📦 Installing chrony..."
    sudo dnf install -y chrony || sudo apt install -y chrony
else
    echo "✅ Chrony is already installed."
fi

# Backup existing configuration
CONFIG="/etc/chrony.conf"
BACKUP="/etc/chrony.conf.bak"
if [ ! -f "$BACKUP" ]; then
    sudo cp "$CONFIG" "$BACKUP"
    echo "📄 Original config backed up to $BACKUP"
fi

# Apply new configuration
echo "⚙️ Writing Chrony configuration..."

sudo tee "$CONFIG" > /dev/null <<EOF
# NTP AWS internal (fast)
server 169.254.169.123 iburst

# Redundancy with public servers
server 0.europe.pool.ntp.org iburst
server 1.europe.pool.ntp.org iburst

# Allow subnet to sync with this server
allow $PRIVATE_SUBNET_CIDR

# Allow local time service even if unsynced
local stratum 8

# Step clock immediately if offset is large
makestep 1.0 3

# Sync hardware clock
rtcsync

# Frequency drift tracking
driftfile /var/lib/chrony/drift

# Logging
logdir /var/log/chrony
EOF

# Restart and enable chronyd
echo "🔁 Restarting chronyd..."
sudo systemctl enable chronyd
sudo systemctl restart chronyd

# Show current time sync status
echo "✅ Chrony setup completed. Current tracking info:"
chronyc tracking
