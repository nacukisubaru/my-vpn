#!/bin/bash
# Шаг 3: генерация криптографии Reality и UUID клиентов.
# Всё генерируется НА СЕРВЕРЕ (xray x25519, openssl), в stdout попадают ключи.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

step "3/6 генерация ключей"

info "генерирую пару x25519 для основного входа"
OUT=$(srv '/usr/local/x-ui/bin/xray-linux-amd64 x25519') || die "не удалось сгенерировать x25519"
K1_PRIV=$(printf '%s\n' "$OUT" | awk '/PrivateKey:/{print $2}' | tr -d '\r')
K1_PUB=$(printf '%s\n' "$OUT" | awk '/PublicKey/{print $NF}' | tr -d '\r')
case "$K1_PRIV" in *[!A-Za-z0-9_-]*|"") die "приватный ключ #1 пустой/битый";; esac
case "$K1_PUB"  in *[!A-Za-z0-9_-]*|"") die "публичный ключ #1 пустой/битый";; esac
ok "основной: pbk=${K1_PUB:0:16}…"

info "генерирую пару x25519 для резервного входа"
OUT=$(srv '/usr/local/x-ui/bin/xray-linux-amd64 x25519') || die "не удалось сгенерировать x25519"
K2_PRIV=$(printf '%s\n' "$OUT" | awk '/PrivateKey:/{print $2}' | tr -d '\r')
K2_PUB=$(printf '%s\n' "$OUT" | awk '/PublicKey/{print $NF}' | tr -d '\r')
case "$K2_PRIV" in *[!A-Za-z0-9_-]*|"") die "приватный ключ #2 пустой/битый";; esac
case "$K2_PUB"  in *[!A-Za-z0-9_-]*|"") die "публичный ключ #2 пустой/битый";; esac
ok "резервный: pbk=${K2_PUB:0:16}…"

info "генерирую shortId (по два на вход)"
SIDS1=$(srv 'openssl rand -hex 8; openssl rand -hex 4' | tr -d '\r')
SIDS2=$(srv 'openssl rand -hex 8; openssl rand -hex 4' | tr -d '\r')
SID1A=$(printf '%s\n' "$SIDS1" | sed -n '1p'); SID1B=$(printf '%s\n' "$SIDS1" | sed -n '2p')
SID2A=$(printf '%s\n' "$SIDS2" | sed -n '1p'); SID2B=$(printf '%s\n' "$SIDS2" | sed -n '2p')
ok "shortId: $SID1A / $SID2A"

info "генерирую UUID клиентов (ПК, телефон, резерв)"
U_MAIN=$(srv '/usr/local/x-ui/bin/xray-linux-amd64 uuid' | tr -d '\r')
U_PHONE=$(srv '/usr/local/x-ui/bin/xray-linux-amd64 uuid' | tr -d '\r')
U_BACKUP=$(srv '/usr/local/x-ui/bin/xray-linux-amd64 uuid' | tr -d '\r')
for u in "$U_MAIN" "$U_PHONE" "$U_BACKUP"; do
  printf '%s' "$u" | grep -qiE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' \
    || die "сгенерирован некорректный UUID: $u"
done
ok "UUID: ПК ${U_MAIN:0:8}…, телефон ${U_PHONE:0:8}…, резерв ${U_BACKUP:0:8}…"

info "сохраняю в /tmp/prov-keys.env"
cat > /tmp/prov-keys.env <<EOF
K1_PRIV='$K1_PRIV'
K1_PUB='$K1_PUB'
K2_PRIV='$K2_PRIV'
K2_PUB='$K2_PUB'
SID1A='$SID1A'
SID1B='$SID1B'
SID2A='$SID2A'
SID2B='$SID2B'
U_MAIN='$U_MAIN'
U_PHONE='$U_PHONE'
U_BACKUP='$U_BACKUP'
EOF
chmod 600 /tmp/prov-keys.env
ok "ключи сохранены локально (временный файл)"
