#!/bin/bash

# ==========================================
#  Deterministic SIT / 6to4 Tunnel Manager
# ==========================================

CONF_DIR="/etc/sit6"
DB="$CONF_DIR/tunnels.db"
TUN_PREFIX="sit6"

mkdir -p "$CONF_DIR"

# ---------- Colors ----------
red()   { echo -e "\e[31m$1\e[0m"; }
green() { echo -e "\e[32m$1\e[0m"; }
blue()  { echo -e "\e[36m$1\e[0m"; }

die() {
  red "ERROR: $1"
  exit 1
}

# ---------- Checks ----------
check_root() {
  [[ $EUID -ne 0 ]] && die "Run as root"
}

fix_ipv6() {
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
  sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
  sysctl -w net.ipv6.conf.default.forwarding=1 >/dev/null
}

persist_ipv6() {
  cat <<EOF >/etc/sysctl.d/99-sit6.conf
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF
  sysctl --system >/dev/null
}

# ---------- Deterministic IPv6 ----------
gen_ipv6_net() {
  local ID=$1
  printf "fd00:%x::/64\n" "$ID"
}

# ---------- Health ----------
health_check() {
  local TARGET=$1
  blue "Health check: ping6 $TARGET"
  ping6 -c 3 -W 2 "$TARGET" &>/dev/null \
    && green "Tunnel is healthy" \
    || die "Tunnel is NOT healthy (IPv6 mismatch or remote down)"
}

# ---------- Core ----------
create_tunnel() {
  echo
  echo "Select server role:"
  echo "1) Iran"
  echo "2) Outside"
  read -p "> " ROLE_SEL

  [[ "$ROLE_SEL" != "1" && "$ROLE_SEL" != "2" ]] && die "Invalid role"

  read -p "Enter tunnel ID (same number on both servers): " TID
  [[ -z "$TID" || ! "$TID" =~ ^[0-9]+$ ]] && die "Tunnel ID must be a number"

  read -p "Enter IRAN server IPv4: " IR_IP
  read -p "Enter OUTSIDE server IPv4: " OUT_IP

  IPV6_NET=$(gen_ipv6_net "$TID")
  TUN="${TUN_PREFIX}${TID}"

  if [[ "$ROLE_SEL" == "1" ]]; then
    # IRAN
    LOCAL="$IR_IP"
    REMOTE="$OUT_IP"
    IPV6_LOCAL="fd00:${TID}::2/64"
    TEST_TARGET="fd00:${TID}::1"
  else
    # OUTSIDE
    LOCAL="$OUT_IP"
    REMOTE="$IR_IP"
    IPV6_LOCAL="fd00:${TID}::1/64"
    TEST_TARGET="fd00:${TID}::2"
  fi

  blue "Creating tunnel $TUN"
  ip tunnel del "$TUN" 2>/dev/null

  ip tunnel add "$TUN" mode sit local "$LOCAL" remote "$REMOTE" ttl 255 \
    || die "Failed to create tunnel"

  ip link set "$TUN" up || die "Failed to bring tunnel up"
  ip -6 addr add "$IPV6_LOCAL" dev "$TUN" || die "Failed to assign IPv6"
  ip -6 route add "$IPV6_NET" dev "$TUN" 2>/dev/null

  echo "$TUN $IR_IP $OUT_IP $IPV6_NET" > "$DB"

  green "Tunnel created"
  blue "IPv6 Network : $IPV6_NET"
  blue "Local IPv6   : $IPV6_LOCAL"

  sleep 1
  health_check "$TEST_TARGET"
}

# ---------- UI ----------
menu() {
  clear
  echo -e "\e[35m====================================\e[0m"
  echo -e "\e[1;35m  Deterministic SIT Tunnel Manager\e[0m"
  echo -e "\e[35m====================================\e[0m"
  echo "1) Create / Recreate tunnel"
  echo "0) Exit"
  echo
}

# ---------- MAIN ----------
check_root
fix_ipv6
persist_ipv6

