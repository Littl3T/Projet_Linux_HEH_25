#!/usr/bin/env bash
set -euo pipefail

BACKUP_HOME="/home/backup"
BACKUP_ROOT="$BACKUP_HOME/backups"
SCRIPTS_DIR="$BACKUP_HOME/scripts"
LOG_DIR="$BACKUP_HOME/logs"

echo "[+] Installation de lvm2"
yum install -y lvm2

# Disques à utiliser pour LVM
DEVICES=(/dev/nvme1n1 /dev/nvme2n1)
VG_NAME="backup_vg"
LV_NAME="backup_lv"
FSTAB="/etc/fstab"

echo "[+] Création des Physical Volumes sur ${DEVICES[*]}"
for dev in "${DEVICES[@]}"; do
  # si le PV n'existe pas encore, on le crée
  pvs --noheadings -o pv_name | grep -qw "$dev" || pvcreate -ff -y "$dev"
done

echo "[+] Création du Volume Group $VG_NAME"
vgs --noheadings -o vg_name | grep -qw "$VG_NAME" || vgcreate "$VG_NAME" "${DEVICES[@]}"

echo "[+] Création du Logical Volume $LV_NAME (100%FREE)"
lvs --noheadings -o lv_name "$VG_NAME" | grep -qw "$LV_NAME" \
  || lvcreate -n "$LV_NAME" -l 100%FREE "$VG_NAME"

echo "[+] Formatage ext4 du LV"
blkid -o value -s TYPE "/dev/$VG_NAME/$LV_NAME" 2>/dev/null \
  || mkfs.ext4 -F "/dev/$VG_NAME/$LV_NAME"

echo "[+] Montage permanent de /dev/$VG_NAME/$LV_NAME sur $BACKUP_ROOT"
mkdir -p "$BACKUP_ROOT"
grep -qxF "/dev/$VG_NAME/$LV_NAME $BACKUP_ROOT ext4 defaults 0 2" "$FSTAB" \
  || echo "/dev/$VG_NAME/$LV_NAME $BACKUP_ROOT ext4 defaults 0 2" >> "$FSTAB"
mount -a

echo "[+] Installation de cronie"
yum install -y cronie   

echo "[+] Activation de crond"
systemctl enable --now crond

echo "[+] Création de l’utilisateur backup"
useradd -m -s /bin/bash backup 2>/dev/null || echo "User 'backup' existe déjà"

echo "[+] Création des répertoires de travail"
mkdir -p "$BACKUP_ROOT" "$LOG_DIR" "$SCRIPTS_DIR"

# Vérification / création du script de backup
BACKUP_SCRIPT="$SCRIPTS_DIR/backup.sh"
if [ ! -f "$BACKUP_SCRIPT" ]; then
  echo "[!] Le script de backup n'existe pas, création d'un fichier vide : $BACKUP_SCRIPT"
  touch "$BACKUP_SCRIPT"
  created_missing_script=true
else
  created_missing_script=false
fi

echo "[+] Permissions sur $BACKUP_HOME"
chown -R backup:backup "$BACKUP_HOME"
chmod 700 "$BACKUP_HOME/.ssh" 2>/dev/null || true

# Rendre le script exécutable et lui donner les bons droits
chmod +x "$BACKUP_SCRIPT"
chown backup:backup "$BACKUP_SCRIPT"

echo "[+] Planification du backup quotidien dans le crontab de backup"
( crontab -u backup -l 2>/dev/null; echo "0 3 * * * $BACKUP_SCRIPT >> $LOG_DIR/backup.log 2>&1" ) \
  | crontab -u backup -

# Avertissement si le script venait d'être créé
if [ "$created_missing_script" = true ]; then
  echo ""
  echo "⚠️  Attention : le script de backup était absent."
  echo "   Vous devez maintenant éditer  $BACKUP_SCRIPT  pour y ajouter vos commandes de sauvegarde."
fi

echo "✅ Serveur de backup initialisé et prêt."
