#!/usr/bin/env bash
set -euo pipefail

### === CONFIG === ###
: "${PRINTER_IP?Error: You must set PRINTER_IP! Example: PRINTER_IP=192.168.1.145}"
PORT="${PORT:-8080}"
AUTH_USER="${AUTH_USER:-}"
AUTH_PASS="${AUTH_PASS:-}"
TAILSCALE_KEY="${TAILSCALE_KEY:-}"

echo "🚀 Setting up printer proxy - targeting $PRINTER_IP on port $PORT"

### === 1. Install dependencies === ###
apt update -y >/dev/null
apt install -y curl nginx apache2-utils >/dev/null

### === 2. Install and start Tailscale === ###
if ! command -v tailscale >/dev/null 2>&1; then
  echo "📡 Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | bash
fi

systemctl enable --now tailscaled

if [ -n "$TAILSCALE_KEY" ]; then
  echo "🔐 Authenticating to Tailscale with key..."
  tailscale up --authkey "$TAILSCALE_KEY" --accept-dns=true || true
else
  echo "⚠️ No TAILSCALE_KEY provided - you'll need to run 'tailscale up' manually to authenticate."
fi

### === 3. Configure nginx === ###
echo "⚙️ Writing nginx config to /etc/nginx/sites-available/printer"
cat >/etc/nginx/sites-available/printer <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen $PORT;
    server_name _;

    client_max_body_size 1G;
EOF

# Optional Basic Auth
if [ -n "$AUTH_USER" ] && [ -n "$AUTH_PASS" ]; then
  htpasswd -bc /etc/nginx/.htpasswd "$AUTH_USER" "$AUTH_PASS"
  cat >>/etc/nginx/sites-available/printer <<EOF
    auth_basic "Restricted Area";
    auth_basic_user_file /etc/nginx/.htpasswd;
EOF
fi

cat >>/etc/nginx/sites-available/printer <<EOF

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

ln -sf /etc/nginx/sites-available/printer /etc/nginx/sites-enabled/printer

echo "✅ Testing nginx configuration..."
nginx -t
systemctl reload nginx
systemctl enable nginx

### === 4. Summary === ###
IP_ADDR=$(hostname -I | awk '{print $1}')
TAILNET_ADDR=$(tailscale ip -4 2>/dev/null | head -n1 || true)

echo
echo "🎉 Setup complete!"
echo "───────────────────────────────────────────────"
echo " 🖥️  Local Access:  http://$IP_ADDR:$PORT"
[ -n "$TAILNET_ADDR" ] && echo " 🌐 Tailscale:     http://$TAILNET_ADDR:$PORT"
echo " 🧩 Proxy Target:  http://$PRINTER_IP"
[ -n "$AUTH_USER" ] && echo " 🔑 Basic Auth:   $AUTH_USER / $AUTH_PASS"
echo "───────────────────────────────────────────────"
echo "Done ✅"
