#!/bin/bash

CONF_DIR="/etc/sit6"
TUN_PREFIX="sit6"
mkdir -p $CONF_DIR

check_root() {
  [ "$EUID" -ne 0 ] && echo "❌ با root اجرا کن" && exit 1
}

detect_country() {
  IP=$(curl -s https://api.ipify.org)
  CC=$(curl -s ipapi.co/$IP/country/)
  [ "$CC" = "IR" ] && echo "IR" || echo "OUT"
}

gen_ipv6() {
  printf "fd%02x:%02x%02x:%02x%02x::1/64\n" $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM
}

load_remote_ip() {
  # بررسی وجود کانفیگ خارجی آماده
  if [ -f "$CONF_DIR/remote_ip.conf" ]; then
    OUT_IP=$(cat $CONF_DIR/remote_ip.conf)
    echo "🌐 IP سرور خارج: $OUT_IP بارگذاری شد"
  else
    read -p "IP سرور خارج: " OUT_IP
    echo $OUT_IP > $CONF_DIR/remote_ip.conf
  fi
}

create_tunnel() {
  load_remote_ip
  read -p "IP سرور ایران: " IR_IP

  ID=$(date +%s)
  TUN="${TUN_PREFIX}${ID}"
  IPV6=$(gen_ipv6)

  if [ "$ROLE" = "IR" ]; then
    LOCAL=$IR_IP
    REMOTE=$OUT_IP
    IPV6_LOCAL="${IPV6%/*}2/64"
  else
    LOCAL=$OUT_IP
    REMOTE=$IR_IP
    IPV6_LOCAL="${IPV6%/*}1/64"
  fi

  # ساخت تونل
  ip tunnel add $TUN mode sit local $LOCAL remote $REMOTE ttl 255
  ip link set $TUN up
  ip -6 addr add $IPV6_LOCAL dev $TUN

  # ذخیره تونل
  echo "$TUN $IR_IP $OUT_IP $IPV6" >> $CONF_DIR/tunnels.db

  echo "✅ تانل ساخته شد: $TUN"
  echo "🌐 IPv6 تانل: ${IPV6%/*}"

  # تست اتصال
  ping -c 2 $REMOTE &>/dev/null && echo "✔️ اتصال به $REMOTE برقرار است" || echo "⚠️ اتصال برقرار نشد"
}

list_tunnels() {
  echo "📡 تانل‌های فعال:"
  ip tunnel show | grep $TUN_PREFIX
}

delete_tunnel() {
  list_tunnels
  read -p "نام تانل: " TUN

  ip tunnel del $TUN 2>/dev/null
  sed -i "/^$TUN /d" $CONF_DIR/tunnels.db

  echo "🗑️ تانل حذف شد"
}

change_ip() {
  list_tunnels
  read -p "نام تانل: " TUN
  read -p "IP جدید ایران: " IR

  OLD=$(grep "^$TUN " $CONF_DIR/tunnels.db)
  OUT_IP=$(echo $OLD | awk '{print $3}')
  IPV6=$(echo $OLD | awk '{print $4}')

  ip tunnel del $TUN 2>/dev/null

  if [ "$ROLE" = "IR" ]; then
    LOCAL=$IR
    REMOTE=$OUT_IP
    IPV6_LOCAL="${IPV6%/*}2/64"
  else
    LOCAL=$OUT_IP
    REMOTE=$IR
    IPV6_LOCAL="${IPV6%/*}1/64"
  fi

  ip tunnel add $TUN mode sit local $LOCAL remote $REMOTE ttl 255
  ip link set $TUN up
  ip -6 addr add $IPV6_LOCAL dev $TUN

  sed -i "/^$TUN /d" $CONF_DIR/tunnels.db
  echo "$TUN $IR $OUT_IP $IPV6" >> $CONF_DIR/tunnels.db

  echo "🔁 IP ایران بروزرسانی شد و تونل مجدد ساخته شد"
}

menu() {
  echo "======================"
  echo "  SIT / 6to4 Manager"
  echo "======================"
  echo "1) ساخت تانل"
  echo "2) لیست تانل‌ها"
  echo "3) حذف تانل"
  echo "4) تغییر IP ایران تانل"
  echo "0) خروج"
}

### MAIN ###
check_root
ROLE=$(detect_country)

[ "$ROLE" = "IR" ] && echo "🇮🇷 سرور ایران" || echo "🌍 سرور خارج"

while true; do
  menu
  read -p "> " C
  case $C in
    1) create_tunnel ;;
    2) list_tunnels ;;
    3) delete_tunnel ;;
    4) change_ip ;;
    0) exit ;;
  esac
done
