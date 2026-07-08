#!/bin/bash
# VPN-Starter-Kit :: core/slowdns.sh
# Install DNSTT (SlowDNS) server, generate keypair, forward to local SSH.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

SLOWDNS_DIR="/etc/vpn-script/slowdns"
DNSTT_LISTEN_PORT=5300          # dnstt binds here; iptables sends :53 -> here
SSH_TARGET="127.0.0.1:143"      # Dropbear (matches File 4)

mkdir -p "$SLOWDNS_DIR"
cd "$SLOWDNS_DIR"

# --- 1. Fetch the dnstt-server binary ---
# Built from bamsoftware's dnstt (the canonical SlowDNS core).
echo ">>> Downloading dnstt-server binary..."
if [[ ! -f "$SLOWDNS_DIR/dnstt-server" ]]; then
  wget -O dnstt-server \
    "https://raw.githubusercontent.com/khaledagn/DNS-AGN/main/slowdns/dns-server" \
    || { echo "Download failed. Check network settings / mirror URL."; exit 1; }
  chmod +x dnstt-server
fi

# --- 2. Generate the server keypair (only once) ---
# server.key = private (stays on server). server.pub = public (goes to clients).
if [[ ! -f "$SLOWDNS_DIR/server.key" ]]; then
  echo ">>> Generating DNSTT keypair..."
  ./dnstt-server -gen-key -privkey-file server.key -pubkey-file server.pub
fi

echo "============================================"
echo " SlowDNS core installed."
echo "   Listen : UDP ${DNSTT_LISTEN_PORT}  (iptables redirects :53 here)"
echo "   Target : ${SSH_TARGET}"
echo ""
echo " PUBLIC KEY (give this to clients):"
cat "$SLOWDNS_DIR/server.pub"
echo "============================================"