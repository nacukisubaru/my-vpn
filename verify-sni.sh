#!/bin/bash
# Проверка одного домена как SNI реальным тестом туннеля.
#   ./verify-sni.sh <domain>
# Возвращает: "OK <cn>" или "FAIL <причина>".
# Метод: проверяем TLS 1.3+h2 и совпадение сертификата, затем ВРЕМЕННО ставим SNI
# на основной вход, гоняем запросы через контейнер и возвращаем исходный SNI.
set -uo pipefail
cd "$(dirname "$0")"
D="${1:?usage: ./verify-sni.sh <domain>}"

# ---------- 1. TLS-уровень с сервера ----------
# -tls1_3 форсирует TLS 1.3: если хендшейк прошёл и есть сертификат — 1.3 поддерживается
TLS=$(./rssh.sh "echo | timeout 20 openssl s_client -connect ${D}:443 -servername ${D} -tls1_3 -alpn h2 2>/dev/null | grep -E 'subject=|ALPN protocol: h2'" 2>/dev/null)
case "$TLS" in
  *"subject="*) : ;;
  *) echo "FAIL нет TLS 1.3 (хендшейк не прошёл)"; exit 0 ;;
esac
case "$TLS" in
  *"ALPN protocol: h2"*) : ;;
  *) echo "FAIL нет HTTP/2"; exit 0 ;;
esac

SUBJ=$(echo "$TLS" | grep -m1 "subject=" | sed 's/.*CN *= *//' | sed 's/,.*//' | tr -d ' ')
CNOK=$(python3 - "$D" "$SUBJ" <<'PY'
import sys
host, cn = sys.argv[1], sys.argv[2]
if cn.startswith("*."):
    ok = host.endswith(cn[1:]) and host.count(".") == cn.count(".")
else:
    ok = host == cn
print("1" if ok else "0")
PY
)
[ "$CNOK" = "1" ] || { echo "FAIL сертификат не на ${D} (CN=${SUBJ})"; exit 0; }

# ---------- 2. реальный туннель ----------
./xui-api.sh GET /panel/api/inbounds/list 2>/dev/null > /tmp/vs-list.json
python3 - <<'PY'
import json
lst = json.load(open("/tmp/vs-list.json"))["obj"]
main = next(i for i in lst if i["id"] == 1)
json.dump(main, open("/tmp/vs-main.json", "w"), ensure_ascii=False)
PY
MAIN_ID=$(python3 -c "import json;print(json.load(open('/tmp/vs-main.json'))['id'])")
MAIN_PORT=$(python3 -c "import json;print(json.load(open('/tmp/vs-main.json'))['port'])")

restore() {
  [ -f /tmp/vs-main.json ] || return 0
  ./xui-api.sh POST "/panel/api/inbounds/update/$MAIN_ID" /tmp/vs-main.json >/dev/null 2>&1
  sleep 1
}
trap restore EXIT INT TERM

python3 - "$D" <<'PY'
import json, sys
sni = sys.argv[1]
d = json.load(open("/tmp/vs-main.json"))
rs = d["streamSettings"]["realitySettings"]
rs["dest"] = f"{sni}:443"; rs["serverNames"] = [sni]
json.dump(d, open("/tmp/vs-apply.json", "w"), ensure_ascii=False)
PY
./xui-api.sh POST "/panel/api/inbounds/update/$MAIN_ID" /tmp/vs-apply.json >/dev/null 2>&1
sleep 2

SRV=$(python3 -c "
import json;d=json.load(open('/tmp/vs-main.json'));r=d['streamSettings']['realitySettings']
print(r['settings']['publicKey'], r['shortIds'][0], r['settings'].get('fingerprint','chrome'))")
PUB=$(echo "$SRV" | cut -d' ' -f1); SID=$(echo "$SRV" | cut -d' ' -f2); FP=$(echo "$SRV" | cut -d' ' -f3)
UUID=$(python3 -c "
import json;d=json.load(open('/tmp/vs-main.json'));print(d['settings']['clients'][0]['id'])")

python3 - "$D" "$PUB" "$SID" "$FP" "$UUID" "$MAIN_PORT" <<'PY'
import json, sys
sni, pub, sid, fp, uuid, port = sys.argv[1:7]
c = json.load(open("client/config.json"))
v = c["outbounds"][0]["settings"]["vnext"][0]
v["port"] = int(port); v["users"][0]["id"] = uuid
r = c["outbounds"][0]["streamSettings"]["realitySettings"]
r.update(serverName=sni, publicKey=pub, shortId=sid, fingerprint=fp)
json.dump(c, open("/tmp/vs-config.json", "w"), indent=2)
PY

docker rm -f vsni >/dev/null 2>&1
docker run -d --name vsni -v "/tmp/vs-config.json:/cfg/c.json:ro" vpn-test-client -config /cfg/c.json >/dev/null 2>&1
for _ in $(seq 1 20); do docker exec vsni sh -c 'nc -z 127.0.0.1 1080' >/dev/null 2>&1 && break; sleep 0.5; done
sleep 1

ok=0
for i in 1 2 3; do
  c=$(docker exec vsni sh -c 'curl -s -o /dev/null -w "%{http_code}" --max-time 12 --socks5-hostname 127.0.0.1:1080 https://www.gstatic.com/generate_204' 2>/dev/null)
  [ "$c" = "204" ] && ok=$((ok+1))
done
ip=$(docker exec vsni sh -c 'curl -s --max-time 12 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org' 2>/dev/null)
docker rm -f vsni >/dev/null 2>&1

restore   # вернуть исходный SNI до удаления временных файлов
if [ "$ok" -ge 2 ] && [ "$ip" = "82.148.226.31" ]; then
  echo "OK ${SUBJ}"
else
  echo "FAIL туннель ${ok}/3, ip='${ip:-нет}'"
fi
rm -f /tmp/vs-*.json
