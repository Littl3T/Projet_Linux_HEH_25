#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# 0. Variables d’environnement (à adapter si nécessaire)
# ────────────────────────────────────────────────────────────────
export SSH_KEY="/root/labsuser.pem"
export WEB_USER="ec2-user"
export CA_DIR="/root/ca"
export DAYS_CA=3650
export DAYS_TLS=825

# Charger le setup_env 
if [ ! -f /root/setup_env.sh ]; then
  echo "❌ /root/setup_env.sh introuvable"
  exit 1
fi
source /root/setup_env.sh

export WEB_HOST="$WEB_PRIVATE_IP"

echo "[+] Création du dossier CA: $CA_DIR"
mkdir -p "$CA_DIR"/{private,certs,newcerts,csr}
chmod 700 "$CA_DIR"/private
touch "$CA_DIR/index.txt"
echo 1000 > "$CA_DIR/serial"

# ────────────────────────────────────────────────────────────────
# 1. Génération de la CA root
# ────────────────────────────────────────────────────────────────
echo "[+] Génération de la clé privée de la CA"
openssl genrsa -out "$CA_DIR/private/ca.key.pem" 4096
chmod 400 "$CA_DIR/private/ca.key.pem"

echo "[+] Génération du certificat root (self-signed)"
openssl req -x509 -new -nodes \
  -key "$CA_DIR/private/ca.key.pem" \
  -sha256 -days $DAYS_CA \
  -subj "/C=BE/ST=Hainaut/L=Mons/O=$PROJ_NAME/OU=CA/CN=RootCA.$PROJ_DOMAIN" \
  -out "$CA_DIR/certs/ca.crt.pem"
chmod 444 "$CA_DIR/certs/ca.crt.pem"

# ────────────────────────────────────────────────────────────────
# 2. Génération du certificat wildcard *.tomananas.lan
# ────────────────────────────────────────────────────────────────
echo "[+] Génération de la clé privée wildcard"
openssl genrsa -out "$CA_DIR/private/wildcard.$PROJ_DOMAIN.key.pem" 2048
chmod 400 "$CA_DIR/private/wildcard.$PROJ_DOMAIN.key.pem"

cat > "$CA_DIR/csr/san.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt             = no

[req_distinguished_name]
CN = *.$PROJ_DOMAIN

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $PROJ_DOMAIN
DNS.2 = *.$PROJ_DOMAIN
EOF

echo "[+] Création du CSR wildcard"
openssl req -new -key "$CA_DIR/private/wildcard.$PROJ_DOMAIN.key.pem" \
  -config "$CA_DIR/csr/san.cnf" \
  -out "$CA_DIR/csr/wildcard.$PROJ_DOMAIN.csr.pem"

echo "[+] Signature du certificat wildcard par la CA"
openssl x509 -req \
  -in "$CA_DIR/csr/wildcard.$PROJ_DOMAIN.csr.pem" \
  -CA "$CA_DIR/certs/ca.crt.pem" \
  -CAkey "$CA_DIR/private/ca.key.pem" \
  -CAcreateserial \
  -out "$CA_DIR/certs/wildcard.$PROJ_DOMAIN.crt.pem" \
  -days $DAYS_TLS \
  -sha256 \
  -extfile "$CA_DIR/csr/san.cnf" \
  -extensions req_ext
chmod 444 "$CA_DIR/certs/wildcard.$PROJ_DOMAIN.crt.pem"

# ────────────────────────────────────────────────────────────────
# 3. Déploiement sur le serveur web
# ────────────────────────────────────────────────────────────────
echo "[+] Copie des certificats vers le serveur web $WEB_HOST"
scp -i "$SSH_KEY" \
  "$CA_DIR/certs/ca.crt.pem" \
  "$CA_DIR/certs/wildcard.$PROJ_DOMAIN.crt.pem" \
  "$CA_DIR/private/wildcard.$PROJ_DOMAIN.key.pem" \
  "$WEB_USER@$WEB_HOST":/tmp/

echo "[+] Installation des certificats sur web"
ssh -i "$SSH_KEY" "$WEB_USER@$WEB_HOST" bash -s <<'EOSSH'
set -e
# Déplacer en lieu sûr
sudo mkdir -p /etc/pki/ca-trust/source/anchors
sudo cp /tmp/ca.crt.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

sudo mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
sudo mv /tmp/wildcard.*.crt.pem /etc/pki/tls/certs/wildcard.crt.pem
sudo mv /tmp/wildcard.*.key.pem  /etc/pki/tls/private/wildcard.key.pem
sudo chmod 444 /etc/pki/tls/certs/wildcard.crt.pem
sudo chmod 400 /etc/pki/tls/private/wildcard.key.pem
EOSSH

# ────────────────────────────────────────────────────────────────
# 4. Bilan et instructions
# ────────────────────────────────────────────────────────────────
echo ""
echo "✅ CA et wildcard installés."
echo "→ Le fichier CA public se trouve sur web: /etc/pki/ca-trust/source/anchors/ca.crt.pem"
echo "→ Wildcard cert:    /etc/pki/tls/certs/wildcard.crt.pem"
echo "→ Wildcard key:     /etc/pki/tls/private/wildcard.key.pem"
echo ""
echo "👉 Sur chaque client (Windows/Linux), importez CA ($WEB_HOSTNAME CA) pour faire confiance aux certificats."
echo "👉 Vous pouvez désormais configurer vos vhosts HTTPS en réutilisant wildcard.crt.pem et wildcard.key.pem."
