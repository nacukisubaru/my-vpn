#!/bin/bash
# Шаг 5: сохранение локальных файлов — secrets, клиентские ссылки, QR.
# Повторяет структуру, которую используют остальные скрипты проекта.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
source /tmp/prov-keys.env
source /tmp/prov-ids.env

step "5/6 локальные файлы"

ROOT="${PROV_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT"

mkdir -p secrets client qr

info "записываю secrets/server.json"
cat > secrets/server.json <<EOF
{
  "host": "${S_HOST}",
  "server": "${S_HOST}",
  "user": "${S_USER}",
  "password": "${S_PASS}"
}
EOF
chmod 600 secrets/server.json
ok "secrets/server.json"

info "записываю secrets/panel.json"
cat > secrets/panel.json <<EOF
{
  "panel_port": ${P_PORT},
  "panel_user": "${P_USER}",
  "panel_pass": "${P_PASS}",
  "panel_path": "${P_PATH}",
  "api_token": "${P_TOKEN}",
  "listen_ip": "127.0.0.1"
}
EOF
chmod 600 secrets/panel.json
ok "secrets/panel.json"

# путь подписки берём из панели (он случайный)
info "читаю путь подписки из панели"
SUB_PATH=$(srv "sqlite3 /etc/x-ui/x-ui.db \"select value from settings where key='subPath'\"" 2>/dev/null | tr -d '\r') || true
[ -z "$SUB_PATH" ] && { warn "не удалось прочитать путь подписки, беру /sub/"; SUB_PATH="/sub/"; }
SUB_PATH="/$(printf '%s' "$SUB_PATH" | tr -d '/' )/"
ok "путь подписки: $SUB_PATH"

info "записываю secrets/vpn.json"
cat > secrets/vpn.json <<EOF
{
  "host": "${S_HOST}",
  "server": "${S_HOST}",
  "port": ${S_MAIN_PORT},
  "sni": "${S_SNI}",
  "dest": "${S_SNI}:443",
  "inbound_id": ${ID_MAIN},
  "private_key": "${K1_PRIV}",
  "public_key": "${K1_PUB}",
  "short_id": "${SID1A}",
  "short_ids": ["${SID1A}", "${SID1B}"],
  "uuid": "${U_MAIN}",
  "fingerprint": "${PROV_FP}",
  "flow": "${PROV_FLOW}",
  "subscription_path": "${SUB_PATH}",
  "sub_id": "mainsub01",
  "subscription_url": "http://${S_HOST}:2096${SUB_PATH}mainsub01",
  "clients": {
    "main": { "email": "main", "uuid": "${U_MAIN}", "sub_id": "mainsub01" },
    "phone": {
      "email": "phone", "uuid": "${U_PHONE}", "sub_id": "phonesub01",
      "subscription": "http://${S_HOST}:2096${SUB_PATH}phonesub01"
    }
  },
  "backup_inbound": {
    "remark": "${PROV_REMARK_BACKUP}",
    "port": ${S_BACKUP_PORT},
    "inbound_id": ${ID_BACKUP},
    "sni": "${S_SNI2}",
    "dest": "${S_SNI2}:443",
    "private_key": "${K2_PRIV}",
    "public_key": "${K2_PUB}",
    "short_id": "${SID2A}",
    "short_ids": ["${SID2A}", "${SID2B}"],
    "uuid": "${U_BACKUP}",
    "email": "backup"
  }
}
EOF
chmod 600 secrets/vpn.json
ok "secrets/vpn.json"

# ---------- клиентские ссылки ----------
info "генерирую vless-ссылки"
python3 - <<PY
import json, os
v = json.load(open("secrets/vpn.json"))
b = v["backup_inbound"]
host = v["host"]

def link(uuid_value, port, pbk, sid, sni, name):
    return (f"vless://{uuid_value}@{host}:{port}"
            f"?type=tcp&security=reality&encryption=none"
            f"&pbk={pbk}&sid={sid}&sni={sni}&fp={v['fingerprint']}"
            f"&flow={v['flow']}#{name}")

