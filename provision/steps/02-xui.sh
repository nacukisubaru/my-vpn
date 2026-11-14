#!/bin/bash
# Шаг 2: установка панели 3x-ui (последняя версия) в неинтерактивном режиме.
# Если 3x-ui уже установлен — по умолчанию СТОП (см. PROV_ON_EXISTS).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

step "2/6 установка 3x-ui"

if srv 'test -d /usr/local/x-ui' 2>/dev/null; then
  case "${PROV_ON_EXISTS:-abort}" in
    abort)
      die "на сервере уже установлен 3x-ui (/usr/local/x-ui).
   Ничего не меняю. Варианты:
     • проверить существующую установку:  make doctor
     • разрешить переустановку:            make install PROV_ON_EXISTS=force
   ВНИМАНИЕ: force удалит базу панели (клиентов и инбаунды)." ;;
    force)
      warn "PROV_ON_EXISTS=force — переустанавливаю панель, данные будут потеряны"
      srv 'x-ui stop >/dev/null 2>&1 || true; systemctl disable x-ui >/dev/null 2>&1 || true
           rm -rf /usr/local/x-ui /etc/x-ui /etc/systemd/system/x-ui.service
           systemctl daemon-reload >/dev/null 2>&1 || true' >/dev/null 2>&1
      ok "прежняя установка удалена" ;;
    *) die "неизвестное значение PROV_ON_EXISTS=$PROV_ON_EXISTS" ;;
  esac
fi

info "скачиваю установщик 3x-ui"
srv 'curl -fsSL -o /root/install-3x-ui.sh https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh' \
  >/dev/null 2>&1 || die "не удалось скачать install.sh"
ok "установщик загружен"

info "устанавливаю панель (неинтерактивно)"
srv "XUI_NONINTERACTIVE=1 \
     XUI_PANEL_PORT=${P_PORT} \
     XUI_USERNAME=${P_USER} \
     XUI_PASSWORD=${P_PASS} \
     XUI_WEB_BASE_PATH=${P_PATH} \
     XUI_SSL_MODE=none \
     XUI_DB_TYPE=sqlite \
     XUI_SERVER_IP=${S_HOST} \
     bash /root/install-3x-ui.sh > /root/xui-install.log 2>&1" \
  || { srv 'tail -30 /root/xui-install.log'; die "установка 3x-ui не удалась"; }

VER=$(srv '/usr/local/x-ui/x-ui -v 2>/dev/null | head -1' | tr -d '\r')
ok "3x-ui установлен: ${VER:-версия неизвестна}"

info "проверяю, что сервис активен"
srv 'systemctl is-active x-ui' >/dev/null 2>&1 || die "сервис x-ui не запустился"
ok "x-ui активен"

info "привязываю панель к 127.0.0.1 (наружу не торчит)"
srv '/usr/local/x-ui/x-ui setting -listenIP 127.0.0.1 >/dev/null 2>&1
     systemctl restart x-ui' >/dev/null 2>&1
sleep 5
srv 'ss -tulpn | grep -q "127.0.0.1:${P_PORT}"' 2>/dev/null \
  || warn "панель не слушает 127.0.0.1:${P_PORT} — проверьте: make doctor"
ok "панель слушает 127.0.0.1:${P_PORT}"

info "выпускаю API-токен"
TOKEN=$(srv '/usr/local/x-ui/x-ui setting -getApiToken 2>&1 | grep -oE "^apiToken: .+" | awk "{print \$2}"' | tr -d '\r')
[ -z "$TOKEN" ] && die "не удалось получить API-токен"
printf '%s' "$TOKEN" > /tmp/prov-token.txt
ok "API-токен получен"

info "проверяю API панели"
P_TOKEN="$TOKEN"
api GET /panel/api/inbounds/list >/dev/null 2>&1 || die "API панели не отвечает"
ok "API панели работает"

info "разрешаю в firewall порт подписки 2096"
srv 'ufw allow 2096/tcp >/dev/null 2>&1 || true' >/dev/null 2>&1
ok "2096/tcp открыт"
