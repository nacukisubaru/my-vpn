#!/bin/bash
# Ротация основного входа VLESS+Reality (сброс «отпечатка» для DPI).
#
#   ./rotate.sh                        # случайный SNI + новые ключи, порт не меняется
#   ./rotate.sh --without-sni          # только ключи, SNI оставить прежним
#   ./rotate.sh --sni <домен>          # вручную задать SNI (+ новые ключи)
#   ./rotate.sh --change-port          # случайный свободный порт (+ SNI + ключи)
#   ./rotate.sh --port 2053            # вручную задать порт (+ SNI + ключи)
#   ./rotate.sh --no-keys              # не менять ключи
#   ./rotate.sh --list-sni | --list-ports
#   ./rotate.sh --verify-sni [домен]
#   ./rotate.sh --reset-used [sni|ports]
#   ./rotate.sh -h | --help
set -uo pipefail
cd "$(dirname "$0")"

SNI=""; WITHOUT_SNI=0; CHANGE_PORT=0; PORT=""; DO_KEYS=1
LIST_SNI=0; LIST_PORTS=0; VERIFY=""; RESET=""; HELP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --sni)          SNI="$2"; shift 2 ;;
    --without-sni)  WITHOUT_SNI=1; shift ;;
    --change-port)  CHANGE_PORT=1; shift ;;
    --port)         PORT="$2"; shift 2 ;;
    --no-keys)      DO_KEYS=0; shift ;;
    --list-sni)     LIST_SNI=1; shift ;;
    --list-ports)   LIST_PORTS=1; shift ;;
    --verify-sni)   shift; if [ $# -gt 0 ] && [ "${1:0:2}" != "--" ]; then VERIFY="$1"; shift; else VERIFY="ALL"; fi ;;
    --reset-used)   shift; if [ $# -gt 0 ] && [ "${1:0:2}" != "--" ]; then RESET="$1"; shift; else RESET="all"; fi ;;
    -h|--help)      HELP=1; shift ;;
    *) echo "неизвестный флаг: $1 (см. ./rotate.sh --help)" >&2; exit 1 ;;
  esac
done

if [ "$HELP" = 1 ]; then
  echo "Ротация SNI/порта/ключей VLESS+Reality"; echo
  sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# ============ сервисные команды ============
[ "$LIST_SNI" = 1 ]   && { python3 tools/state.py list sni;   exit 0; }
[ "$LIST_PORTS" = 1 ] && { python3 tools/state.py list ports; exit 0; }
[ -n "$RESET" ]       && { python3 tools/state.py reset "$RESET"; exit 0; }

if [ -n "$VERIFY" ]; then
  if [ "$VERIFY" = "ALL" ]; then
    HOSTS=()
    while IFS= read -r line; do HOSTS+=("$line"); done < <(
      grep -v '^[[:space:]]*#' data/sni.txt | sed 's/#.*//' | tr -d ' ' | grep -v '^$')
  else
    HOSTS=("$VERIFY")
  fi
  echo "== проверяю ${#HOSTS[@]} домен(ов) реальным тестом туннеля =="
  for h in "${HOSTS[@]}"; do
    printf "  %-26s " "$h"
    RES=$(./verify-sni.sh "$h" 2>/dev/null | tail -1)
    case "$RES" in
      OK*)  CN=$(echo "$RES" | sed 's/^OK *//'); python3 tools/state.py verified "$h" 1 "$CN"; echo "✅ $CN" ;;
      *)    python3 tools/state.py verified "$h" 0; echo "❌ ${RES#FAIL }" ;;
    esac
  done
  echo; echo "Готово. Список: ./rotate.sh --list-sni"
  exit 0
fi

die() { echo >&2; echo "❌ $*" >&2; echo "   Ротация НЕ выполнена — конфиг на сервере не изменён." >&2; exit 1; }

