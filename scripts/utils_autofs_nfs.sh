  #!/bin/bash

  if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root."
    exit 1
  fi

  # Load variables from setup_env.sh file
  if [ ! -f "/root/setup_env.sh" ]; then
    echo "❌ setup_env.sh file not found. Create one with the necessary variables."
    exit 1
  else
    source /root/setup_env.sh
  fi

  # Required environment variables
  : "${NFS_PRIVATE_IP:?NFS_PRIVATE_IP is not set}"
  : "${SHARED_FOLDER:?SHARED_FOLDER is not set}"
  : "${MOUNT_ROOT:?MOUNT_ROOT is not set}"
  : "${MOUNT_NAME:?MOUNT_NAME is not set}"
  : "${TIMEOUT:?TIMEOUT is not set}"
  : "${AUTO_MASTER:?AUTO_MASTER is not set}"
  : "${AUTO_MAP:?AUTO_MAP is not set}"

  echo "📦 Installing autofs..."
  if command -v apt &>/dev/null; then
    apt update && apt install -y autofs nfs-common
  elif command -v yum &>/dev/null; then
    yum install -y autofs nfs-utils
  else
    echo "❌ Unsupported package manager."
    exit 1
  fi

  echo "📝 Configuring autofs mount point..."

  # Ensure mount root exists
  mkdir -p "$MOUNT_ROOT"

  # Add autofs map to auto.master if not already present
  if ! grep -q "$MOUNT_ROOT" "$AUTO_MASTER"; then
    echo "$MOUNT_ROOT  $AUTO_MAP  --timeout=$TIMEOUT" >> "$AUTO_MASTER"
  fi

  # Write auto.nfs map
  cat > "$AUTO_MAP" <<EOF
  $MOUNT_NAME  -rw,sync  $NFS_PRIVATE_IP:$SHARED_FOLDER
  EOF

  echo "🔁 Restarting autofs..."
  systemctl restart autofs

  echo "✅ Autofs configured successfully."

  echo "📂 Test access:"
  echo "  - Path: $MOUNT_ROOT/$MOUNT_NAME"
  echo "  - Run: ls $MOUNT_ROOT/$MOUNT_NAME"
  echo "    (autofs will auto-mount on first access)"