os.makedirs("client", exist_ok=True)
files = {
    "client/vless-url.txt":
        link(v["uuid"], v["port"], v["public_key"], v["short_ids"][0], v["sni"], "vpn-main"),
    "client/vless-minimal.txt":
        link(v["uuid"], v["port"], v["public_key"], v["short_ids"][0], v["sni"], "vpn-minimal"),
    "client/vless-backup.txt":
        link(b["uuid"], b["port"], b["public_key"], b["short_ids"][0], b["sni"], "vpn-backup"),
    "client/vless-phone-main.txt":
        link(v["clients"]["phone"]["uuid"], v["port"], v["public_key"], v["short_ids"][0], v["sni"], "vpn-phone"),
    "client/vless-phone-backup.txt":
        link(v["clients"]["phone"]["uuid"], b["port"], b["public_key"], b["short_ids"][0], b["sni"], "vpn-phone-backup"),
}
for path, value in files.items():
    open(path, "w").write(value + "\n")
    print(f"  {path}")
PY
ok "ссылки созданы"

# ---------- QR ----------
info "генерирую QR-коды"
if command -v qrencode >/dev/null 2>&1; then
  for pair in "client/vless-url.txt qr/main.png" \
              "client/vless-backup.txt qr/backup.png" \
              "client/vless-phone-main.txt qr/phone-main.png" \
              "client/vless-phone-backup.txt qr/phone-backup.png"; do
    set -- $pair
    qrencode -o "$2" -s 8 -m 2 "$(cat "$1")" && echo "  $2"
  done
  ok "QR-коды созданы"
else
  warn "qrencode не установлен — QR пропущены (brew install qrencode)"
fi

# ---------- secrets/CREDENTIALS.md ----------
info "пишу сводку доступов"
cat > secrets/CREDENTIALS.md <<EOF
# Доступы (не публиковать — папка в .gitignore)

## Сервер (SSH)
- host: \`${S_HOST}\`
- user: \`${S_USER}\`
- pass: \`${S_PASS}\`

## Панель 3x-ui
- URL после \`./panel-tunnel.sh\`: http://localhost:${P_PORT}/${P_PATH}/
- логин:  \`${P_USER}\`
- пароль: \`${P_PASS}\`
- API-токен: \`${P_TOKEN}\`

## VPN
| | основной | резервный |
|---|---|---|
| порт | ${S_MAIN_PORT} | ${S_BACKUP_PORT} |
| SNI | \`${S_SNI}\` | \`${S_SNI2}\` |
| publicKey | \`${K1_PUB}\` | \`${K2_PUB}\` |
| shortId | \`${SID1A}\` | \`${SID2A}\` |

- UUID ПК:     \`${U_MAIN}\`
- UUID тел.:   \`${U_PHONE}\`
- UUID резерв: \`${U_BACKUP}\`

- подписка ПК:     ${S_HOST}:2096 → \`http://${S_HOST}:2096${SUB_PATH}mainsub01\`
- подписка телефон: \`http://${S_HOST}:2096${SUB_PATH}phonesub01\`
EOF
chmod 600 secrets/CREDENTIALS.md
ok "secrets/CREDENTIALS.md"

# ---------- базовый клиентский конфиг для тестов ----------
info "собираю client/config-base.json (шаблон для тестов)"
python3 - <<'PY'
import json
v = json.load(open("secrets/vpn.json"))
cfg = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        {"tag": "socks-in", "listen": "127.0.0.1", "port": 1080, "protocol": "socks",
         "settings": {"auth": "noauth", "udp": True, "ip": "127.0.0.1"},
         "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}},
        {"tag": "http-in", "listen": "127.0.0.1", "port": 1081, "protocol": "http",
         "settings": {}},
    ],
    "outbounds": [
        {"tag": "proxy", "protocol": "vless",
         "settings": {"vnext": [{"address": v["host"], "port": v["port"],
            "users": [{"id": v["uuid"], "encryption": "none", "flow": v["flow"]}]}]},
         "streamSettings": {"network": "tcp", "security": "reality",
            "realitySettings": {"serverName": v["sni"], "fingerprint": v["fingerprint"],
                "publicKey": v["public_key"], "shortId": v["short_ids"][0], "spiderX": "/"}}},
        {"tag": "direct", "protocol": "freedom", "settings": {}},
    ],
    "routing": {"domainStrategy": "AsIs",
        "rules": [{"type": "field", "network": "tcp,udp", "outboundTag": "proxy"}]},
}
json.dump(cfg, open("client/config-base.json", "w"), indent=2, ensure_ascii=False)
print("  client/config-base.json")
PY
ok "шаблон создан"
