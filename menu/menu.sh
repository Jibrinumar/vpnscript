#!/bin/bash
# VPN-Starter-Kit :: menu/menu.sh
# Main interactive dashboard. Installed path: /etc/vpn-script/menu/menu.sh
# Reached globally by the `menu` command (symlinked in the install stage).
set -uo pipefail

BASE="/etc/vpn-script/menu"

# --- must be root: user creation, systemctl all need it ---
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo menu"
  exit 1
fi

pause() { read -rp $'\nPress Enter to return to menu...' _; }

service_status() {
  # prints ● active / ○ dead for a unit, padded
  local unit="$1" label="$2"
  if systemctl is-active --quiet "$unit"; then
    printf "  %-10s : \e[32m● active\e[0m\n" "$label"
  else
    printf "  %-10s : \e[31m○ down\e[0m\n" "$label"
  fi
}

restart_all() {
  echo ">>> Restarting services..."
  systemctl restart xray        && echo "  xray      restarted"
  systemctl restart nginx       && echo "  nginx     restarted"
  systemctl restart dropbear    && echo "  dropbear  restarted"
  systemctl restart ws-proxy    && echo "  ws-proxy  restarted"
  systemctl restart slowdns     && echo "  slowdns   restarted"
}

while true; do
  clear
  echo "==========================================="
  echo "            VPN MANAGER  v1.0"
  echo "==========================================="
  service_status xray     "Xray"
  service_status nginx    "Nginx"
  service_status dropbear "Dropbear"
  service_status ws-proxy "SSH-WS"
  service_status slowdns  "SlowDNS"
  echo "-------------------------------------------"
  echo "  XRAY USERS"
  echo "   [1] Add VLESS user"
  echo "   [2] Add VMess user"
  echo ""
  echo "  SSH / SLOWDNS USERS   (one account = both)"
  echo "   [3] Add SSH/DNS user"
  echo ""
  echo "  SYSTEM"
  echo "   [4] Restart all services"
  echo "   [5] Delete user        (coming: File 10)"
  echo "   [6] List users         (coming: File 11)"
  echo "   [0] Exit"
  echo "==========================================="
  read -rp " Choose an option: " opt

  case "$opt" in
    1) bash "$BASE/add-user.sh" vless ; pause ;;
    2) bash "$BASE/add-user.sh" vmess ; pause ;;
    3) bash "$BASE/add-ssh-user.sh"   ; pause ;;
    4) restart_all                    ; pause ;;
    5) echo "Not built yet (File 10)."; pause ;;
    6) echo "Not built yet (File 11)."; pause ;;
    0) clear; exit 0 ;;
    *) echo "Invalid option."; sleep 1 ;;
  esac
done
