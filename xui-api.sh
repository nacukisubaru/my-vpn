#!/bin/bash
# Обёртка над API панели 3x-ui (панель слушает только localhost на сервере).
#   ./xui-api.sh GET  /panel/api/inbounds/list
#   ./xui-api.sh POST /panel/api/inbounds/update/1 payload.json
# Падает с кодом 1, если ответ пустой/не JSON — чтобы вызывающие скрипты
# не продолжали работу с «тихо пустым» результатом.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
METHOD="${1:?usage: xui-api.sh METHOD PATH [payload.json]}"
APIPATH="${2:?path required}"
PAYLOAD="${3:-}"
TOKEN=$(python3 -c "import json;print(json.load(open('$DIR/secrets/panel.json'))['api_token'])")
PORT=$(python3 -c "import json;print(json.load(open('$DIR/secrets/panel.json'))['panel_port'])")
BASE=$(python3 -c "import json;d=json.load(open('$DIR/secrets/panel.json'));print(d['panel_path'])")
URL="http://127.0.0.1:${PORT}/${BASE}${APIPATH}"

call_api() {
  if [ -n "$PAYLOAD" ]; then
    "$DIR/rssh.sh" -f "$PAYLOAD" "cat > /tmp/xui-payload.json" >/dev/null 2>&1 || return 1
    "$DIR/rssh.sh" "curl -s --max-time 30 -H 'Authorization: Bearer ${TOKEN}' -H 'Content-Type: application/json' -X ${METHOD} '${URL}' -d @/tmp/xui-payload.json; rm -f /tmp/xui-payload.json"
  else
    "$DIR/rssh.sh" "curl -s --max-time 30 -H 'Authorization: Bearer ${TOKEN}' -X ${METHOD} '${URL}'"
  fi
}

OUT=""
for attempt in 1 2 3; do
  OUT=$(call_api 2>/dev/null)
  # отделённый rssh-предупреждение от полезной нагрузки
  OUT=$(printf '%s\n' "$OUT" | grep -v '^Warning: Permanently added')
  if printf '%s' "$OUT" | python3 -c "import json,sys; json.loads(sys.stdin.read())" 2>/dev/null; then
    printf '%s\n' "$OUT"
    exit 0
  fi
  echo "[xui-api] попытка $attempt: пустой/битый ответ от панели" >&2
  sleep 2
done

echo "[xui-api] ОШИБКА: панель не ответила корректным JSON на ${METHOD} ${APIPATH}" >&2
echo "[xui-api] проверьте: ./rssh.sh 'systemctl is-active x-ui; curl -s -o /dev/null -w \"%{http_code}\" http://127.0.0.1:${PORT}/${BASE}/'" >&2
printf '%s\n' "$OUT" >&2
exit 1
