#!/bin/bash
# Провижининг VPN-сервера (VLESS + Reality на 3x-ui).
#
# Запуск через make (он спросит ip/логин/пароль и попросит подтверждение):
#     make install
#
# Переменные можно передать заранее и тогда вопросов не будет:
#     make install S_HOST=1.2.3.4 S_USER=root S_PASS=... CONFIRM=yes
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"

step "провижининг VPN-сервера"

# ---------- значения по умолчанию ----------
: "${S_USER:=root}"
: "${S_SSH_PORT:=22}"
: "${S_MAIN_PORT:=443}"
: "${S_BACKUP_PORT:=8443}"
: "${S_SNI:=www.apple.com}"
: "${S_SNI2:=www.python.org}"
: "${PROV_FP:=chrome}"
: "${PROV_FLOW:=xtls-rprx-vision}"
: "${PROV_REMARK_MAIN:=VLESS-Reality-main}"
: "${PROV_REMARK_BACKUP:=VLESS-Reality-backup}"
: "${PROV_ON_EXISTS:=abort}"

# ---------- интерактивный ввод ----------
ask() {  # ask <переменная> <вопрос> <значение-по-умолчанию>
  local var="$1" prompt="$2" def="${3:-}" cur answer
  cur="${!var:-}"
  if [ -n "$cur" ]; then return 0; fi          # уже задано снаружи
  if [ -n "$def" ]; then
    read -r -p "$prompt [$def]: " answer
    answer="${answer:-$def}"
  else
    while [ -z "${answer:-}" ]; do read -r -p "$prompt: " answer; done
  fi
  printf -v "$var" '%s' "$answer"
}

echo
echo "Нужны доступы к серверу. Пароль используется только для SSH"
echo "и сохраняется локально в secrets/server.json (chmod 600)."
echo

ask S_HOST      "IP или домен сервера"
ask S_USER      "Пользователь SSH" "$S_USER"
ask S_PASS      "Пароль SSH"

if [ -z "${S_PASS:-}" ]; then
  printf "Пароль SSH: "
  read -r -s S_PASS
  echo
fi

# SSH-порт: по умолчанию 22, спрашиваем только если задан неверно
ask S_SSH_PORT  "SSH-порт" "$S_SSH_PORT"

echo
echo "Параметры VPN (Enter — оставить по умолчанию):"
ask S_MAIN_PORT   "  порт основного входа" "$S_MAIN_PORT"
ask S_BACKUP_PORT "  порт резервного входа" "$S_BACKUP_PORT"
ask S_SNI         "  домен-маскировка основного" "$S_SNI"
ask S_SNI2        "  домен-маскировка резервного" "$S_SNI2"

# ---------- проверка обязательного ----------
[ -z "${S_HOST:-}" ] && die "не задан адрес сервера"
[ -z "${S_PASS:-}" ] && die "не задан пароль SSH"

# ---------- подтверждение ----------
step "план действий"
cat <<EOF
  сервер        : $S_USER@$S_HOST (SSH порт $S_SSH_PORT)
  основной вход : VLESS+Reality, порт $S_MAIN_PORT, SNI $S_SNI
  резервный вход: VLESS+Reality, порт $S_BACKUP_PORT, SNI $S_SNI2
  панель        : 3x-ui (последняя), слушает только 127.0.0.1
  firewall      : ufw — SSH, $S_MAIN_PORT, $S_BACKUP_PORT, 2096
  ускорение     : BBR
  файлы         : secrets/, client/, qr/ в этом проекте

  Будет установлено на сервере:
    • пакеты curl, socat, cron, ufw, sqlite3
    • 3x-ui + Xray-core
    • два инбаунда VLESS+Reality (основной и резервный)

  НЕ будет сделано (по умолчанию):
    • смена SSH-порта и пароля root
    • отключение входа по паролю (SSH-ключи)
EOF

if srv 'test -d /usr/local/x-ui' 2>/dev/null; then
  warn "на сервере УЖЕ установлен 3x-ui"
  case "$PROV_ON_EXISTS" in
    abort)  die "остановлено: PROV_ON_EXISTS=abort (ничего не меняю)" ;;
    force)  warn "PROV_ON_EXISTS=force — панель будет переустановлена, данные потеряны" ;;
  esac
fi

if [ "${CONFIRM:-}" != "yes" ]; then
  echo
  read -r -p "Продолжить? Введите yes для запуска: " ANSWER
  [ "$ANSWER" = "yes" ] || die "отменено пользователем"
fi

# ---------- запуск шагов ----------
export S_HOST S_USER S_PASS S_SSH_PORT S_MAIN_PORT S_BACKUP_PORT
export S_SNI S_SNI2 PROV_FP PROV_FLOW PROV_REMARK_MAIN PROV_REMARK_BACKUP PROV_ON_EXISTS

# генерация секретов панели
P_PORT=$(python3 -c 'import random;print(random.randint(20000,60000))')
P_USER="adm$(rand_alnum 8)"
P_PASS="$(rand_alnum 24)"
P_PATH="$(rand_alnum 18)"
export P_PORT P_USER P_PASS P_PATH

START_TS=$(date +%s)

for stepfile in "$HERE"/steps/0*.sh; do
  bash "$stepfile" || die "шаг $(basename "$stepfile") завершился с ошибкой"
  # подхватываем переменные, которые шаги сохранили
  [ -f /tmp/prov-token.txt ] && P_TOKEN=$(cat /tmp/prov-token.txt) && export P_TOKEN
  [ -f /tmp/prov-keys.env ] && source /tmp/prov-keys.env && export K1_PRIV K1_PUB K2_PRIV K2_PUB \
    SID1A SID1B SID2A SID2B U_MAIN U_PHONE U_BACKUP
  [ -f /tmp/prov-ids.env ] && source /tmp/prov-ids.env && export ID_MAIN ID_BACKUP
done

DUR=$(( $(date +%s) - START_TS ))

# ---------- итог ----------
URL=$(cat "$ROOT/client/vless-url.txt" 2>/dev/null || echo "(не создана)")
SUB=$(python3 -c "import json;print(json.load(open('$ROOT/secrets/vpn.json'))['subscription_url'])" 2>/dev/null || echo "-")

echo
echo "════════════════════════════════════════════════════════════════════"
echo " ГОТОВО за ${DUR}s"
echo "════════════════════════════════════════════════════════════════════"
printf " Основной вход : :%s  SNI %s\n" "$S_MAIN_PORT" "$S_SNI"
printf " Резервный вход: :%s  SNI %s\n" "$S_BACKUP_PORT" "$S_SNI2"
printf " Панель        : ./panel-tunnel.sh  →  http://localhost:%s/%s/\n" "$P_PORT" "$P_PATH"
printf " Логин/пароль  : secrets/CREDENTIALS.md\n"
echo "────────────────────────────────────────────────────────────────────"
echo " ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ (client/vless-url.txt):"
echo " $URL"
echo
echo " Подписка (авто-обновление): $SUB"
echo " QR-коды: qr/"
echo "════════════════════════════════════════════════════════════════════"
echo " Дальше:  ./diag.sh   — диагностика"
echo "          make help   — остальные команды"
echo "════════════════════════════════════════════════════════════════════"

rm -f /tmp/prov-keys.env /tmp/prov-ids.env /tmp/prov-token.txt /tmp/prov-main.json /tmp/prov-backup.json /tmp/prov-list.json
