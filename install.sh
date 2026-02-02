
#!/bin/bash

# ===============================
#  SIT / 6to4 Tunnel Manager
#  Fixed + Health Check Edition
# ===============================

CONF_DIR="/etc/sit6"
DB="$CONF_DIR/tunnels.db"
TUN_PREFIX="sit6"

mkdir -p "$CONF_DIR"

# ---------- Utils ----------
die() {
  echo -e "\e[31m❌ $1\e[0m"
  exit 1
}

ok() {
  echo -e "\e[32m✔ $1\e[0m"
}

info() {
  echo -e "\e[36m➜ $1\e[0m"
}

check_root() {
  [[ $EUID -ne 0 ]] && die "اسکریپت باید با root اجرا شود"
}

detect_role() {
  local CC
  CC=$(curl -s ipapi.co/country/)
  [[ "$CC" == "IR" ]] && echo "IR" || echo "OUT"
}

gen_ipv6() {
  printf "fd%02x:%02x%02x:%02x%02x::/64\n" \
    $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) \
    $((RANDOM%256)) $((RANDOM%256))
}

health_check() {
  local DEV=$1
  local TARGET=$2

  info "تست سلامت تونل (ping6)"
  if ping6 -c 3 -W 2 "$TARGET" &>/dev/null; then
    ok "تونل سالم است"
  else
    die "تونل مشکل دارد (IPv6 پاسخ نمی‌دهد)"
  fi
}

# ---------- Core ----------
create_tunnel() {
  read -p "IP سرور ایران: " IR_IP
  read -p "IP سرور خارج: " OUT_IP

  [[ -z "$IR_IP" || -z "$OUT_IP" ]] && die "IP ها نباید خالی باشند"

  TUN="${TUN_PREFIX}$(date +%s)"
  IPV6_NET=$(gen_ipv6)

  if [[ "$ROLE" == "IR" ]]; then
    LOCAL="$IR_IP"
    REMOTE="$OUT_IP"
    IPV6_LOCAL="${IPV6_NET%/*}2/64"
    IPV6_REMOTE="${IPV6_NET%/*}1"
    TEST_TARGET="$IPV6_REMOTE"
  else
    LOCAL="$OUT_IP"
    REMOTE="$IR_IP"
    IPV6_LOCAL="${IPV6_NET%/*}1/64"
    IPV6_REMOTE="${IPV6_NET%/*}2"
    TEST_TARGET="$IPV6_REMOTE"
  fi

  info "ساخت تونل $TUN"
  ip tunnel add "$TUN" mode sit local "$LOCAL" remote "$REMOTE" ttl 255 || die "خطا در ساخت تونل"
  ip link set "$TUN" up || die "UP نشد"
  ip -6 addr add "$IPV6_LOCAL" dev "$TUN" || die "IPv6 ست نشد"

  echo "$TUN $IR_IP $OUT_IP $IPV6_NET" >> "$DB"

  ok "تونل ساخته شد"
  info "IPv6 Network: $IPV6_NET"
  info "IPv6 این سرور: $IPV6_LOCAL"

  sleep 1
  health_check "$TUN" "$TEST_TARGET"
}

list_tunnels() {
  echo
  info "تونل‌های فعال:"
  ip tunnel show | grep "$TUN_PREFIX" || echo "هیچ تونلی نیست"
  echo
}

delete_tunnel() {
  list_tunnels
  read -p "نام تونل برای حذف: " TUN

  ip tunnel del "$TUN" 2>/dev/null
  sed -i "/^$TUN /d" "$DB"

  ok "تونل حذف شد"
}

check_tunnel() {
  list_tunnels
  read -p "نام تونل: " TUN

  ROW=$(grep "^$TUN " "$DB") || die "تونل پیدا نشد"
  IPV6_NET=$(echo "$ROW" | awk '{print $4}')

  if [[ "$ROLE" == "IR" ]]; then
    TARGET="${IPV6_NET%/*}1"
  else
    TARGET="${IPV6_NET%/*}2"
  fi

  health_check "$TUN" "$TARGET"
}

# ---------- UI ----------
menu() {
  clear
  echo -e "\e[35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
  echo -e "\e[1;35m   🚀 SIT / 6to4 Tunnel Manager\e[0m"
  echo -e "\e[35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
  echo "1) ➕ ساخت تونل جدید"
  echo "2) 📡 لیست تونل‌ها"
  echo "3) 🧪 تست سلامت تونل"
  echo "4) 🗑️ حذف تونل"
  echo "0) 🚪 خروج"
  echo
}

# ---------- MAIN ----------
check_root
ROLE=$(detect_role)

[[ "$ROLE" == "IR" ]] && info "نقش سرور: 🇮🇷 ایران" || info "نقش سرور: 🌍 خارج"

while true; do
  menu
  read -p "> " C
  case "$C" in
    1) create_tunnel ;;
    2) list_tunnels; read -p "Enter..." ;;
    3) check_tunnel; read -p "Enter..." ;;
    4) delete_tunnel; read -p "Enter..." ;;
    0) exit 0 ;;
    *) echo "گزینه نامعتبر"; sleep 1 ;;
  esac
done
