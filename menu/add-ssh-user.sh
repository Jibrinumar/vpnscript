#!/bin/bash
# VPN-Starter-Kit :: menu/add-ssh-user.sh
# Create a Linux account for SSH-WebSocket + SlowDNS (one account covers both).
# Tunnel-only: no shell, password auth, hard expiry date.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

read -rp "Enter Username : " USERNAME
read -rp "Enter Password : " PASSWORD
read -rp "Expiry (days)  : " DAYS

# --- validate ---
if [[ -z "$USERNAME" ]]; then
  echo "Username cannot be empty."; exit 1
fi
if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Invalid username. Use lowercase letters, digits, - and _ only."; exit 1
fi
if [[ -z "$PASSWORD" ]]; then
  echo "Password cannot be empty."; exit 1
fi
if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
  echo "Expiry must be a number of days."; exit 1
fi

# --- refuse duplicate ---
if id "$USERNAME" >/dev/null 2>&1; then
  echo "Error: system user '$USERNAME' already exists."; exit 1
fi

EXPIRY=$(date -d "+${DAYS} days" +%Y-%m-%d)

# --- create the account ---
# -M : no home dir (tunnel users don't need one)
# -s /bin/false : no interactive shell — SSH tunnel only, no command execution
# -e : account expiry date (kernel enforces it; login refused after)
useradd -M -s /bin/false -e "$EXPIRY" "$USERNAME"

# set password (chpasswd reads user:pass from stdin)
echo "${USERNAME}:${PASSWORD}" | chpasswd

echo "==========================================="
echo " SSH / SlowDNS account created"
echo "   Username : $USERNAME"
echo "   Password : $PASSWORD"
echo "   Expires  : $EXPIRY"
echo ""
echo " Works for BOTH:"
echo "   - SSH-WebSocket : <server-ip>:8880"
echo "   - SlowDNS       : via your NS domain"
echo "==========================================="