#!/bin/bash

# Web folder, user must be created before

# === Create Samba user password ===
if pdbedit -L | grep -q "^$USERNAME:"; then
  echo "⚠️ Samba user $USERNAME already exists."
else
  echo "🔐 Set Samba password for $USERNAME:"
  smbpasswd -a "$USERNAME"
fi
smbpasswd -e "$USERNAME"

