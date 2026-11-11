#!/bin/bash
# Подключается к VPN нативно на Mac по vless://-ссылке (без GUI-клиентов).
#   ./connect-link.sh                       — берёт client/vless-url.txt
#   ./connect-link.sh "vless://..."         — произвольная ссылка
#   ./connect-link.sh --system              — + включить системный прокси macOS
#   ./connect-link.sh --config out.json "vless://..."  — сохранить Xray-конфиг
#
# Поднимает SOCKS5 на 127.0.0.1:$(PORT) и проверяет реальную передачу данных.
set -uo pipefail
cd "$(dirname "$0")"
XRAY=".tools/xray"
SOCKS_PORT=11080
OUT_CFG=""

SYSTEM_PROXY=0
if [ "${1:-}" = "--config" ]; then OUT_CFG="$2"; shift 2; fi
if [ "${1:-}" = "--system" ]; then SYSTEM_PROXY=1; shift; fi
[ "${1:-}" = "--config" ] && { OUT_CFG="$2"; shift 2; }
LINK="${1:-}"
[ -z "$LINK" ] && LINK=$(cat client/vless-url.txt)

# ---- Xray для macOS, если ещё нет ----
if [ ! -x "$XRAY" ]; then
  echo "== скачиваю Xray-core для macOS =="
  mkdir -p .tools
  case "$(uname -m)" in
    arm64)  A=Xray-macos-arm64-v8a.zip ;;
    x86_64) A=Xray-macos-64.zip ;;
    *) echo "неизвестная архитектура"; exit 1 ;;
  esac
  curl -fsSL -o /tmp/x.zip "https://github.com/XTLS/Xray-core/releases/download/v26.10.31/$A" || exit 1
  unzip -oq /tmp/x.zip -d .tools && rm -f /tmp/x.zip && chmod +x "$XRAY"
fi

# ---- vless:// -> Xray config.json ----
CFG=/tmp/vless-live.json
python3 - "$LINK" "$SOCKS_PORT" "$CFG" <<'PY' || exit 1
import json, sys, urllib.parse
link, socks_port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]

if not link.startswith("vless://"):
    sys.exit("это не vless:// ссылка")

body = link[len("vless://"):].split("#")[0]
main, _, query = body.partition("?")
uuid, _, hostport = main.rpartition("@")
host, _, port = hostport.rpartition(":")

q = {}
for pair in query.split("&"):
    if pair:
        k, _, v = pair.partition("=")
        q[k.lower()] = urllib.parse.unquote(v)

for need in ("pbk", "sid", "sni"):
    if need not in q:
        sys.exit(f"в ссылке нет параметра {need}")

print("=== ЧТО РАЗОБРАНО ИЗ ССЫЛКИ ===")
print(f"  адрес сервера : {host}")
print(f"  порт          : {port}")
print(f"  UUID          : {uuid}")
print(f"  flow          : {q.get('flow', '(нет)')}")
print(f"  transport     : {q.get('type', 'tcp')}")
print(f"  security      : {q.get('security')}")
print(f"  SNI           : {q['sni']}")
print(f"  fingerprint   : {q.get('fp', 'chrome')}")
print(f"  publicKey     : {q['pbk']}")
print(f"  shortId       : {q['sid']}")
print(f"  spiderX       : {q.get('spx', '/')}")
print()

