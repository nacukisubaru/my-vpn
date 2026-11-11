#!/bin/bash
# VPN для браузера и всех приложений, которые уважают системный прокси macOS.
# НЕ требует sudo. При выходе (Ctrl+C) возвращает прежние настройки прокси.
#
#   ./vpn-browser.sh                 # взять client/vless-url.txt
#   ./vpn-browser.sh "vless://..."   # произвольная ссылка
#   ./vpn-browser.sh --off           # просто выключить прокси (если что-то зависло)
#
# Что делает:
#   1. поднимает Xray: SOCKS5 127.0.0.1:1080 + HTTP 127.0.0.1:1081
#   2. ставит системные прокси macOS (HTTP/HTTPS/SOCKS) на эти порты
#   3. проверяет, что трафик реально идёт через VPN
#   4. по Ctrl+C возвращает прежние настройки
set -uo pipefail
cd "$(dirname "$0")"
XRAY=".tools/xray"
STATE="/tmp/vpn-browser-orig.txt"
SOCKS_PORT=1080
HTTP_PORT=1081

# Только ТОТ сервис, через который реально идёт трафик (default route).
# Трогать все сервисы нельзя: там висят Outline/Hiddify/v2RayTun и они конфликтуют.
active_service() {
  local dev svc
  dev=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  [ -z "$dev" ] && return 1
  svc=$(networksetup -listnetworkserviceorder 2>/dev/null \
        | awk -v d="Device: $dev)" 'index($0, d) {print prev} {prev=$0}' \
        | tail -1 | sed 's/^([0-9]*) //')
  [ -z "$svc" ] && return 1
  printf '%s\n' "$svc"
}

services() { active_service; }

save_state() {
  : > "$STATE"
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    {
      echo "SERVICE=$s"
      networksetup -getwebproxy "$s" 2>/dev/null | sed 's/^/WEB_/'
      networksetup -getsecurewebproxy "$s" 2>/dev/null | sed 's/^/SECURE_/'
      networksetup -getsocksfirewallproxy "$s" 2>/dev/null | sed 's/^/SOCKS_/'
      echo "---"
    } >> "$STATE"
  done < <(services)
}

proxy_off() {
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    networksetup -setwebproxystate "$s" off 2>/dev/null
    networksetup -setsecurewebproxystate "$s" off 2>/dev/null
    networksetup -setsocksfirewallproxystate "$s" off 2>/dev/null
  done < <(services)
}

if [ "${1:-}" = "--off" ]; then
  proxy_off
  echo "системные прокси выключены на всех сервисах"
  networksetup -getwebproxy "$(services | head -1)" | head -3
  exit 0
fi

LINK="${1:-}"
[ -z "$LINK" ] && LINK=$(cat client/vless-url.txt)

if [ ! -x "$XRAY" ]; then
  echo "== скачиваю Xray-core =="
  mkdir -p .tools
  case "$(uname -m)" in
    arm64)  A=Xray-macos-arm64-v8a.zip ;;
    x86_64) A=Xray-macos-64.zip ;;
    *) echo "неизвестная архитектура"; exit 1 ;;
  esac
  curl -fsSL -o /tmp/x.zip "https://github.com/XTLS/Xray-core/releases/download/v26.10.31/$A" || exit 1
  unzip -oq /tmp/x.zip -d .tools && rm -f /tmp/x.zip && chmod +x "$XRAY"
fi

# ---- ссылка -> конфиг с SOCKS + HTTP ----
CFG=/tmp/vpn-browser.json
python3 - "$LINK" "$CFG" "$SOCKS_PORT" "$HTTP_PORT" <<'PY' || exit 1
import json, sys, urllib.parse
link, out, socks, http = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
body = link[len("vless://"):].split("#")[0]
main, _, qs = body.partition("?")
uuid, _, hostport = main.rpartition("@")
host, _, port = hostport.rpartition(":")
q = {}
for p in qs.split("&"):
    if p:
        k, _, v = p.partition("=")
        q[k.lower()] = urllib.parse.unquote(v)
for need in ("pbk", "sid", "sni"):
    if need not in q:
        sys.exit(f"в ссылке нет {need}")
