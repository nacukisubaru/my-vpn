#!/bin/bash
# Диагностика «каши» из VPN-клиентов на Mac.
# Показывает: запущенные клиенты, залипшие системные прокси, порты, TUN-интерфейсы.
#   ./vpn-doctor.sh           # только показать
#   ./vpn-doctor.sh --clean   # выключить залипшие системные прокси
set -uo pipefail
cd "$(dirname "$0")"

active_service() {
  local dev
  dev=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  networksetup -listnetworkserviceorder 2>/dev/null \
    | awk -v d="Device: $dev)" 'index($0,d){print prev} {prev=$0}' | tail -1 | sed 's/^([0-9]*) //'
}

SVC=$(active_service)
echo "########## 1. Запущенные VPN-клиенты ##########"
found=0
while IFS= read -r line; do
  echo "   $line"; found=1
done < <(ps -eo pid,comm | grep -iE "v2raytun|hiddify|streisand|nekoray|outline|sing-box|xray|clash|shadowrocket" | grep -v grep)
[ "$found" = 0 ] && echo "   нет запущенных клиентов"

echo
echo "########## 2. Системные прокси (активный сервис: ${SVC:-?}) ##########"
if [ -n "$SVC" ]; then
  for kind in webproxy securewebproxy socksfirewallproxy; do
    en=$(networksetup -get${kind} "$SVC" 2>/dev/null | awk '/Enabled:/{print $2}')
    srv=$(networksetup -get${kind} "$SVC" 2>/dev/null | awk '/Server:/{print $2}')
    port=$(networksetup -get${kind} "$SVC" 2>/dev/null | awk '/Port:/{print $2}')
    if [ "$en" = "Yes" ]; then
      listening=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | grep -c LISTEN)
      if [ "$listening" = "0" ]; then
        echo "   ⚠️  $kind ВКЛЮЧЁН → $srv:$port, но НИКТО не слушает этот порт → ИНТЕРНЕТ НЕ РАБОТАЕТ"
      else
        echo "   ✅ $kind включён → $srv:$port (порт слушается)"
      fi
    else
      echo "   — $kind выключен"
    fi
  done
fi

echo
echo "########## 3. Кто слушает локальные порты ##########"
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || $9 ~ /127.0.0.1/' | grep -E "COMMAND|127.0.0.1" | head -12

echo
echo "########## 4. TUN-интерфейсы ##########"
ifconfig 2>/dev/null | grep -E "^utun|^tun" | head -8

echo
echo "########## 5. Маршрут по умолчанию ##########"
route -n get default 2>/dev/null | grep -E "gateway|interface"

echo
echo "########## Вердикт ##########"
echo "   Если в п.2 есть ⚠️ — ИМЕННО ЭТО ломает браузер: прокси включён, но мёртв."
echo "   Лечение:  ./vpn-doctor.sh --clean"
echo "   Если в п.1 несколько клиентов — оставьте ОДИН, остальные закройте."

if [ "${1:-}" = "--clean" ]; then
  echo
  echo "== выключаю все системные прокси на активном сервисе =="
  [ -z "$SVC" ] && { echo "не удалось определить сервис"; exit 1; }
  networksetup -setwebproxystate "$SVC" off 2>/dev/null
  networksetup -setsecurewebproxystate "$SVC" off 2>/dev/null
  networksetup -setsocksfirewallproxystate "$SVC" off 2>/dev/null
  echo "   готово. Проверьте интернет в браузере."
fi
