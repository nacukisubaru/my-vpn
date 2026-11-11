#!/bin/bash
# Проверка туннеля в изолированном docker-контейнере.
# Хост-система не затрагивается: наружу ходим только через SOCKS внутри контейнера.
set -uo pipefail
cd "$(dirname "$0")"

echo "== 1. Сборка образа клиента (Xray-core) =="
docker build -q -t vpn-test-client ./client || exit 1

echo "== 2. Запуск контейнера с клиентом =="
docker rm -f vpn-test >/dev/null 2>&1
docker run -d --name vpn-test --cap-add=NET_ADMIN \
  -v "$PWD/client:/cfg:ro" vpn-test-client -config /cfg/config.json >/dev/null
sleep 4
echo "--- логи клиента ---"
docker logs vpn-test 2>&1 | tail -20

run() { docker exec vpn-test sh -c "$1"; }

echo
echo "== 3. Прямой выход из контейнера (без туннеля) =="
DIRECT_IP=$(run 'curl -s --max-time 15 https://api.ipify.org')
echo "IP без туннеля: ${DIRECT_IP:-<нет ответа>}"

echo
echo "== 4. Выход через VLESS/Reality (SOCKS 127.0.0.1:1080) =="
PROXY_IP=$(run 'curl -s --max-time 20 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org')
echo "IP через туннель: ${PROXY_IP:-<нет ответа>}"

echo
echo "== 5. HTTP через туннель =="
for u in https://www.google.com https://www.youtube.com https://www.apple.com https://ifconfig.me/ip https://www.gstatic.com/generate_204; do
  code=$(run "curl -s -o /dev/null -w '%{http_code}' --max-time 25 --socks5-hostname 127.0.0.1:1080 $u")
  echo "  $u -> ${code:-fail}"
done

echo
echo "== 5b. Стабильность: 10 подряд запросов через туннель =="
OK=0
for i in $(seq 1 10); do
  code=$(run "curl -s -o /dev/null -w '%{http_code}' --max-time 20 --socks5-hostname 127.0.0.1:1080 https://www.gstatic.com/generate_204")
  [ "$code" = "204" ] && OK=$((OK+1))
done
echo "  успешных: ${OK}/10"

echo
echo "== 6. Скорость (10 MB через туннель, Cloudflare) =="
run 'curl -s -o /dev/null --max-time 90 -w "скачано=%{size_download} байт, скорость=%{speed_download} байт/с, время=%{time_total} с\n" \
  --socks5-hostname 127.0.0.1:1080 "https://speed.cloudflare.com/__down?bytes=10000000"'

echo
echo "== 7. HTTP-прокси 1081 (для браузера) =="
run 'curl -s --max-time 20 -x http://127.0.0.1:1081 https://api.ipify.org; echo'

echo
echo "== 8. Гео/ASN IP через туннель =="
run 'curl -s --max-time 20 --socks5-hostname 127.0.0.1:1080 "http://ip-api.com/line?fields=status,country,city,isp,as,query"'

echo
echo "== ИТОГ =="
echo "IP хоста/провайдера: ${DIRECT_IP:-?}"
echo "IP после VPN:       ${PROXY_IP:-?}"
if [ -n "${PROXY_IP:-}" ] && [ "${PROXY_IP}" = "82.148.226.31" ]; then
  echo "РЕЗУЛЬТАТ: OK — трафик идёт через VPN-сервер 82.148.226.31"
else
  echo "РЕЗУЛЬТАТ: FAIL — проверь логи выше"
fi
