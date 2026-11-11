#!/bin/bash
# Проверка всех входов (основной + резервный) в изолированных контейнерах.
# Порты берутся из secrets/vpn.json, ничего не захардкожено.
set -uo pipefail
cd "$(dirname "$0")"
docker build -q -t vpn-test-client ./client >/dev/null || exit 1

check() {
  local cfg="$1" label="$2"
  docker rm -f vpn-chk >/dev/null 2>&1
  docker run -d --name vpn-chk -v "$PWD/client:/cfg:ro" \
    vpn-test-client -config "/cfg/$(basename "$cfg")" >/dev/null 2>&1
  for _ in $(seq 1 20); do
    docker exec vpn-chk sh -c 'nc -z 127.0.0.1 1080' >/dev/null 2>&1 && break
    sleep 0.5
  done
  sleep 1
  local ip ok=0
  ip=$(docker exec vpn-chk sh -c 'curl -s --max-time 20 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org')
  for i in $(seq 1 5); do
    c=$(docker exec vpn-chk sh -c 'curl -s -o /dev/null -w "%{http_code}" --max-time 20 --socks5-hostname 127.0.0.1:1080 https://www.gstatic.com/generate_204')
    [ "$c" = "204" ] && ok=$((ok+1))
  done
  if [ "$ip" = "82.148.226.31" ]; then
    printf "  %-28s ✅ IP %s  стабильность %s/5\n" "$label" "$ip" "$ok"
  else
    printf "  %-28s ❌ ответ '%s'  стабильность %s/5\n" "$label" "${ip:-нет}" "$ok"
  fi
  docker rm -f vpn-chk >/dev/null 2>&1
}

PORT=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['port'])")
SNI=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['sni'])")
PORT2=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['backup_inbound']['port'])")
SNI2=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['backup_inbound']['sni'])")

echo "== Основной вход :$PORT (SNI $SNI) =="
check "client/config.json" ":$PORT main"
echo "== Резервный вход :$PORT2 (SNI $SNI2) =="
check "client/config-phone$PORT2.json" ":$PORT2 backup"