while true; do
  menu
  read -p "> " C
  case "$C" in
    1) create_tunnel ;;
    0) exit 0 ;;
    *) echo "Invalid option"; sleep 1 ;;
  esac
done    die "IPv6 is not responding on remote side"
  fi
}

# ---------- Core ----------
create_tunnel() {
  read -p "Enter IRAN server IPv4: " IR_IP
  read -p "Enter OUTSIDE server IPv4: " OUT_IP

  [[ -z "$IR_IP" || -z "$OUT_IP" ]] && die "IPv4 addresses cannot be empty"

  TUN="${TUN_PREFIX}$(date +%s)"
  IPV6_NET=$(gen_ipv6_net)

  if [[ "$ROLE" == "IR" ]]; then
    LOCAL="$IR_IP"
    REMOTE="$OUT_IP"
    IPV6_LOCAL="${IPV6_NET%/*}2/64"
    TEST_TARGET="${IPV6_NET%/*}1"
  else
    LOCAL="$OUT_IP"
    REMOTE="$IR_IP"
    IPV6_LOCAL="${IPV6_NET%/*}1/64"
    TEST_TARGET="${IPV6_NET%/*}2"
  fi

  blue "Creating tunnel: $TUN"

  ip tunnel add "$TUN" mode sit local "$LOCAL" remote "$REMOTE" ttl 255 \
    || die "Failed to create tunnel"

  ip link set "$TUN" up || die "Failed to bring tunnel up"
  ip -6 addr add "$IPV6_LOCAL" dev "$TUN" || die "Failed to assign IPv6"
  ip -6 route add "$IPV6_NET" dev "$TUN" 2>/dev/null

  echo "$TUN $IR_IP $OUT_IP $IPV6_NET" >> "$DB"

  green "Tunnel created successfully"
  blue "IPv6 network: $IPV6_NET"
  blue "Local IPv6: $IPV6_LOCAL"

  sleep 1
  health_check "$TEST_TARGET"
}

list_tunnels() {
  blue "Active tunnels:"
  ip tunnel show | grep "$TUN_PREFIX" || echo "No tunnels found"
}

delete_tunnel() {
  list_tunnels
  read -p "Enter tunnel name to delete: " TUN

  ip tunnel del "$TUN" 2>/dev/null
  sed -i "/^$TUN /d" "$DB"

  green "Tunnel removed"
}

check_tunnel() {
  list_tunnels
  read -p "Enter tunnel name to check: " TUN

  ROW=$(grep "^$TUN " "$DB") || die "Tunnel not found in database"
  IPV6_NET=$(echo "$ROW" | awk '{print $4}')

  if [[ "$ROLE" == "IR" ]]; then
    TARGET="${IPV6_NET%/*}1"
  else
    TARGET="${IPV6_NET%/*}2"
  fi

  health_check "$TARGET"
}

# ---------- UI ----------
menu() {
  clear
  echo -e "\e[35m====================================\e[0m"
  echo -e "\e[1;35m   SIT / 6to4 Tunnel Manager\e[0m"
  echo -e "\e[35m====================================\e[0m"
  echo "1) Create new tunnel"
  echo "2) List tunnels"
  echo "3) Health check tunnel"
  echo "4) Delete tunnel"
  echo "0) Exit"
  echo
}

# ---------- MAIN ----------
check_root
ROLE=$(detect_role)

fix_ipv6_sysctl
persist_sysctl

[[ "$ROLE" == "IR" ]] && blue "Server role: IRAN" || blue "Server role: OUTSIDE"

while true; do
  menu
  read -p "> " C
  case "$C" in
    1) create_tunnel ;;
    2) list_tunnels; read -p "Press Enter..." ;;
    3) check_tunnel; read -p "Press Enter..." ;;
    4) delete_tunnel; read -p "Press Enter..." ;;
    0) exit 0 ;;
    *) echo "Invalid option"; sleep 1 ;;
  esac
done
