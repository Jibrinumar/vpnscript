#!/bin/bash
# VPN-Starter-Kit :: core/slowdns.sh
# Install DNSTT (SlowDNS) by BUILDING FROM SOURCE.
# (Prebuilt-binary mirrors get deleted/DMCA'd — that was the old 404. Source doesn't rot.)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

SLOWDNS_DIR="/etc/vpn-script/slowdns"
BUILD_DIR="/tmp/dnstt-build"
mkdir -p "$SLOWDNS_DIR"

# A 0-byte binary can linger from an earlier failed download — purge it so the
# build actually runs instead of trying to execute an empty file.
if [[ -e "$SLOWDNS_DIR/dnstt-server" && ! -s "$SLOWDNS_DIR/dnstt-server" ]]; then
  echo ">>> Removing broken/empty dnstt-server from a previous run..."
  rm -f "$SLOWDNS_DIR/dnstt-server"
fi

# --- 1. Ensure Go + git are present (only if we still need to build) ---
# -s = exists AND non-empty; rebuild whenever that's not true.
if [[ ! -s "$SLOWDNS_DIR/dnstt-server" ]]; then
  if ! command -v go >/dev/null 2>&1; then
    echo ">>> Installing Go toolchain (needed to build dnstt)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y golang-go git
  fi

  # --- 2. Fetch source: canonical bamsoftware first, GitHub mirror as fallback ---
  rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"; cd "$BUILD_DIR"
  echo ">>> Fetching dnstt source..."
  if command -v git >/dev/null 2>&1 && \
     git clone --depth 1 https://www.bamsoftware.com/git/dnstt.git src 2>/dev/null; then
    echo "    source: bamsoftware.com (canonical)"
  else
    echo "    canonical unreachable — using GitHub mirror..."
    curl -fsSL -o dnstt.tar.gz \
      "https://codeload.github.com/gh4rib/dnstt/tar.gz/refs/heads/main" \
      || { echo "Source download failed. Check network settings."; exit 1; }
    mkdir -p src && tar -xzf dnstt.tar.gz -C src --strip-components=1
  fi

  # --- 3. Build the server binary ---
  echo ">>> Building dnstt-server (first build downloads Go modules, ~1 min)..."
  cd src/dnstt-server
  go build -o "$SLOWDNS_DIR/dnstt-server" \
    || { echo "Build failed. See output above."; exit 1; }
  chmod +x "$SLOWDNS_DIR/dnstt-server"
  cd / && rm -rf "$BUILD_DIR"
  echo "    built: $SLOWDNS_DIR/dnstt-server"
fi

# Belt-and-suspenders: make sure it's executable before we run it.
chmod +x "$SLOWDNS_DIR/dnstt-server"

# --- 4. Generate the server keypair (only once) ---
if [[ ! -f "$SLOWDNS_DIR/server.key" ]]; then
  echo ">>> Generating DNSTT keypair..."
  "$SLOWDNS_DIR/dnstt-server" -gen-key \
    -privkey-file "$SLOWDNS_DIR/server.key" \
    -pubkey-file "$SLOWDNS_DIR/server.pub"
fi

echo "============================================"
echo " SlowDNS core installed (built from source)."
echo "   Listen : UDP 5300  (iptables redirects :53 here)"
echo "   Target : 127.0.0.1:143  (Dropbear)"
echo ""
echo " PUBLIC KEY (give this to clients):"
cat "$SLOWDNS_DIR/server.pub"
echo "============================================"
