#!/usr/bin/env bash
set -e

# === CONFIG ===
: "${PRINTER_IP?Error: Set PRINTER_IP environment variable first!}"
NGINX_SITE="/etc/nginx/sites-available/printer"

echo "📦 Installing nginx..."
apt update -y >/dev/null
apt install -y nginx >/dev/null

echo "⚙️ Writing nginx configuration for $PRINTER_IP"
cat >"$NGINX_SITE" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 8080;
    server_name _;

    client_max_body_size 1G;

    location / {
        proxy_pass http://$PRINTER_IP;
        proxy_set_header Host $PRINTER_IP;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_buffering off;
    }
}
EOF

ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/printer

echo "✅ Testing config and reloading nginx..."
nginx -t
systemctl reload nginx

echo
echo "🎉 Printer reverse proxy is live on: http://$(hostname -I | awk '{print $1}'):8080"
echo "→ Proxying to printer at: http://$PRINTER_IP"
