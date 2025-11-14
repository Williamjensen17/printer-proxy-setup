#!/usr/bin/env bash
set -euo pipefail

# ========================================
#  Printer Proxy Installer / Updater / Remover
# ========================================

ACTION="${1:-install}"  # install | update | remove
PRINTER_IP="${PRINTER_IP:-}"
PORT="${PORT:-8080}"
AUTH_USER="${AUTH_USER:-}"
AUTH_PASS="${AUTH_PASS:-}"
NGINX_SITE="/etc/nginx/sites-available/printer"
NGINX_LINK="/etc/nginx/sites-enabled/printer"

print_header() {
  echo -e "\n───────────────────────────────────────────────"
  echo -e " 🔧 Printer Proxy - $ACTION mode"
  echo -e "───────────────────────────────────────────────\n"
}

install_or_upgrade() {
  if [ -z "$PRINTER_IP" ]; then
    echo "❌ Error: Set PRINTER_IP first! Example:"
    echo "   PRINTER_IP=192.168.1.145 bash install.sh"
    exit 1
  fi

  echo "📦 Installing dependencies..."
  apt update -y >/dev/null
  apt install -y nginx apache2-utils >/dev/null

  echo "⚙️  Generating nginx config → $NGINX_SITE"

  cat >"$NGINX_SITE" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen $PORT;
    server_name _;

    client_max_body_size 1G;
EOF

  # Optional basic auth
  if [ -n "$AUTH_USER" ] && [ -n "$AUTH_PASS" ]; then
    htpasswd -bc /etc/nginx/.htpasswd "$AUTH_USER" "$AUTH_PASS"
    cat >>"$NGINX_SITE" <<EOF
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/.htpasswd;
EOF
  fi

  cat >>"$NGINX_SITE" <<EOF

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

  ln -sf "$NGINX_SITE" "$NGINX_LINK"

  echo "🔍 Testing nginx configuration..."
  nginx -t
  systemctl reload nginx
  systemctl enable nginx >/dev/null

  local VPS_IP
  VPS_IP=$(hostname -I | awk '{print $1}')

  echo
  echo "🎉 Printer proxy ready!"
  echo "───────────────────────────────────────────────"
  echo " 🌐 Access URL:  http://$VPS_IP:$PORT"
  echo " 🧩 Proxy target: http://$PRINTER_IP"
  [ -n "$AUTH_USER" ] && echo " 🔑 Auth: $AUTH_USER / $AUTH_PASS"
  echo "───────────────────────────────────────────────"
}

remove_proxy() {
  echo "🧹 Removing printer proxy configuration..."
  rm -f "$NGINX_SITE" "$NGINX_LINK" /etc/nginx/.htpasswd 2>/dev/null || true
  systemctl reload nginx
  echo "✅ Printer proxy removed."
}

# =========================
#  MAIN
# =========================
print_header

case "$ACTION" in
  install|update|upgrade)
    install_or_upgrade
    ;;
  remove|uninstall)
    remove_proxy
    ;;
  *)
    echo "Usage: $0 [install|update|remove]"
    exit 1
    ;;
esac
