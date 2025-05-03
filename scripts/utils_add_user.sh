#!/bin/bash

# Script d'ajout d'un utilisateur FTP chrooté dans /srv/www/<utilisateur>

if [ -z "$1" ]; then
    echo "❌ Utilisation : $0 <nom_utilisateur>"
    exit 1
fi

USERNAME=$1
USERDIR="/srv/www/$USERNAME"

echo "[+] Création de l'utilisateur $USERNAME (sans shell)"
useradd -m "$USERNAME"

echo "[+] Définir le mot de passe pour $USERNAME"
passwd "$USERNAME"

echo "[+] Création du dossier de l'utilisateur $USERNAME"
mkdir -p "$USERDIR"

echo "[+] Attribution des permissions"
chown "$USERNAME:$USERNAME" "$USERDIR"
chmod 755 "$USERDIR"

echo "[+] Utilisateur $USERNAME prêt. Il est chrooté dans $USERDIR"
