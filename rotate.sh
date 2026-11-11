#!/bin/bash
# Ротация параметров основного входа VLESS+Reality (сброс «отпечатка» для DPI).
#
#   ./rotate.sh                        # новый СЛУЧАЙНЫЙ SNI + новые ключи, порт не меняется
#   ./rotate.sh --without-sni          # только ключи, SNI оставить прежним
#   ./rotate.sh --sni <домен>          # вручную задать SNI (+ новые ключи)
#   ./rotate.sh --change-port          # случайный свободный порт (+ случайный SNI + ключи)
#   ./rotate.sh --port 2053            # вручную задать порт (+ случайный SNI + ключи)
#   ./rotate.sh --no-keys              # не менять ключи (только SNI/порт)
#   ./rotate.sh --list-sni            # таблица SNI: проверен / когда использован / статус
#   ./rotate.sh --list-ports          # таблица портов
#   ./rotate.sh --verify-sni [домен]  # проверить домены реальным тестом (все или один)
#   ./rotate.sh --reset-used          # сбросить флаги «недавно использован»
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
  echo "Ротация SNI/порта/ключей VLESS+Reality"
  echo
  sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# ---------------- сервисные команды ----------------
[ "$LIST_SNI" = 1 ]   && { python3 tools/state.py list sni; exit 0; }
[ "$LIST_PORTS" = 1 ] && { python3 tools/state.py list ports; exit 0; }

if [ -n "$RESET" ]; then
  python3 tools/state.py reset "$RESET"
  exit 0
fi

if [ -n "$VERIFY" ]; then
  if [ "$VERIFY" = "ALL" ]; then
    HOSTS=()
    while IFS= read -r line; do HOSTS+=("$line"); done < <(grep -v '^[[:space:]]*#' data/sni.txt | sed 's/#.*//' | tr -d ' ' | grep -v '^$')
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
  echo
  echo "Готово. Список: ./rotate.sh --list-sni"
  exit 0
fi