cfg = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        {"tag": "socks", "listen": "127.0.0.1", "port": socks, "protocol": "socks",
         "settings": {"auth": "noauth", "udp": True, "ip": "127.0.0.1"},
         "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}},
        # ВАЖНО: без sniffing — с ним Xray не отдаёт ответы на CONNECT
        # (запросы принимаются, но соединение висит до таймаута).
        {"tag": "http", "listen": "127.0.0.1", "port": http, "protocol": "http",
         "settings": {"allowTransparent": False}},
    ],
    "outbounds": [
        {"tag": "proxy", "protocol": "vless",
         "settings": {"vnext": [{"address": host, "port": int(port),
            "users": [{"id": uuid, "encryption": q.get("encryption", "none"),
                       "flow": q.get("flow", "")}]}]},
         "streamSettings": {"network": q.get("type", "tcp"),
            "security": q.get("security", "none"),
            "realitySettings": {"serverName": q["sni"],
                "fingerprint": q.get("fp", "chrome"),
                "publicKey": q["pbk"], "shortId": q["sid"],
                "spiderX": q.get("spx", "/")}}},
        {"tag": "direct", "protocol": "freedom", "settings": {}},
    ],
    "routing": {"rules": [{"type": "field", "network": "tcp,udp", "outboundTag": "proxy"}]},
}
json.dump(cfg, open(out, "w"), indent=2, ensure_ascii=False)
print(f"   сервер {host}:{port}, SNI {q['sni']}")
PY

echo
echo "== сохраняю текущие настройки прокси =="
save_state
echo "   было сохранено в $STATE"

cleanup() {
  kill "${XPID:-0}" 2>/dev/null
  proxy_off
  echo
  echo "== прокси выключены, прежние настройки не тронуты =="
  echo "   (при необходимости вернуть вручную: Системные настройки → Сеть → Прокси)"
}
trap cleanup EXIT INT TERM

# предупреждение о конфликте с другими клиентами
CONFLICT=$(ps -eo comm | grep -iE "v2raytun|hiddify|streisand|nekoray|outline" | head -3)
if [ -n "$CONFLICT" ]; then
  echo
  echo "⚠️  Запущены другие VPN-клиенты — они будут драться за прокси:"
  echo "$CONFLICT" | sed 's/^/     /'
  echo "   Закройте их, иначе браузер будет работать нестабильно."
  echo
fi

echo "== запускаю Xray =="
"$XRAY" run -c "$CFG" > /tmp/vpn-browser.log 2>&1 &
XPID=$!
for _ in $(seq 1 20); do nc -z 127.0.0.1 "$SOCKS_PORT" 2>/dev/null && break; sleep 0.5; done
sleep 1

echo "== проверка туннеля =="
IP=$(curl -s --max-time 20 --socks5-hostname "127.0.0.1:$SOCKS_PORT" https://api.ipify.org)
echo "   IP без VPN : $(curl -s --max-time 8 https://api.ipify.org)"
echo "   IP с VPN   : ${IP:-<нет ответа>}"
if [ "$IP" != "82.148.226.31" ]; then
  echo "   ❌ туннель не работает — прокси не включаю"
  tail -10 /tmp/vpn-browser.log
  exit 1
fi

echo "== включаю системные прокси =="
while IFS= read -r s; do
  [ -z "$s" ] && continue
  networksetup -setwebproxy "$s" 127.0.0.1 "$HTTP_PORT" 2>/dev/null
  networksetup -setsecurewebproxy "$s" 127.0.0.1 "$HTTP_PORT" 2>/dev/null
  networksetup -setsocksfirewallproxy "$s" 127.0.0.1 "$SOCKS_PORT" 2>/dev/null
  networksetup -setwebproxystate "$s" on 2>/dev/null
  networksetup -setsecurewebproxystate "$s" on 2>/dev/null
  networksetup -setsocksfirewallproxystate "$s" on 2>/dev/null
  echo "   $s → HTTP 127.0.0.1:$HTTP_PORT, SOCKS 127.0.0.1:$SOCKS_PORT"
done < <(services)

echo
echo "══════════════════════════════════════════════════════"
echo " ГОТОВО. Откройте браузер и проверьте:"
echo "   https://api.ipify.org  →  должен быть 82.148.226.31"
echo
echo " Ctrl+C — выключить VPN и вернуть прокси."
echo "══════════════════════════════════════════════════════"
wait "$XPID"
