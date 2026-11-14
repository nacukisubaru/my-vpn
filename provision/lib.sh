#!/bin/bash
# Общие функции для провижининга. Подключается через `source`.
# Требует переменных окружения: S_HOST, S_USER, S_PASS (для SSH),
# после установки панели — P_PORT, P_PATH, P_TOKEN.
set -uo pipefail

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_RED=$'\033[31m'
C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'; C_DIM=$'\033[2m'

info() { printf "%s==>%s %s\n" "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf "%s  ✓%s %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%s  !%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
step() { printf "\n%s━━ %s %s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n" \
         "$C_BLUE" "$*" "$C_DIM" "$C_RESET"; }

die() {
  printf "\n%s✗ ОШИБКА:%s %s\n" "$C_RED" "$C_RESET" "$*" >&2
  exit 1
}

require_var() {
  local name="$1"
  [ -z "${!name:-}" ] && die "не задана переменная $name"
  return 0
}

# ---------- SSH ----------

# srv "<команда>" — выполнить на сервере (с ретраями)
srv() {
  local cmd="$1" i
  for i in 1 2 3 4; do
    if SSHPASS="$S_PASS" sshpass -e ssh \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
        -o ConnectTimeout=15 -o ServerAliveInterval=15 \
        -o NumberOfPasswordPrompts=1 \
        "$S_USER@$S_HOST" "$cmd" 2>/dev/null; then
      return 0
    fi
    [ "$i" -lt 4 ] && sleep 3
  done
  return 1
}

# srv_put <local> <remote>
srv_put() {
  SSHPASS="$S_PASS" sshpass -e ssh \
    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
    -o ConnectTimeout=15 -o NumberOfPasswordPrompts=1 \
    "$S_USER@$S_HOST" "cat > '$2'" < "$1" || die "не удалось загрузить $1 на сервер"
}

# srv_get <remote> > local
srv_get() { srv "base64 -w0 '$1' 2>/dev/null || base64 '$1'" | base64 -d; }

# ---------- API панели 3x-ui ----------

# api METHOD PATH [payload-file] — вернуть JSON
api() {
  local method="$1" path="$2" payload="${3:-}" url out i
  require_var P_PORT; require_var P_PATH; require_var P_TOKEN
  url="http://127.0.0.1:${P_PORT}/${P_PATH}${path}"

  for i in 1 2 3; do
    if [ -n "$payload" ]; then
      srv_put "$payload" /tmp/prov-payload.json || return 1
      out=$(srv "curl -s --max-time 30 -H 'Authorization: Bearer ${P_TOKEN}' \
        -H 'Content-Type: application/json' -X ${method} '${url}' -d @/tmp/prov-payload.json; \
        rm -f /tmp/prov-payload.json") || { sleep 2; continue; }
    else
      out=$(srv "curl -s --max-time 30 -H 'Authorization: Bearer ${P_TOKEN}' \
        -X ${method} '${url}'") || { sleep 2; continue; }
    fi
    if printf '%s' "$out" | python3 -c "import json,sys; json.loads(sys.stdin.read())" 2>/dev/null; then
      printf '%s\n' "$out"
      return 0
    fi
    sleep 2
  done
  warn "панель не вернула валидный JSON на ${method} ${path}"
  return 1
}

# api_ok METHOD PATH [payload] — то же, но проверяет "success":true
api_ok() {
  local out
  out=$(api "$@") || return 1
  if printf '%s' "$out" | grep -q '"success":true'; then
    printf '%s\n' "$out"
    return 0
  fi
  warn "панель вернула отказ: $(printf '%s' "$out" | head -c 300)"
  return 1
}

# ---------- утилиты ----------

rand_alnum() {
  python3 -c "import secrets,string;a=string.ascii_letters+string.digits;print(''.join(secrets.choice(a) for _ in range(int('$1'))))"
}

json_get() {
  python3 -c "import json,sys;d=json.load(sys.stdin);print($1)" 2>/dev/null
}
