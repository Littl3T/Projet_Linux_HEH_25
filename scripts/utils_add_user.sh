#!/bin/bash

# Chargement des variables d'environnement
if [ ! -f "/root/setup_env.sh" ]; then
  echo "❌ /root/setup_env.sh introuvable. Crée-le avec ces variables :"
  echo "   WEB_PRIVATE_IP, BACKEND_PRIVATE_IP, DNS_PRIVATE_IP"
  exit 1
fi
source /root/setup_env.sh

# Supprime les \r éventuels
for var in WEB_PRIVATE_IP BACKEND_PRIVATE_IP DNS_PRIVATE_IP; do
  eval "$var"="${!var//$'\r'/}"
done

: "${WEB_PRIVATE_IP:?}"
: "${BACKEND_PRIVATE_IP:?}"
: "${DNS_PRIVATE_IP:?}"

SQL_ADMIN_USER="admin"
SQL_ADMIN_PWD="AdminStrongPwd!2025"
SSH_KEY="/root/labsuser.pem"

# === Vérification des arguments ===
if [ -z "${1:-}" ]; then
    echo "❌ Utilisation : $0 <nom_utilisateur>"
    exit 1
fi

USERNAME=$1
USERDIR="/srv/www/$USERNAME"
SQL_DB="${USERNAME}_db"
SQL_USER="${USERNAME}_sql"

# === Saisie manuelle du mot de passe FTP (Linux) ===
read -s -p "🔑 Entrez le mot de passe FTP pour l'utilisateur Linux '$USERNAME' : " FTP_PWD
echo
read -s -p "🔁 Confirmez le mot de passe FTP : " FTP_PWD_CONFIRM
echo

if [ "$FTP_PWD" != "$FTP_PWD_CONFIRM" ]; then
    echo "❌ Les mots de passe ne correspondent pas."
    exit 1
fi

# === Saisie manuelle du mot de passe SQL ===
read -s -p "🔑 Entrez le mot de passe SQL pour l'utilisateur '$SQL_USER' : " SQL_PWD
echo
read -s -p "🔁 Confirmez le mot de passe SQL : " SQL_PWD_CONFIRM
echo

if [ "$SQL_PWD" != "$SQL_PWD_CONFIRM" ]; then
    echo "❌ Les mots de passe ne correspondent pas."
    exit 1
fi

# === Création utilisateur sur serveur Web+FTP + vhosts HTTP/HTTPS ===
echo "📡 Connexion à $WEB_PRIVATE_IP pour créer l’utilisateur et les vhosts…"
ssh -i "$SSH_KEY" ec2-user@"$WEB_PRIVATE_IP" bash -s <<EOF
echo "[+] Création de l'utilisateur Linux $USERNAME"
sudo useradd -m "$USERNAME"

echo "[+] Définition du mot de passe FTP"
echo "$USERNAME:$FTP_PWD" | sudo chpasswd

echo "[+] Création du répertoire et permissions"
sudo mkdir -p "$USERDIR"
sudo chown "$USERNAME:$USERNAME" "$USERDIR"
sudo chmod 755 "$USERDIR"