# ============ 0. связь с панелью ============
echo "== 0/8 связь с панелью =="
./xui-api.sh GET /panel/api/inbounds/list > /tmp/rot-list.json \
  || die "панель не отвечает. Проверьте: ./diag.sh"
python3 -c "import json;json.load(open('/tmp/rot-list.json'))" 2>/dev/null \
  || die "панель вернула не JSON"
echo "   панель отвечает"

read -r MAIN_ID OLD_PORT OLD_SNI < <(python3 - <<'PY'
import json
lst = json.load(open('/tmp/rot-list.json'))['obj']
main = next((i for i in lst if i['id'] == 1), None)
if main is None:
    print("ERR ERR ERR")
else:
    print(main['id'], main['port'], main['streamSettings']['realitySettings']['serverNames'][0])
PY
)
[ "$MAIN_ID" = "ERR" ] && die "в панели нет инбаунда с id=1"
[ -z "$MAIN_ID" ] || [ -z "$OLD_PORT" ] || [ -z "$OLD_SNI" ] && die "не удалось прочитать текущие параметры входа"
echo "   сейчас: id=$MAIN_ID порт=$OLD_PORT sni=$OLD_SNI"

# ============ 1. снапшот ============
echo "== 1/8 снапшот =="
STAMP=$(date +%Y-%m-%d_%H%M%S)
SNAP="docs/snapshots/${STAMP}-rotate"
mkdir -p "$SNAP"
cp /tmp/rot-list.json "$SNAP/inbounds.json"
python3 tools/snapshot.py "$SNAP" >/dev/null || die "не удалось разложить снапшот"
cp client/config.json "$SNAP/client-config.json" 2>/dev/null || true
cp client/vless-url.txt "$SNAP/" 2>/dev/null || true
cp secrets/vpn.json "$SNAP/vpn-keys.json" 2>/dev/null || true
mkdir -p "$SNAP/qr"; cp qr/*.png "$SNAP/qr/" 2>/dev/null || true
echo "   $SNAP"

# ============ 2. SNI ============
echo "== 2/8 выбираю SNI =="
if [ "$WITHOUT_SNI" = 1 ] && [ -z "$SNI" ]; then
  SNI="$OLD_SNI"; echo "   --without-sni → оставляю $SNI"
elif [ -n "$SNI" ]; then
  echo "   вручную → $SNI"
else
  SNI=$(python3 tools/state.py pick sni) || die "нет доступных SNI. Сначала: ./rotate.sh --verify-sni"
  [ -z "$SNI" ] && die "не удалось выбрать SNI"
  echo "   случайно → $SNI"
fi

# ============ 3. порт ============
echo "== 3/8 выбираю порт =="
if [ -n "$PORT" ]; then
  echo "   вручную → $PORT"
elif [ "$CHANGE_PORT" = 1 ]; then
  BUSY=$(python3 -c "
import json
l=json.load(open('/tmp/rot-list.json'))['obj']
print(','.join(str(i['port']) for i in l) + ',22,2096,38217')")
  PORT=$(python3 tools/state.py pick ports "$BUSY" 2>/dev/null)
  [ -z "$PORT" ] && PORT=443
  echo "   случайно → $PORT"
else
  PORT="$OLD_PORT"; echo "   без изменений → $PORT"
fi

# ============ 4. валидация SNI ============
echo "== 4/8 проверка SNI на сервере =="
if [ "$SNI" != "$OLD_SNI" ]; then
  CHK=$(./rssh.sh "echo | timeout 20 openssl s_client -connect ${SNI}:443 -servername ${SNI} -tls1_3 -alpn h2 2>/dev/null | grep -E 'subject=|ALPN protocol: h2'" 2>/dev/null)
  case "$CHK" in
    *"subject="*"ALPN protocol: h2"*) echo "   $SNI OK (TLS 1.3 + h2)" ;;
    *) die "домен $SNI не годится как SNI (нужен TLS 1.3 + HTTP/2). Выберите другой: ./rotate.sh --list-sni" ;;
  esac
else
  echo "   без изменений"
fi

# ============ 5. ключи ============
if [ "$DO_KEYS" = 1 ]; then
  echo "== 5/8 новые ключи Reality =="
  KEYS=$(./rssh.sh '/usr/local/x-ui/bin/xray-linux-amd64 x25519; openssl rand -hex 8; openssl rand -hex 4')
  PRIV=$(echo "$KEYS" | awk '/PrivateKey:/{print $2}')
  PUB=$(echo "$KEYS"  | awk '/PublicKey/{print $NF}')
  SID1=$(echo "$KEYS" | sed -n '4p' | tr -d "[:space:]")
  SID2=$(echo "$KEYS" | sed -n '5p' | tr -d "[:space:]")
  case "$PRIV" in *[!A-Za-z0-9_-]*|"") die "не удалось сгенерировать приватный ключ";; esac
  case "$PUB"  in *[!A-Za-z0-9_-]*|"") die "не удалось сгенерировать публичный ключ";; esac
  echo "   pbk=${PUB:0:16}… sid=$SID1"
else
  echo "== 5/8 ключи не меняю (--no-keys) =="
  PRIV=""; PUB=""; SID1=""; SID2=""
fi

# ============ 6. применяем ============
echo "== 6/8 применяю на сервере =="
python3 - "$MAIN_ID" "$PORT" "$SNI" "$PRIV" "$PUB" "$SID1" "$SID2" <<'PY' || die "не удалось собрать payload"
import json, sys
mid, port, sni, priv, pub, sid1, sid2 = sys.argv[1:8]
lst = json.load(open("/tmp/rot-list.json"))["obj"]
tgt = next(i for i in lst if i["id"] == int(mid))
tgt["port"] = int(port)
rs = tgt["streamSettings"]["realitySettings"]
rs["dest"] = f"{sni}:443"; rs["serverNames"] = [sni]
if priv:
    rs["privateKey"] = priv
    rs["shortIds"] = [sid1, sid2]
    rs["settings"]["publicKey"] = pub
keep = ("up","down","total","remark","enable","expiryTime","listen","port","protocol",
        "settings","streamSettings","sniffing","shareAddrStrategy","shareAddr",
        "subSortIndex","excludeFromSub","trafficReset","trafficResetDay")
json.dump({k: tgt[k] for k in keep if k in tgt}, open("/tmp/rot-upd.json","w"),
          ensure_ascii=False, indent=2)
print(f"   inbound {mid}: порт {port}, dest {rs['dest']}")
PY

./xui-api.sh POST "/panel/api/inbounds/update/$MAIN_ID" /tmp/rot-upd.json > /tmp/rot-apply.json \
  || die "панель не приняла изменения"
grep -q '"success":true' /tmp/rot-apply.json \
  || die "панель вернула отказ: $(cat /tmp/rot-apply.json)"
echo "   изменения приняты панелью"

./rssh.sh "ufw allow $PORT/tcp >/dev/null 2>&1; true" >/dev/null 2>&1
if [ "$PORT" != "$OLD_PORT" ] && [ "$OLD_PORT" != "443" ]; then
  ./rssh.sh "ufw delete allow $OLD_PORT/tcp >/dev/null 2>&1; true" >/dev/null 2>&1
  echo "   ufw: +$PORT, -$OLD_PORT"
else
  echo "   ufw: +$PORT"
fi

# --- 6b. гарантия, что порт реально слушается ---
# При СМЕНЕ ПОРТА 3x-ui может снять старый слушатель и не поднять новый
# (горячее применение через API). Проверяем и при необходимости перезапускаем.
echo "   проверяю, что порт $PORT слушается…"
LISTEN_OK=0
for attempt in 1 2 3; do
  if ./rssh.sh "ss -tulpn 2>/dev/null | grep -qE ':${PORT} '" >/dev/null 2>&1; then LISTEN_OK=1; break; fi
  echo "   порт не слушается → перезапуск x-ui (попытка $attempt)"
  ./rssh.sh 'systemctl restart x-ui' >/dev/null 2>&1
  sleep 8
done
if [ "$LISTEN_OK" != "1" ]; then
  ./rssh.sh 'journalctl -u x-ui --since "-3min" --no-pager | tail -20' >&2
  die "xray не поднял порт $PORT (конфиг применён, но вход не работает)"
fi
echo "   порт $PORT слушается ✅"

# ============ 7. синхронизация ============
echo "== 7/8 синхронизация клиентов =="
./sync-client.sh 2>&1 | grep -E "wrote|removed|removed" | sed 's/^/   /'

# ============ 8. проверка туннеля ============
echo "== 8/8 проверка туннеля =="
TUNNEL_OK="не проверено (docker не запущен)"
TUNNEL_RC=0
if docker info >/dev/null 2>&1; then
  docker rm -f rotcheck >/dev/null 2>&1
  docker run -d --name rotcheck -v "$PWD/client:/cfg:ro" vpn-test-client \
    -config /cfg/config.json >/dev/null 2>&1
  for _ in $(seq 1 24); do
    docker exec rotcheck sh -c 'nc -z 127.0.0.1 1080' >/dev/null 2>&1 && break
    sleep 0.5
  done
  TIP=$(docker exec rotcheck sh -c 'curl -s --max-time 20 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org' 2>/dev/null)
  docker rm -f rotcheck >/dev/null 2>&1
  if [ "$TIP" = "82.148.226.31" ]; then
    TUNNEL_OK="работает ✅"
  else
    TUNNEL_OK="НЕ РАБОТАЕТ ❌ (ответ '${TIP:-нет}')"
    TUNNEL_RC=2
  fi
fi
echo "   $TUNNEL_OK"

# ============ отметки состояния ============
[ "$SNI"  != "$OLD_SNI"  ] && python3 tools/state.py mark sni "$SNI"
[ "$PORT" != "$OLD_PORT" ] && python3 tools/state.py mark ports "$PORT"

rm -f /tmp/rot-list.json /tmp/rot-upd.json /tmp/rot-apply.json

# ============ итог ============
MAIN_PORT=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['port'])")
URL=$(cat client/vless-url.txt)
QR="qr/main-${MAIN_PORT}.png"
PBK=$(python3 -c "import re;u=open('client/vless-url.txt').read();print(re.search(r'pbk=([^&]+)',u).group(1))")
SIDN=$(python3 -c "import re;u=open('client/vless-url.txt').read();print(re.search(r'sid=([^&]+)',u).group(1))")
SUB=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['subscription_url'])")

echo
echo "════════════════════════════════════════════════════════════════════"
echo " РОТАЦИЯ ЗАВЕРШЕНА   $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════════"
printf " SNI          : %s\n" "$SNI"
printf " Порт         : %s  (было %s)\n" "$MAIN_PORT" "$OLD_PORT"
printf " publicKey    : %s\n" "$PBK"
printf " shortId      : %s\n" "$SIDN"
printf " Ключи        : %s\n" "$([ "$DO_KEYS" = 1 ] && echo 'обновлены (новые)' || echo 'без изменений')"
printf " Туннель      : %s\n" "$TUNNEL_OK"
printf " Снапшот      : %s\n" "$SNAP"
echo "────────────────────────────────────────────────────────────────────"
echo " URL ДЛЯ ПОДКЛЮЧЕНИЯ  →  client/vless-url.txt"
echo
echo " $URL"
echo
echo " QR-КОД               →  $QR"
echo " ПОДПИСКА (авто)      →  $SUB"
echo "════════════════════════════════════════════════════════════════════"
echo " Обновите профиль на устройствах (подписка обновится сама)."
echo " Откат: ./rollback.sh $(basename "$SNAP")"
echo "════════════════════════════════════════════════════════════════════"
exit "$TUNNEL_RC"
