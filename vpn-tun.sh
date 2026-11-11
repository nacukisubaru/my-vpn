#!/bin/bash
# ПОЛНОЦЕННЫЙ VPN на macOS через TUN — как у обычного VPN-клиента.
# Покрывает ВСЁ: браузер, приложения, игры, DNS. Не зависит от системного прокси.
#
#   sudo ./vpn-tun.sh                  # поднять (нужен пароль администратора)
#   sudo ./vpn-tun.sh --off            # остановить и вернуть сеть
#   sudo ./vpn-tun.sh "vless://..."    # произвольная ссылка
#   ./vpn-tun.sh --check               # только проверить конфиг (без sudo)
#
# Требуется sing-box (.tools/sing-box, скачивается автоматически).
set -uo pipefail
cd "$(dirname "$0")"
SB=".tools/sing-box"
CFG="vpn-tun.json"

if [ ! -x "$SB" ]; then
  echo "== скачиваю sing-box =="
  mkdir -p .tools
  case "$(uname -m)" in
    arm64)  A=sing-box-1.14.4-darwin-arm64.tar.gz ;;
    x86_64) A=sing-box-1.14.4-darwin-amd64.tar.gz ;;
    *) echo "неизвестная архитектура"; exit 1 ;;
  esac
  curl -fsSL -o /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.14.4/$A" || exit 1
  tar xzf /tmp/sb.tar.gz -C /tmp && cp "/tmp/${A%.tar.gz}/sing-box" "$SB" \
    && chmod +x "$SB" && rm -rf /tmp/sb.tar.gz "/tmp/${A%.tar.gz}"
fi

if [ "${1:-}" = "--off" ]; then
  if [ -f /tmp/vpn-tun.pid ]; then
    kill "$(cat /tmp/vpn-tun.pid)" 2>/dev/null && echo "VPN остановлен"
    rm -f /tmp/vpn-tun.pid
  else
    echo "VPN не запущен (нет /tmp/vpn-tun.pid)"
  fi
  exit 0
fi

CHECK_ONLY=0
LINK=""
for a in "$@"; do
  case "$a" in
    --check) CHECK_ONLY=1 ;;
    --off)   : ;;   # обработано выше
    -*)      echo "неизвестный флаг: $a" >&2; exit 1 ;;
    *)       LINK="$a" ;;
  esac
done
[ -z "$LINK" ] && LINK=$(cat client/vless-url.txt)

# ---- ссылка -> конфиг sing-box ----
python3 - "$LINK" "$CFG" <<'PY' || exit 1
import json, sys, urllib.parse
link, out = sys.argv[1], sys.argv[2]
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
    "log": {"level": "warn", "timestamp": True},
    "dns": {
        "servers": [
            {"type": "https", "tag": "remote", "server": "1.1.1.1", "detour": "proxy"},
            {"type": "https", "tag": "remote-backup", "server": "8.8.8.8", "detour": "proxy"},
        ],
        "final": "remote",
        "strategy": "ipv4_only",
    },
    "inbounds": [{
        "type": "tun",
        "tag": "tun-in",
        "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
        "mtu": 9000,
        "auto_route": True,
        "strict_route": False,
        "stack": "mixed",
    }],
    "outbounds": [
        {"type": "vless", "tag": "proxy",
         "server": host, "server_port": int(port), "uuid": uuid,
         "flow": q.get("flow", ""),
         "tls": {"enabled": True, "server_name": q["sni"],
                 "utls": {"enabled": True, "fingerprint": q.get("fp", "chrome")},
                 "reality": {"enabled": True, "public_key": q["pbk"],
                             "short_id": q["sid"]}}},
        {"type": "direct", "tag": "direct"},
        {"type": "block", "tag": "block"},
    ],
    "route": {
        "rules": [
            {"action": "sniff"},
            {"protocol": "dns", "action": "hijack-dns"},
            {"ip_is_private": True, "outbound": "direct"},
        ],
        "final": "proxy",
        "auto_detect_interface": True,
        "default_domain_resolver": "remote",
    },
}
json.dump(cfg, open(out, "w"), indent=2, ensure_ascii=False)
print(f"   сервер {host}:{port}")
print(f"   SNI    {q['sni']}, flow {q.get('flow','(нет)')}")
PY

echo
echo "== проверка конфига =="
"$SB" check -c "$CFG" || { echo "конфиг невалиден"; exit 1; }
echo "   конфиг валиден"

if [ "$CHECK_ONLY" = "1" ]; then
  echo "   ✅ конфиг валиден (только проверка, VPN не запускался)"
  exit 0
fi

if [ "$(id -u)" != "0" ]; then
  echo
  echo "TUN требует прав администратора. Запустите:"
  echo "   sudo ./vpn-tun.sh"
  exit 1
fi

echo
echo "== предупреждение о других VPN-клиентах =="
if ps -eo comm | grep -qiE "v2raytun|hiddify|streisand|nekoray|outline"; then
  echo "   ВНИМАНИЕ: запущены другие VPN-клиенты. Закройте их, иначе будет конфликт:"
  ps -eo comm | grep -iE "v2raytun|hiddify|streisand|nekoray|outline" | sed 's/^/     /'
  echo "   (продолжаю через 5 секунд, Ctrl+C — отмена)"
  sleep 5
fi

echo "== запускаю sing-box (TUN) =="
"$SB" run -c "$CFG" > /tmp/vpn-tun.log 2>&1 &
XPID=$!
echo "$XPID" > /tmp/vpn-tun.pid

for _ in $(seq 1 20); do
  if ifconfig 2>/dev/null | grep -q "172.19.0.1"; then break; fi
  sleep 0.5
done
sleep 2

echo "== проверка =="
IP=$(curl -s --max-time 20 https://api.ipify.org)
echo "   IP через VPN: ${IP:-<нет ответа>}"
if [ "$IP" != "82.148.226.31" ]; then
  echo "   ❌ не работает. Лог:"
  tail -20 /tmp/vpn-tun.log
  kill "$XPID" 2>/dev/null
  exit 1
fi

echo
echo "══════════════════════════════════════════════════════"
echo " ✅ VPN РАБОТАЕТ (TUN, весь трафик)"
echo "    Откройте браузер — всё должно работать."
echo
echo " Остановить:  sudo ./vpn-tun.sh --off"
echo "             (или Ctrl+C здесь)"
echo "══════════════════════════════════════════════════════"
trap 'kill "$XPID" 2>/dev/null; rm -f /tmp/vpn-tun.pid; echo; echo "VPN остановлен"' EXIT INT TERM
wait "$XPID"
