#!/bin/bash
# VPN-Starter-Kit :: install/setup.sh  (full orchestrator)
# Run standalone:
#   wget -q https://raw.githubusercontent.com/Jibrinumar/vpnscript/main/install/setup.sh && chmod +x setup.sh && sudo bash setup.sh
# Or from a clone:
#   sudo bash install/setup.sh
set -euo pipefail

# ============================================================
# SELF-BOOTSTRAP — if run standalone (no repo next to us),
# pull the whole repo tarball and re-exec from inside it.
# ============================================================
REPO_SLUG="Jibrinumar/vpnscript"
REPO_BRANCH="main"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# We know we're "inside the repo" if core/config.json exists one level up.
if [[ ! -f "$SCRIPT_DIR/../core/config.json" ]]; then
  echo ">>> Standalone mode — downloading project files..."
  TMP="$(mktemp -d)"
  wget -qO "$TMP/repo.tar.gz" \
    "https://github.com/${REPO_SLUG}/archive/refs/heads/${REPO_BRANCH}.tar.gz" \
    || { echo "Download failed. Check REPO_SLUG / branch / network."; exit 1; }
  tar -xzf "$TMP/repo.tar.gz" -C "$TMP"
  # GitHub tarballs extract to <repo>-<branch>/
  EXTRACTED="$(find "$TMP" -maxdepth 1 -type d -name '*-'"${REPO_BRANCH}" | head -n1)"
  exec bash "$EXTRACTED/install/setup.sh"
fi

REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

INSTALL_DIR="/etc/vpn-script"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo -i  then re-run."
  exit 1
fi
if ! grep -q "24.04" /etc/os-release; then
  echo "Warning: tuned for Ubuntu 24.04. Continuing in 3s..."; sleep 3
fi

export DEBIAN_FRONTEND=noninteractive

# ============================================================
echo ">>> [1/9] Dependencies"
# ============================================================
apt update -y
apt install -y curl wget jq unzip socat cron nginx dropbear \
  python3 iptables iptables-persistent

# ============================================================
echo ">>> [2/9] Directories + copy project files"
# ============================================================
mkdir -p "$INSTALL_DIR"/{core,menu,slowdns} /var/log/vpn-script
cp "$REPO/core/"*.py    "$INSTALL_DIR/core/" 2>/dev/null || true
cp "$REPO/menu/"*.sh    "$INSTALL_DIR/menu/"
chmod +x "$INSTALL_DIR/menu/"*.sh "$INSTALL_DIR/core/"*.py

# ============================================================
echo ">>> [3/9] BBR"
# ============================================================
cat >/etc/sysctl.d/99-vpn-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1 || true

# ============================================================
echo ">>> [4/9] Xray-core + config"
# ============================================================
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
install -m 644 "$REPO/core/config.json" /usr/local/etc/xray/config.json

# ============================================================
echo ">>> [5/9] Nginx front door"
# ============================================================
install -m 644 "$REPO/core/nginx.conf" /etc/nginx/conf.d/vpn.conf
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t

read -rp "Enter your TLS/WS domain (e.g. vpn.grab2.eu.cc), or leave blank for self-signed: " WS_DOMAIN
echo "${WS_DOMAIN:-}" > /etc/vpn-script/domain          # <-- add this
bash "$REPO/core/tls.sh" "${WS_DOMAIN:-}"

# ============================================================
echo ">>> [6/9] Dropbear + SSH-WS proxy"
# ============================================================
bash "$REPO/core/dropbear.sh"
install -m 644 "$REPO/core/ws-proxy.service" /etc/systemd/system/ws-proxy.service

# ============================================================
echo ">>> [7/9] SlowDNS (needs your NS domain)"
# ============================================================
bash "$REPO/core/slowdns.sh"

read -rp "Enter your SlowDNS NS domain (e.g. slow.creebcloud.net): " NS_DOMAIN
if [[ -z "$NS_DOMAIN" ]]; then
  echo "No NS domain given — SlowDNS service will be installed but left disabled."
  NS_DOMAIN="CHANGE_ME"
fi
# bake the domain into the service unit
sed "s|<YOUR_NS_DOMAIN>|${NS_DOMAIN}|g" \
  "$REPO/core/slowdns.service" > /etc/systemd/system/slowdns.service
bash "$REPO/core/slowdns-redirect.sh"

# --- free UDP 53 from systemd-resolved so DNS can reach us ---
echo ">>> Freeing port 53 from systemd-resolved..."
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/vpn.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF
# keep working resolv.conf (resolved's symlink breaks once stub is off)
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
systemctl restart systemd-resolved || true

# ============================================================
echo ">>> [8/9] Enable + start all services"
# ============================================================
systemctl daemon-reload
systemctl enable --now xray nginx dropbear ws-proxy >/dev/null 2>&1 || true
if [[ "$NS_DOMAIN" != "CHANGE_ME" ]]; then
  systemctl enable --now slowdns >/dev/null 2>&1 || true
else
  systemctl enable slowdns >/dev/null 2>&1 || true
  echo "  slowdns installed but NOT started (set NS domain, then: systemctl start slowdns)"
fi

# ============================================================
echo ">>> [9/9] Global 'menu' command"
# ============================================================
ln -sf "$INSTALL_DIR/menu/menu.sh" /usr/local/bin/menu
chmod +x /usr/local/bin/menu

SERVER_IP=$(curl -s https://api.ipify.org || echo "your-server-ip")
echo ""
echo "==================================================="
echo " INSTALL COMPLETE"
echo "==================================================="
echo "  Server IP   : $SERVER_IP"
echo "  Xray VLESS  : ${SERVER_IP}:80  path /vless"
echo "  Xray VMess  : ${SERVER_IP}:80  path /vmess"
echo "  SSH-WS      : ${SERVER_IP}:8880"
echo "  SlowDNS NS  : ${NS_DOMAIN}"
echo ""
echo "  SlowDNS public key:"
cat "$INSTALL_DIR/slowdns/server.pub" 2>/dev/null || echo "  (run slowdns.sh)"
echo ""
echo "  Type  menu  to manage users."
echo "==================================================="
