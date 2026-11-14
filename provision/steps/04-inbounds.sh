#!/bin/bash
# Шаг 4: проверка доменов-маскировок и создание инбаундов через API панели.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
source /tmp/prov-keys.env

step "4/6 создание инбаундов"

PROV_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# check_sni <domain> — 1 если домен годится под Reality
check_sni() {
  local d="$1" out
  out=$(srv "echo | timeout 20 openssl s_client -connect ${d}:443 -servername ${d} -tls1_3 -alpn h2 2>/dev/null | grep -E 'subject=|ALPN protocol: h2'") || return 1
  case "$out" in
    *"subject="*"ALPN protocol: h2"*) return 0 ;;
    *) return 1 ;;
  esac
}

info "проверяю домен-маскировку для основного входа: ${S_SNI}"
if check_sni "$S_SNI"; then
  ok "${S_SNI}: TLS 1.3 + HTTP/2, сертификат на месте"
else
  warn "${S_SNI} не подходит, ищу рабочий из data/sni.txt"
  FOUND=""
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    if check_sni "$cand"; then FOUND="$cand"; break; fi
  done < <(grep -v '^[[:space:]]*#' "$PROV_DIR/../data/sni.txt" | sed 's/#.*//' | tr -d ' ' | grep -v '^$')
  [ -z "$FOUND" ] && die "ни один домен из data/sni.txt не подошёл"
  S_SNI="$FOUND"
  ok "выбран ${S_SNI}"
fi

info "проверяю домен-маскировку для резервного входа: ${S_SNI2}"
if check_sni "$S_SNI2"; then
  ok "${S_SNI2}: TLS 1.3 + HTTP/2"
else
  die "${S_SNI2} не подходит. Укажите другой: make install S_SNI2=<домен>"
fi

export S_HOST S_SNI S_SNI2 S_MAIN_PORT S_BACKUP_PORT
export K1_PRIV K1_PUB K2_PRIV K2_PUB SID1A SID1B SID2A SID2B U_MAIN U_PHONE U_BACKUP
export PROV_FP PROV_FLOW PROV_REMARK_MAIN PROV_REMARK_BACKUP

info "собираю payload основного входа (:${S_MAIN_PORT})"
python3 "$PROV_DIR/build-inbounds.py" main /tmp/prov-main.json || die "не удалось собрать payload"

info "создаю основной инбаунд"
api_ok POST /panel/api/inbounds/add /tmp/prov-main.json >/dev/null \
  || die "панель не приняла основной инбаунд"
ok "основной вход создан"

info "собираю payload резервного входа (:${S_BACKUP_PORT})"
python3 "$PROV_DIR/build-inbounds.py" backup /tmp/prov-backup.json || die "не удалось собрать payload"

info "создаю резервный инбаунд"
api_ok POST /panel/api/inbounds/add /tmp/prov-backup.json >/dev/null \
  || die "панель не приняла резервный инбаунд"
ok "резервный вход создан"

info "открываю порты в firewall"
srv "ufw allow ${S_MAIN_PORT}/tcp >/dev/null 2>&1; ufw allow ${S_BACKUP_PORT}/tcp >/dev/null 2>&1" >/dev/null 2>&1
ok "ufw: ${S_MAIN_PORT}/tcp, ${S_BACKUP_PORT}/tcp"

info "проверяю, что порты реально слушаются"
LISTEN_OK=0
for attempt in 1 2 3; do
  if srv "ss -tulpn 2>/dev/null | grep -qE ':${S_MAIN_PORT} ' && ss -tulpn 2>/dev/null | grep -qE ':${S_BACKUP_PORT} '"; then
    LISTEN_OK=1; break
  fi
  warn "порты не слушаются — перезапускаю x-ui (попытка $attempt)"
  srv 'systemctl restart x-ui' >/dev/null 2>&1
  sleep 8
done
[ "$LISTEN_OK" = "1" ] || {
  srv 'journalctl -u x-ui --since "-3min" --no-pager | tail -25'
  die "xray не поднял порты ${S_MAIN_PORT}/${S_BACKUP_PORT}"
}
ok "порты ${S_MAIN_PORT} и ${S_BACKUP_PORT} слушаются"

info "получаю id созданных инбаундов"
api GET /panel/api/inbounds/list > /tmp/prov-list.json || die "не удалось прочитать список инбаундов"
read -r ID_MAIN ID_BACKUP < <(python3 - <<PY
import json
lst = json.load(open("/tmp/prov-list.json"))["obj"]
main = next((i["id"] for i in lst if i["port"] == int("${S_MAIN_PORT}")), 0)
back = next((i["id"] for i in lst if i["port"] == int("${S_BACKUP_PORT}")), 0)
print(main, back)
PY
)
[ "$ID_MAIN" = "0" ] || [ "$ID_BACKUP" = "0" ] && die "не нашёл созданные инбаунды в панели"
printf 'ID_MAIN=%s\nID_BACKUP=%s\n' "$ID_MAIN" "$ID_BACKUP" > /tmp/prov-ids.env
ok "id: основной=$ID_MAIN, резервный=$ID_BACKUP"
