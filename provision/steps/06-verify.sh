#!/bin/bash
# Шаг 6: сквозная проверка — реальный туннель в изолированном контейнере.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

step "6/6 проверка туннеля"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

info "собираю клиентские конфиги из панели"
./sync-client.sh >/dev/null 2>&1 || warn "sync-client.sh завершился с предупреждениями"

if ! docker info >/dev/null 2>&1; then
  warn "Docker не запущен — проверка туннеля пропущена."
  warn "Запустите Docker Desktop и выполните: ./diag.sh"
  exit 0
fi

info "проверяю TCP-доступность портов с этой машины"
for pair in "${S_HOST}:${S_MAIN_PORT}" "${S_HOST}:${S_BACKUP_PORT}"; do
  h=${pair%:*}; p=${pair#*:}
  if nc -z -G 8 "$h" "$p" 2>/dev/null; then ok "  $h:$p доступен"; else warn "  $h:$p НЕ доступен"; fi
done

info "собираю образ клиента"
docker build -q -t vpn-test-client ./client >/dev/null 2>&1 || die "не удалось собрать образ клиента"
ok "образ собран"

check_tunnel() {
  local cfg="$1" label="$2" ip ok=0
  docker rm -f prov-check >/dev/null 2>&1
  docker run -d --name prov-check -v "$PWD/client:/cfg:ro" \
    vpn-test-client -config "/cfg/$(basename "$cfg")" >/dev/null 2>&1
  for _ in $(seq 1 24); do
    docker exec prov-check sh -c 'nc -z 127.0.0.1 1080' >/dev/null 2>&1 && break
    sleep 0.5
  done
  sleep 1
  ip=$(docker exec prov-check sh -c 'curl -s --max-time 20 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org' 2>/dev/null)
  for _ in $(seq 1 3); do
    c=$(docker exec prov-check sh -c 'curl -s -o /dev/null -w "%{http_code}" --max-time 20 --socks5-hostname 127.0.0.1:1080 https://www.gstatic.com/generate_204' 2>/dev/null)
    [ "$c" = "204" ] && ok=$((ok+1))
  done
  docker rm -f prov-check >/dev/null 2>&1
  if [ "$ip" = "$S_HOST" ]; then
    printf "  %s %-10s IP %s, стабильность %s/3\n" "$C_GREEN✓$C_RESET" "$label" "$ip" "$ok"
    return 0
  fi
  printf "  %s %-10s ответ '%s', стабильность %s/3\n" "$C_RED✗$C_RESET" "$label" "${ip:-нет}" "$ok"
  return 1
}

FAIL=0
info "туннель: основной вход"
check_tunnel client/config.json "основной" || FAIL=1

if [ -f "client/config-phone${S_BACKUP_PORT}.json" ]; then
  info "туннель: резервный вход"
  check_tunnel "client/config-phone${S_BACKUP_PORT}.json" "резервный" || FAIL=1
fi

echo
if [ "$FAIL" = "0" ]; then
  ok "туннель работает на обоих входах"
else
  warn "туннель не подтвердился — смотрите: ./diag.sh"
fi
