#!/bin/bash
# Локальный VPN на Mac без сторонних приложений (Xray + системный SOCKS/HTTP прокси).
#   ./mac-vpn.sh            — запустить (SOCKS 127.0.0.1:1080, HTTP 127.0.0.1:1081)
#   ./mac-vpn.sh --system   — ещё и включить системный прокси macOS (с авто-откатом по Ctrl+C)
#   ./mac-vpn.sh --test     — только проверить конфиг и связь, ничего не включать
set -uo pipefail
cd "$(dirname "$0")"

XRAY=".tools/xray"
CFG="client/config.json"
SOCKS="127.0.0.1:1080"
HTTPP="127.0.0.1:1081"
SERVICE=$(networksetup -listnetworkserviceorder 2>/dev/null | awk -F': ' '/Wi-Fi|Ethernet/{print $2; exit}' | sed 's/^[0-9]*) //')
SYSTEM=0; TEST=0
for a in "$@"; do case "$a" in --system) SYSTEM=1;; --test) TEST=1;; esac; done

if [ ! -x "$XRAY" ]; then
  echo "== скачиваю Xray-core для macOS =="
  mkdir -p .tools
  arch=$(uname -m); case "$arch" in arm64) A=Xray-macos-arm64-v8a.zip;; x86_64) A=Xray-macos-64.zip;; *) echo "неизвестная архитектура $arch"; exit 1;; esac
  curl -fsSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.10.31/$A" || { echo "не удалось скачать"; exit 1; }
  unzip -oq /tmp/xray.zip -d .tools && rm -f /tmp/xray.zip && chmod +x "$XRAY"
fi

echo "== проверка конфига =="
"$XRAY" run -c "$CFG" -test 2>&1 | grep -E "Configuration OK|failed" || exit 1
[ "$TEST" = "1" ] && { echo "конфиг валиден"; exit 0; }

cleanup() {
  [ -n "${XPID:-}" ] && kill "$XPID" 2>/dev/null
  if [ "$SYSTEM" = "1" ]; then
    networksetup -setwebproxystate "$SERVICE" off 2>/dev/null
    networksetup -setsecurewebproxystate "$SERVICE" off 2>/dev/null
    networksetup -setsocksfirewallproxystate "$SERVICE" off 2>/dev/null
    echo "системный прокси выключен"
  fi
  echo "остановлено"
}
trap cleanup EXIT INT TERM

"$XRAY" run -c "$CFG" > /tmp/mac-vpn.log 2>&1 &
XPID=$!
sleep 3

echo "== проверка туннеля =="
IP=$(curl -s --max-time 20 --socks5-hostname "$SOCKS" https://api.ipify.org)
DIRECT=$(curl -s --max-time 10 https://api.ipify.org)
echo "  без VPN: $DIRECT"
echo "  с VPN  : ${IP:-<нет ответа>}"
if [ "$IP" = "82.148.226.31" ]; then echo "  ✅ туннель работает"; else echo "  ❌ туннель не работает, лог: /tmp/mac-vpn.log"; tail -20 /tmp/mac-vpn.log; exit 1; fi

if [ "$SYSTEM" = "1" ]; then
  echo "== включаю системный прокси (сервис: $SERVICE) =="
  networksetup -setsocksfirewallproxy "$SERVICE" 127.0.0.1 1080
  networksetup -setwebproxy "$SERVICE" 127.0.0.1 1081
  networksetup -setsecurewebproxy "$SERVICE" 127.0.0.1 1081
  networksetup -setsocksfirewallproxystate "$SERVICE" on
  networksetup -setwebproxystate "$SERVICE" on
  networksetup -setsecurewebproxystate "$SERVICE" on
  echo "  прокси включён. Откройте https://2ip.ru — должен быть IP 82.148.226.31"
fi

echo
echo "VPN работает. SOCKS5: $SOCKS · HTTP: $HTTPP"
echo "Ctrl+C — выключить."
wait "$XPID"
