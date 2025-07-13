#!/bin/bash

#DOMAIN="dns.gapesta.my.id"
echo "masukan domain untuk di jadikan dns dan akses web"
read -rp "Input domain : " -e DOMAIN
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
ADGUARD_BIN="/opt/AdGuardHome/AdGuardHome"

# 1. Install AdGuard Home
echo "📦 Menginstall AdGuard Home..."
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | bash

# 2. Jalankan pertama kali untuk buat config
$ADGUARD_BIN -s install
sleep 5

# 3. Setup Firewall
echo "🛡️ Mengizinkan port DNS dan Web UI..."
ufw allow 53/udp
ufw allow 80
ufw allow 443

# 4. Install nginx + certbot
echo "🌐 Menginstall Nginx dan Certbot..."
apt update
apt install nginx certbot python3-certbot-nginx -y

# 5. Nginx config untuk AdGuard proxy
echo "🔧 Setting Nginx untuk domain $DOMAIN..."

cat >/etc/nginx/sites-available/adguard <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -s /etc/nginx/sites-available/adguard /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# 6. Pasang SSL Let's Encrypt
echo "🔐 Memasang SSL..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN --redirect

# 7. Restart AdGuard Home
$ADGUARD_BIN -s restart

# 8. Selesai
echo ""
echo "✅ Selesai!"
echo "🌐 Akses Web UI: https://$DOMAIN"
echo "📶 Atur DNS HP/PC ke: $(curl -s ifconfig.me)"
echo "💡 Login pertama kali via browser → buat akun admin"

sleep 5

# Pastikan file cert & key ada
if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
  echo "❌ Sertifikat SSL tidak ditemukan!"
  echo "➡️ Pastikan certbot sudah sukses untuk $DOMAIN"
  exit 1
fi

echo "🔐 Mengaktifkan DNS-over-HTTPS (DoH) dan DNS-over-TLS (DoT)..."

# Konfigurasi langsung ke AdGuard config.yaml
CONFIG_FILE="/opt/AdGuardHome/AdGuardHome.yaml"

# Backup config dulu
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"

# Ubah config
sed -i "s|enabled: false|enabled: true|g" "$CONFIG_FILE"
sed -i "s|certificate_path:.*|certificate_path: $CERT_PATH|g" "$CONFIG_FILE"
sed -i "s|private_key_path:.*|private_key_path: $KEY_PATH|g" "$CONFIG_FILE"

# Tambahkan domain untuk DoH/DoT jika belum ada
grep -q "dns.gapesta.my.id" "$CONFIG_FILE" || sed -i "/^tls:\$/a\\  server_name: $DOMAIN" "$CONFIG_FILE"

# Restart AdGuard Home
echo "🔄 Restart AdGuard Home..."
$ADGUARD_BIN -s restart

echo ""
echo "✅ Sukses mengaktifkan DoH & DoT!"
echo "🌐 Server DoH/DoT: $DOMAIN"
echo "📱 Sekarang kamu bisa atur DNS pribadi di HP ke: $DOMAIN"