# ---------------- 1. параметры ----------------
echo "== 1/7 снапшот =="
STAMP=$(date +%Y-%m-%d_%H%M%S)
SNAP="docs/snapshots/${STAMP}-rotate"
mkdir -p "$SNAP"
./xui-api.sh GET /panel/api/inbounds/list 2>/dev/null > "$SNAP/inbounds.json"
python3 tools/snapshot.py "$SNAP"
cp client/config.json "$SNAP/client-config.json" 2>/dev/null || true
cp client/vless-url.txt "$SNAP/" 2>/dev/null || true
cp secrets/vpn.json "$SNAP/vpn-keys.json" 2>/dev/null || true
mkdir -p "$SNAP/qr"; cp qr/*.png "$SNAP/qr/" 2>/dev/null || true
echo "   $SNAP  (время ротации в названии)"

./xui-api.sh GET /panel/api/inbounds/list 2>/dev/null > /tmp/rot-list.json
MAIN_ID=$(python3 -c "import json;l=json.load(open('/tmp/rot-list.json'))['obj'];print(next(i['id'] for i in l if i['id']==1))")
OLD_PORT=$(python3 -c "import json;l=json.load(open('/tmp/rot-list.json'))['obj'];print(next(i['port'] for i in l if i['id']==$MAIN_ID))")
OLD_SNI=$(python3 -c "import json;l=json.load(open('/tmp/rot-list.json'))['obj'];i=next(x for x in l if x['id']==$MAIN_ID);print(i['streamSettings']['realitySettings']['serverNames'][0])")

echo "== 2/7 выбираю SNI =="
if [ "$WITHOUT_SNI" = 1 ] && [ -z "$SNI" ]; then
  SNI="$OLD_SNI"; echo "   --without-sni → оставляю $SNI"
elif [ -n "$SNI" ]; then
  echo "   вручную → $SNI"
else
  SNI=$(python3 tools/state.py pick sni)
  RC=$?
  [ $RC -ne 0 ] && { echo "   нет рабочих SNI — сначала ./rotate.sh --verify-sni" >&2; exit 1; }
  echo "   случайно → $SNI"
fi

echo "== 3/7 выбираю порт =="
if [ -n "$PORT" ]; then
  echo "   вручную → $PORT"
elif [ "$CHANGE_PORT" = 1 ]; then
  BUSY=$(python3 -c "
import json
l=json.load(open('/tmp/rot-list.json'))['obj']
print(','.join(str(i['port']) for i in l) + ',22,2096,38217')")
  PORT=$(python3 tools/state.py pick ports "$BUSY")
  RC=$?
  [ $RC -ne 0 ] && PORT=443
  echo "   случайно → $PORT"
else
  PORT="$OLD_PORT"; echo "   без изменений → $PORT"
fi

# ---------------- 2. валидация SNI ----------------
echo "== 4/7 проверка SNI на сервере =="
if [ "$SNI" != "$OLD_SNI" ]; then
  CHK=$(./rssh.sh "echo | timeout 20 openssl s_client -connect ${SNI}:443 -servername ${SNI} -tls1_3 -alpn h2 2>/dev/null | grep -E 'subject=|ALPN protocol: h2'" 2>/dev/null)
  case "$CHK" in
    *"subject="*"ALPN protocol: h2"*) echo "   $SNI OK (TLS 1.3 + h2)" ;;
    *) echo "   $SNI не подходит (нужен TLS 1.3 + h2)" >&2; exit 1 ;;
  esac
else
  echo "   без изменений"
fi

# ---------------- 3. ключи ----------------
if [ "$DO_KEYS" = 1 ]; then
  echo "== 5/7 новые ключи Reality =="
  KEYS=$(./rssh.sh '/usr/local/x-ui/bin/xray-linux-amd64 x25519; openssl rand -hex 8; openssl rand -hex 4')
  PRIV=$(echo "$KEYS" | awk '/PrivateKey:/{print $2}')
  PUB=$(echo "$KEYS" | awk '/PublicKey/{print $NF}')
  SID1=$(echo "$KEYS" | sed -n '4p' | tr -d "[:space:]")
  SID2=$(echo "$KEYS" | sed -n '5p' | tr -d "[:space:]")
  case "$PRIV" in *[!A-Za-z0-9_-]*|"") echo "ошибка генерации приватного ключа" >&2; exit 1;; esac
  case "$PUB"  in *[!A-Za-z0-9_-]*|"") echo "ошибка генерации публичного ключа" >&2; exit 1;; esac
  echo "   pbk=${PUB:0:16}… sid=$SID1"
else
  echo "== 5/7 ключи не меняю (--no-keys) =="
  PRIV=""; PUB=""; SID1=""; SID2=""
fi

# ---------------- 4. применяем ----------------
echo "== 6/7 применяю на сервере =="
python3 - "$MAIN_ID" "$PORT" "$SNI" "$PRIV" "$PUB" "$SID1" "$SID2" <<'PY'
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
json.dump({k: tgt[k] for k in keep if k in tgt}, open("/tmp/rot-upd.json","w"), ensure_ascii=False, indent=2)
print(f"   inbound {mid}: порт {port}, dest {rs['dest']}")
PY
./xui-api.sh POST "/panel/api/inbounds/update/$MAIN_ID" /tmp/rot-upd.json | head -c 100; echo

# фаервол
./rssh.sh "ufw allow $PORT/tcp >/dev/null 2>&1; true" >/dev/null 2>&1
if [ "$PORT" != "$OLD_PORT" ] && [ "$OLD_PORT" != "443" ]; then
  ./rssh.sh "ufw delete allow $OLD_PORT/tcp >/dev/null 2>&1; true" >/dev/null 2>&1
  echo "   ufw: +$PORT, -$OLD_PORT"
else
  echo "   ufw: +$PORT"
fi

# отметки в состоянии (SNI — только если реально сменили)
if [ "$SNI" != "$OLD_SNI" ]; then
  python3 tools/state.py mark sni "$SNI"
fi
if [ "$PORT" != "$OLD_PORT" ]; then
  python3 tools/state.py mark ports "$PORT"
fi

echo "== 7/7 синхронизация клиентов =="
./sync-client.sh 2>&1 | grep -E "wrote|removed" | sed 's/^/   /'

rm -f /tmp/rot-list.json /tmp/rot-upd.json

# ---------------- 5. итог ----------------
MAIN_PORT=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['port'])")
URL=$(cat client/vless-url.txt)
QR="qr/main-${MAIN_PORT}.png"

# значения берём ИЗ САМОЙ ССЫЛКИ, чтобы итог совпадал с тем, что реально в файле
PBK=$(python3 -c "import re,sys;u=open('client/vless-url.txt').read();print(re.search(r'pbk=([^&]+)',u).group(1))")
SIDN=$(python3 -c "import re;u=open('client/vless-url.txt').read();print(re.search(r'sid=([^&]+)',u).group(1))")
SUB=$(python3 -c "import json;print(json.load(open('secrets/vpn.json'))['subscription_url'])")

echo
echo "════════════════════════════════════════════════════════════════════"
echo " РОТАЦИЯ ЗАВЕРШЕНА   $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════════"
printf " SNI          : %s\n" "$SNI"
printf " Порт         : %s\n" "$MAIN_PORT"
printf " publicKey    : %s\n" "$PBK"
printf " shortId      : %s\n" "$SIDN"
printf " Ключи        : %s\n" "$([ "$DO_KEYS" = 1 ] && echo 'обновлены (новые)' || echo 'без изменений')"
printf " Снапшот      : %s\n" "$SNAP"
echo "────────────────────────────────────────────────────────────────────"
echo " URL ДЛЯ ПОДКЛЮЧЕНИЯ  →  client/vless-url.txt"
echo
echo " $URL"
echo
echo " QR-КОД               →  $QR"
echo " ПОДПИСКА (авто)      →  $SUB"
echo "════════════════════════════════════════════════════════════════════"
echo " ВАЖНО: переимпортируйте профиль на устройствах (ключи/SNI изменились)."
echo " Откат: ./rollback.sh $(basename "$SNAP")"
echo "════════════════════════════════════════════════════════════════════"
