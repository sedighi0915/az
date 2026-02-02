#!/bin/bash

CONF_DIR="/etc/sit6"
DB="$CONF_DIR/tunnels.db"
TUN_PREFIX="sit6"
mkdir -p "$CONF_DIR"

# ---------- Colors ----------
red()   { echo -e "\e[31m$1\e[0m"; }
green() { echo -e "\e[32m$1\e[0m"; }
blue()  { echo -e "\e[36m$1\e[0m"; }

die() { red "ERROR: $1"; exit 1; }
check_root() { [[ $EUID -ne 0 ]] && die "Run as root"; }

# ---------- IPv6 kernel ----------
enable_ipv6() {
  sysctl -w net.ipv6.conf.all.disable_ipv6=0
  sysctl -w net.ipv6.conf.default.disable_ipv6=0
  sysctl -w net.ipv6.conf.all.forwarding=1
  sysctl -w net.ipv6.conf.default.forwarding=1
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

# ---------- deterministic IPv6 ----------
gen_ipv6_net() { local ID=$1; printf "fd00:%x::/64\n" "$ID"; }

# ---------- Health ----------
health_check() {
  local TARGET=$1
  blue "Health check: ping6 $TARGET"
  if ping6 -c 3 -W 2 "$TARGET" &>/dev/null; then
    green "Tunnel is healthy"
  else
    die "IPv6 is not responding on remote side"
  fi
}

# ---------- Tunnel ----------
create_tunnel_iran() {
  echo
  read -p "Tunnel ID (same on both servers, number): " TID
  [[ -z "$TID" || ! "$TID" =~ ^[0-9]+$ ]] && die "Tunnel ID must be a number"

  read -p "IPv4 ایران (کلاینت‌ها به این وصل می‌شوند): " IR_IP
  read -p "IPv4 سرور خارج: " OUT_IP
  [[ -z "$IR_IP" || -z "$OUT_IP" ]] && die "IPv4 cannot be empty"

  read -p "TCP port برای forward (default 4040): " PORT
  [[ -z "$PORT" ]] && PORT=4040

  IPV6_NET=$(gen_ipv6_net "$TID")
  TUN="${TUN_PREFIX}${TID}"

  IPV6_LOCAL="fd00:${TID}::2/64"  # لوکال ایران
  IPV6_REMOTE="fd00:${TID}::1/64" # تونل سرور خارج

  blue "Creating tunnel $TUN..."
  ip tunnel del "$TUN" 2>/dev/null
  ip tunnel add "$TUN" mode sit local "$IR_IP" remote "$OUT_IP" ttl 255 || die "Failed to create tunnel"
  ip link set "$TUN" up || die "Failed to bring tunnel up"
  ip -6 addr add "$IPV6_LOCAL" dev "$TUN" || die "Failed to assign IPv6"
  ip -6 route add "$IPV6_NET" dev "$TUN" 2>/dev/null

  echo "$TUN $IR_IP $OUT_IP $IPV6_NET" > "$DB"
  green "Tunnel created successfully"
  blue "IPv6 Network: $IPV6_NET"
  blue "Local IPv6  : $IPV6_LOCAL"

  # ---------- Health ----------
  sleep 1
  health_check "$IPV6_REMOTE"

  # ---------- TCP Forward IPv4 -> IPv6 تونل ----------
  blue "Setting up TCP forward IPv4:$PORT -> $IPV6_LOCAL:$PORT"
  iptables -t nat -D PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $IPV6_LOCAL:$PORT 2>/dev/null
  ip6tables -t nat -D POSTROUTING -p tcp -d $IPV6_LOCAL --dport $PORT -j MASQUERADE 2>/dev/null
  iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $IPV6_LOCAL:$PORT
  ip6tables -t nat -A POSTROUTING -p tcp -d $IPV6_LOCAL --dport $PORT -j MASQUERADE
  green "✅ TCP forward setup complete on port $PORT"
}

create_tunnel_outside() {
  echo
  read -p "Tunnel ID (same as ایران): " TID
  [[ -z "$TID" || ! "$TID" =~ ^[0-9]+$ ]] && die "Tunnel ID must be a number"

  read -p "IPv4 سرور خارج: " OUT_IP
  read -p "IPv4 ایران: " IR_IP
  [[ -z "$OUT_IP" || -z "$IR_IP" ]] && die "IPv4 cannot be empty"

  IPV6_NET=$(gen_ipv6_net "$TID")
  TUN="${TUN_PREFIX}${TID}"

  IPV6_LOCAL="fd00:${TID}::1/64"   # لوکال سرور خارج
  IPV6_REMOTE="fd00:${TID}::2/64"  # تونل ایران

  blue "Creating tunnel $TUN..."
  ip tunnel del "$TUN" 2>/dev/null
  ip tunnel add "$TUN" mode sit local "$OUT_IP" remote "$IR_IP" ttl 255 || die "Failed to create tunnel"
  ip link set "$TUN" up || die "Failed to bring tunnel up"
  ip -6 addr add "$IPV6_LOCAL" dev "$TUN" || die "Failed to assign IPv6"
  ip -6 route add "$IPV6_NET" dev "$TUN" 2>/dev/null

  echo "$TUN $OUT_IP $IR_IP $IPV6_NET" > "$DB"
  green "Tunnel created successfully"
  blue "IPv6 Network: $IPV6_NET"
  blue "Local IPv6  : $IPV6_LOCAL"

  # ---------- Health ----------
  sleep 1
  health_check "$IPV6_REMOTE"
  green "✅ Tunnel ready. No TCP forward needed here."
}

# ---------- Menu ----------
menu() {
  clear
  echo -e "\e[35m====================================\e[0m"
  echo -e "\e[1;35m SIT / 6to4 Tunnel (Iran/Outside)\e[0m"
  echo -e "\e[35m====================================\e[0m"
  echo "1) Create / Recreate tunnel (Iran)"
  echo "2) Create / Recreate tunnel (Outside)"
  echo "0) Exit"
  echo
}

# ---------- MAIN ----------
check_root
enable_ipv6
persist_ipv6

while true; do
  menu
  read -p "> " C
  case "$C" in
    1) create_tunnel_iran ;;
    2) create_tunnel_outside ;;
    0) exit 0 ;;
    *) echo "Invalid option"; sleep 1 ;;
  esac
done
