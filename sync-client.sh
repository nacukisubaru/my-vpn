#!/bin/bash
# Синхронизирует всё локальное с состоянием панели 3x-ui (источник истины):
#   client/vless-url.txt            — ссылка ПК (текущий порт)
#   client/vless-phone-<порт>.txt   — ссылки телефона
#   client/vless-backup-<порт>.txt  — резервный вход
#   client/config*.json             — конфиги Xray для тестов
#   qr/main-<порт>.png              — QR основной ссылки
#   qr/phone-<порт>.png             — QR профилей телефона
#   secrets/vpn.json                — ключи/параметры
#   qr/                             — старые PNG удаляются
set -euo pipefail
cd "$(dirname "$0")"

./xui-api.sh GET /panel/api/inbounds/list 2>/dev/null > /tmp/sc-inbounds.json
for e in main phone backup; do
  ./xui-api.sh GET /panel/api/clients/links/$e 2>/dev/null > "/tmp/sc-links-$e.json"
done

python3 - <<'PY'
import json, os, glob

def links(email):
    return json.load(open(f"/tmp/sc-links-{email}.json")).get("obj") or []

def port_of(link):
    hostport = link[len("vless://"):].split("@", 1)[1].split("?", 1)[0]
    return int(hostport.rsplit(":", 1)[1])

def params(link):
    q = link.split("?", 1)[1].split("#", 1)[0]
    return dict(p.split("=", 1) for p in q.split("&"))

data = {"main": links("main"), "phone": links("phone"), "backup": links("backup")}
inbounds = json.load(open("/tmp/sc-inbounds.json"))["obj"]
backup_ids = {i["id"] for i in inbounds if i["port"] != min(x["port"] for x in inbounds)}

# --- ссылки ---
files = {}
for name, lst in data.items():
    for link in lst:
        if name == "main":
            files["client/vless-url.txt"] = link
        else:
            files[f"client/vless-{name}-{port_of(link)}.txt"] = link

# удалить устаревшие файлы ссылок
for old in glob.glob("client/vless-*.txt"):
    if old not in files:
        os.remove(old); print("removed", old)
for path, link in files.items():
    open(path, "w").write(link + "\n")
    print("wrote", path)

# --- клиентские конфиги для тестов ---
base = json.load(open("client/config.json")) if os.path.exists("client/config-base.json") is False else json.load(open("client/config-base.json"))

def make(link):
    p = params(link)
    user, hostport = link[len("vless://"):].split("@", 1)
    host, port = hostport.split("/")[0].split("?")[0].rsplit(":", 1)
    c = json.loads(json.dumps(base))
    v = c["outbounds"][0]["settings"]["vnext"][0]
    v["address"] = host; v["port"] = int(port); v["users"][0]["id"] = user
    v["users"][0]["flow"] = p.get("flow", "")
    r = c["outbounds"][0]["streamSettings"]["realitySettings"]
    r["serverName"] = p["sni"]; r["publicKey"] = p["pbk"]; r["shortId"] = p["sid"]
    r["fingerprint"] = p.get("fp", "chrome"); r["spiderX"] = p.get("spx", "/").replace("%2F", "/")
    return c

main_link = files.get("client/vless-url.txt")
if main_link:
    json.dump(make(main_link), open("client/config.json", "w"), indent=2)
    print("wrote client/config.json")

for path, link in files.items():
    if "phone" in path:
        port = port_of(link)
        out = f"client/config-phone{port}.json"
        json.dump(make(link), open(out, "w"), indent=2)
        print("wrote", out)

# --- secrets/vpn.json ---
v = json.load(open("secrets/vpn.json"))
for i in inbounds:
    rs = i["streamSettings"]["realitySettings"]
    item = dict(port=i["port"], inbound_id=i["id"], dest=rs["dest"], sni=rs["serverNames"][0],
                private_key=rs["privateKey"], public_key=rs["settings"]["publicKey"],
                short_id=rs["shortIds"][0], short_ids=rs["shortIds"],
                emails=[c["email"] for c in i["settings"]["clients"]])
    if i["id"] == 1:
        v.update({k: item[k] for k in ("dest","sni","private_key","public_key","short_id","short_ids")})
        v["port"] = i["port"]
    else:
        v["backup_inbound"] = item
json.dump(v, open("secrets/vpn.json", "w"), indent=2)
print("wrote secrets/vpn.json")
PY

echo "== «закалённый» конфиг с маршрутизацией =="
python3 tools/build-client.py

echo "== QR =="
mkdir -p qr
rm -f qr/main-*.png qr/phone-*.png
python3 - <<'PY'
import glob, subprocess, os
targets = []
for f in glob.glob("client/vless-url.txt"):
    targets.append((f, None))
for f in glob.glob("client/vless-phone-*.txt"):
    targets.append((f, None))
for f, _ in targets:
    base = os.path.basename(f)
    if base == "vless-url.txt":
        port = __import__("re").search(r":(\d+)\?", open(f).read()).group(1)
        out = f"qr/main-{port}.png"
    else:
        port = __import__("re").search(r":(\d+)\?", open(f).read()).group(1)
        out = f"qr/phone-{port}.png"
    subprocess.run(["qrencode", "-o", out, "-s", "8", "-m", "2", open(f).read().strip()], check=True)
    print("wrote", out)
PY
rm -f /tmp/sc-*.json