cfg = {
    "log": {"loglevel": "info"},
    "inbounds": [{
        "tag": "socks-in", "listen": "127.0.0.1", "port": socks_port, "protocol": "socks",
        "settings": {"auth": "noauth", "udp": True, "ip": "127.0.0.1"},
        "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]},
    }],
    "outbounds": [
        {"tag": "proxy", "protocol": "vless",
         "settings": {"vnext": [{
             "address": host, "port": int(port),
             "users": [{"id": uuid, "encryption": q.get("encryption", "none"),
                        "flow": q.get("flow", "")}]}]},
         "streamSettings": {
             "network": q.get("type", "tcp"),
             "security": q.get("security", "none"),
             "realitySettings": {
                 "serverName": q["sni"],
                 "fingerprint": q.get("fp", "chrome"),
                 "publicKey": q["pbk"],
                 "shortId": q["sid"],
                 "spiderX": q.get("spx", "/"),
             }}},
        {"tag": "direct", "protocol": "freedom", "settings": {}},
    ],
    "routing": {"rules": [{"type": "field", "network": "tcp,udp", "outboundTag": "proxy"}]},
}
json.dump(cfg, open(out, "w"), indent=2, ensure_ascii=False)
print(f"=== XRAY-КОНФИГ СОБРАН: {out} ===")
PY

[ -n "$OUT_CFG" ] && cp "$CFG" "$OUT_CFG" && echo "конфиг сохранён в $OUT_CFG"

# ---- запуск ----
echo
echo "=== ЗАПУСК XRAY ==="
SERVICE=$(networksetup -listnetworkserviceorder 2>/dev/null \
  | awk -F': ' '/Wi-Fi|Ethernet/{print $2; exit}' | sed 's/^[0-9]*) //')

cleanup() {
  kill "$XPID" 2>/dev/null
  if [ "$SYSTEM_PROXY" = "1" ] && [ -n "$SERVICE" ]; then
    networksetup -setsocksfirewallproxystate "$SERVICE" off 2>/dev/null
    networksetup -setwebproxystate "$SERVICE" off 2>/dev/null
    networksetup -setsecurewebproxystate "$SERVICE" off 2>/dev/null
    echo "   системный прокси выключен"
  fi
  echo "остановлено"
}
trap cleanup EXIT INT TERM

"$XRAY" run -c "$CFG" > /tmp/vless-live.log 2>&1 &
XPID=$!

for _ in $(seq 1 20); do
  nc -z 127.0.0.1 "$SOCKS_PORT" 2>/dev/null && break
  sleep 0.5
done
sleep 1

echo
echo "=== ПРОВЕРКА ТРАФИКА ЧЕРЕЗ SOCKS 127.0.0.1:$SOCKS_PORT ==="
IP=$(curl -s --max-time 20 --socks5-hostname "127.0.0.1:$SOCKS_PORT" https://api.ipify.org)
echo "  IP без VPN : $(curl -s --max-time 10 https://api.ipify.org)"
echo "  IP с VPN   : ${IP:-<нет ответа>}"
echo
for u in https://www.google.com https://www.youtube.com https://github.com; do
  printf "  %-28s " "$u"
  curl -s -o /dev/null --max-time 30 --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
    -w "http=%{http_code} bytes=%{size_download} время=%{time_total}s\n" "$u"
done

echo
echo "=== ЛОГ XRAY (реальные соединения) ==="
grep -E "accepted|reality|failed|error" /tmp/vless-live.log | tail -10

if [ "$IP" = "82.148.226.31" ]; then
  echo
  echo "✅ ТУННЕЛЬ РАБОТАЕТ"
  if [ "$SYSTEM_PROXY" = "1" ] && [ -n "$SERVICE" ]; then
    echo "   включаю системный прокси (сервис: $SERVICE)"
    networksetup -setsocksfirewallproxy "$SERVICE" 127.0.0.1 "$SOCKS_PORT" >/dev/null 2>&1
    networksetup -setsocksfirewallproxystate "$SERVICE" on >/dev/null 2>&1
    echo "   Готово: откройте браузер и проверьте https://api.ipify.org"
    echo "   Должен быть IP 82.148.226.31"
  fi
  echo "   Держите этот процесс запущенным, Ctrl+C — остановить."
  wait $XPID
else
  echo
  echo "❌ ТУННЕЛЬ НЕ РАБОТАЕТ — смотрите лог выше"
  exit 1
fi