echo "[+] Ajout de page d’accueil personnalisée"
sudo tee "$USERDIR/index.html" > /dev/null <<'HTML'
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Bienvenue sur tomananas.lan <b>$USERNAME</b></title>
  <style>
    body { font-family: 'Segoe UI', sans-serif; background: linear-gradient(135deg, #ffeaa7, #fab1a0); color: #2d3436; text-align: center; padding: 50px; }
    .ascii { font-family: monospace; white-space: pre; color: #d35400; margin-bottom: 20px; }
    .box { background: #ffffffaa; padding: 20px; border-radius: 15px; display: inline-block; }
  </style>
</head>
<body>
  <div class="box">
    <h1>Bienvenue sur <strong>tomananas.lan</strong> !</h1>
    <p>Votre site est hébergé avec amour par Tom & Anastasiia.</p>
    <h2>💡 Pour publier votre propre site :</h2>
    <p>Connectez-vous via <strong>FileZilla</strong> avec les informations que vous avez reçues :</p>
    <ul style="list-style: none; padding: 0;">
      <li><strong>Hôte :</strong> l’adresse IP du serveur</li>
      <li><strong>Port :</strong> 21</li>
      <li><strong>Protocole :</strong> FTP - TLS explicite</li>
      <li><strong>Identifiant :</strong> $USERNAME</li>
      <li><strong>Mot de passe :</strong> (fourni par email)</li>
    </ul>
    <p>Vos fichiers doivent être déposés dans ce dossier.<br>
       Ce message disparaîtra lorsque vous le remplacerez par votre propre index.</p>
  </div>
</body>
</html>
HTML
sudo chown "$USERNAME:$USERNAME" "$USERDIR/index.html"

echo "[+] Préparation des répertoires de vhosts"
sudo mkdir -p /etc/httpd/sites-available /etc/httpd/sites-enabled

# --- HTTP vhost ---
echo "[+] Création du VirtualHost HTTP"
sudo tee /etc/httpd/sites-available/$USERNAME.conf > /dev/null <<VH
<VirtualHost *:80>
    ServerName $USERNAME.tomananas.lan
    DocumentRoot $USERDIR
    <Directory "$USERDIR">
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog /var/log/httpd/${USERNAME}_error.log
    CustomLog /var/log/httpd/${USERNAME}_access.log combined
</VirtualHost>
VH

# --- HTTPS vhost ---
echo "[+] Création du VirtualHost HTTPS"
# ajoute Listen 443 si pas déjà présent
sudo grep -q '^Listen 443' /etc/httpd/conf/httpd.conf \
  || echo 'Listen 443' | sudo tee -a /etc/httpd/conf/httpd.conf

sudo tee /etc/httpd/sites-available/${USERNAME}-ssl.conf > /dev/null <<VHSSL
<VirtualHost *:443>
    ServerName $USERNAME.tomananas.lan
    DocumentRoot $USERDIR
    SSLEngine on
    SSLCertificateFile      /etc/pki/tls/certs/vsftpd.pem
    SSLCertificateKeyFile   /etc/pki/tls/private/vsftpd.key
    <Directory "$USERDIR">
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog  /var/log/httpd/${USERNAME}_ssl_error.log
    CustomLog /var/log/httpd/${USERNAME}_ssl_access.log combined
</VirtualHost>
VHSSL

echo "[+] Activation des vhosts"
sudo ln -sf /etc/httpd/sites-available/$USERNAME.conf /etc/httpd/sites-enabled/
sudo ln -sf /etc/httpd/sites-available/${USERNAME}-ssl.conf /etc/httpd/sites-enabled/

echo "[+] Rechargement d’Apache pour prendre en compte HTTP & HTTPS"
sudo systemctl reload httpd

 # ────────────────────────────────────────────────────────────────
 # Partie Samba : création du compte Samba et activation
 # ────────────────────────────────────────────────────────────────
 echo "[+] Création/utilisateur Samba pour $USERNAME"
 if sudo pdbedit -L | grep -q "^$USERNAME:"; then
   echo "⚠️ Samba user $USERNAME already exists."
 else
   echo "[+] Définition non-interactive du mot de passe Samba pour $USERNAME"
   # on réutilise ici le même mot de passe que pour FTP, stocké dans $FTP_PWD
   printf "%s\n%s\n" "$FTP_PWD" "$FTP_PWD" | sudo smbpasswd -s -a "$USERNAME"
 fi
 echo "[+] Activation du compte Samba"
 sudo smbpasswd -e "$USERNAME"

echo "✅ Utilisateur Linux & Samba $USERNAME et vhosts HTTP/HTTPS créés"
EOF

# === Création de l’utilisateur SQL ===
echo "🗄 Connexion à $BACKEND_PRIVATE_IP pour créer la base SQL et l’utilisateur…"
ssh -i "$SSH_KEY" ec2-user@"$BACKEND_PRIVATE_IP" bash -s <<EOF
sudo mysql -u"$SQL_ADMIN_USER" -p"$SQL_ADMIN_PWD" <<MYSQL
CREATE DATABASE IF NOT EXISTS \\\`$SQL_DB\\\`;
CREATE USER IF NOT EXISTS '$SQL_USER'@'%' IDENTIFIED BY '$SQL_PWD';
GRANT ALL PRIVILEGES ON \\\`$SQL_DB\\\`.* TO '$SQL_USER'@'%';
FLUSH PRIVILEGES;
MYSQL
EOF

echo "✅ Base de données $SQL_DB et utilisateur $SQL_USER créés sur le serveur SQL"

# === Déclaration DNS sur serveur DNS ===
DNS_ZONE_FILE="$ZONE_DIR/forward.tomananas.lan"

echo "🌐 Connexion à $DNS_PRIVATE_IP pour ajouter l’entrée DNS $USERNAME.tomananas.lan → $WEB_PRIVATE_IP"

ssh -i "$SSH_KEY" ec2-user@$DNS_PRIVATE_IP "sudo bash -s" <<EOF
ZONEDIR="$DNS_ZONE_FILE"
TMPFILE=\$(mktemp)

# Lire le fichier, incrémenter le serial, conserver tout le reste
sudo awk '
  BEGIN { serial_updated = 0 }
  /^\$TTL/ { print; next }
  /[0-9]+[[:space:]]*;[[:space:]]*Serial/ && !serial_updated {
    serial = \$1 + 1
    print "        " serial " ; Serial"
    serial_updated = 1
    next
  }
  { print }
' "\$ZONEDIR" > "\$TMPFILE"

# Ajouter la ligne DNS (sans supprimer les autres)
echo "$USERNAME IN A $WEB_PRIVATE_IP" | sudo tee -a "\$TMPFILE" > /dev/null

# Vérifier que la zone est valide
sudo named-checkzone tomananas.lan "\$TMPFILE"
if [ \$? -ne 0 ]; then
  echo "❌ Zone invalide, annulation"
  rm -f "\$TMPFILE"
  exit 1
fi

# Remplacer le fichier de zone uniquement si tout est OK
sudo mv "\$TMPFILE" "\$ZONEDIR"
sudo chown named:named "\$ZONEDIR"
sudo systemctl restart named
EOF

echo "✅ Enregistrement DNS ajouté pour $USERNAME.tomananas.lan → $WEB_PRIVATE_IP"

# === Résumé ===
echo "🎉 Client $USERNAME ajouté avec succès !"
cat <<SUMMARY

🔐 Connexions :
  • FTP (serveur Web) : 
      Utilisateur : $USERNAME
      Mot de passe : (votre saisie)
  • SQL (phpMyAdmin) : 
      Hôte        : $BACKEND_PRIVATE_IP
      Base        : $SQL_DB
      Utilisateur : $SQL_USER
      Mot de passe: $SQL_PWD
  • HTTP  : http://$USERNAME.tomananas.lan
  • HTTPS : https://$USERNAME.tomananas.lan
  • DNS   : $USERNAME.tomananas.lan → $WEB_PRIVATE_IP
SUMMARY
