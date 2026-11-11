#!/bin/bash
# Послойная диагностика: понять, на каком уровне ломается.
# Запуск с Mac: ./diag.sh
set -uo pipefail
cd "$(dirname "$0")"
HOST=$(python3 -c "import json;print(json.load(open('secrets/server.json'))['host'])")
SNI=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['sni'])")
SNI2=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['backup_inbound']['sni'])")
PORT=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['port'])")
PORT2=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['backup_inbound']['port'])")

echo "########## 1. Сеть до сервера ##########"
for p in 22 "$PORT" "$PORT2"; do
  if nc -z -G 8 "$HOST" "$p" 2>/dev/null; then echo "  $p/tcp  OK"; else echo "  $p/tcp  НЕДОСТУПЕН"; fi
done

echo
echo "########## 2. TLS-маскировка (DPI видит обычный HTTPS) ##########"
for pair in "$PORT $SNI" "$PORT2 $SNI2"; do
  set -- $pair; port=$1; sni=$2
  out=$(echo | openssl s_client -connect "$HOST:$port" -servername "$sni" -tls1_3 -alpn h2 2>/dev/null)
  cn=$(echo "$out" | grep -m1 "subject=")
  alpn=$(echo "$out" | grep -m1 "ALPN")
  if [ -n "$cn" ]; then echo "  :$port SNI=$sni  OK"; echo "     $cn"; echo "     $alpn"
  else echo "  :$port SNI=$sni  ПРОВАЛ (сервер не отвечает как $sni — возможна блокировка по SNI/IP)"; fi
done

echo
echo "########## 3. Реальный туннель (изолированный контейнер) ##########"
docker build -q -t vpn-test-client ./client >/dev/null 2>&1 || { echo "  docker недоступен"; exit 0; }
for pair in "$PORT config-phone$PORT" "$PORT2 config-phone$PORT2"; do
  set -- $pair; port=$1; cfg=$2
  docker rm -f diag-c >/dev/null 2>&1
  docker run -d --name diag-c -v "$PWD/client:/cfg:ro" vpn-test-client -config "/cfg/$cfg.json" >/dev/null 2>&1
  for _ in $(seq 1 20); do docker exec diag-c sh -c 'nc -z 127.0.0.1 1080' >/dev/null 2>&1 && break; sleep 0.5; done
  ip=$(docker exec diag-c sh -c 'curl -s --max-time 15 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org' 2>/dev/null)
  if [ "$ip" = "$HOST" ]; then echo "  :$port туннель OK (выход $ip)"; else echo "  :$port туннель НЕ работает (ответ: '${ip:-нет}')"; fi
  docker rm -f diag-c >/dev/null 2>&1
done

echo
echo "########## 4. Сервер ##########"
./rssh.sh "echo \"  x-ui: \$(systemctl is-active x-ui) | xray: \$(pgrep -c -f 'xray-linux-amd64 -c') | load: \$(cut -d' ' -f1-3 /proc/loadavg)\"; ss -tulpn | grep -E ':${PORT} |:${PORT2} ' | sed 's/^/  /'" 2>/dev/null || echo "  SSH недоступен"

echo
echo "########## Вердикт ##########"
echo "  П.1 упал      → блок по IP/порту на стороне провайдера → ротация порта или другой IP сервера"
echo "  П.2 упал      → блок по SNI/dest       → ./rotate.sh --sni <другой домен>"
echo "  П.2 ок, П.3 упал → клиент/ключи        → ./sync-client.sh и переимпортируйте ссылки"
echo "  Всё ок        → проблема в приложении на устройстве (переимпортируйте профиль/подписку)"
