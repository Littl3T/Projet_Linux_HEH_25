#!/usr/bin/env bash
# setup_sftp_web.sh
# Installe et configure HTTPD+PHP et SSH pour n’autoriser que SFTP (groupe sftpusers)

set -euo pipefail

# 1. Installer les paquets
dnf install -y httpd php php-mysqlnd openssh-server

# 2. Démarrer et activer
systemctl enable --now httpd
systemctl enable --now sshd

# 3. Créer le répertoire parent des sites
mkdir -p /srv/www
chmod 755 /srv/www

# 4. Créer le groupe SFTP
groupadd -f sftpusers

# 5. Configurer SSHD
sshd_conf=/etc/ssh/sshd_config

# Activer subsystem internal-sftp
grep -q '^Subsystem\s\+sftp' $sshd_conf \
  || echo 'Subsystem sftp internal-sftp' >> $sshd_conf

# Ajouter un bloc Match pour restreindre le groupe sftpusers
if ! grep -q '^Match Group sftpusers' $sshd_conf; then
  cat >> $sshd_conf <<'EOF'

Match Group sftpusers
    ChrootDirectory /srv/www/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
EOF
fi

# 6. Reload SSHD
systemctl reload sshd

echo "✅  setup_sftp_web complete. HTTPD & PHP installed, SSH → SFTP only."
