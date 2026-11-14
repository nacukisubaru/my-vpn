#!/usr/bin/env python3
"""Собирает payload'ы инбаундов для API 3x-ui.

Использование:
    python3 build-inbounds.py main <out.json>
    python3 build-inbounds.py backup <out.json>

Читает параметры из окружения (см. provision/install.sh).
"""
import json
import os
import sys


def env(name, default=None):
    v = os.environ.get(name, default)
    if v is None:
        sys.exit(f"не задана переменная {name}")
    return v


def client(uid, email, flow, sub_id, comment):
    return {
        "id": uid,
        "flow": flow,
        "email": email,
        "limitIp": 0,
        "totalGB": 0,
        "expiryTime": 0,
        "enable": True,
        "tgId": "",
        "subId": sub_id,
        "comment": comment,
        "reset": 0,
    }


def inbound(port, remark, clients, sni, priv, pub, sids):
    settings = {"clients": clients, "decryption": "none", "fallbacks": []}
    stream = {
        "network": "tcp",
        "security": "reality",
        "externalProxy": [],
        "realitySettings": {
            "show": False,
            "xver": 0,
            "dest": f"{sni}:443",
            "serverNames": [sni],
            "privateKey": priv,
            "minClientVer": "",
            "maxClientVer": "",
            "maxTimediff": 0,
            "shortIds": sids,
            "settings": {
                "publicKey": pub,
                "fingerprint": env("PROV_FP", "chrome"),
                "serverName": "",
                "spiderX": "/",
            },
        },
        "sockopt": {"acceptProxyProtocol": False, "tcpFastOpen": False, "mark": 0},
    }
    sniffing = {
        "enabled": True,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": False,
        "routeOnly": True,
    }
    return {
        "up": 0,
        "down": 0,
        "total": 0,
        "remark": remark,
        "enable": True,
        "expiryTime": 0,
        "listen": "",
        "port": int(port),
        "protocol": "vless",
        "settings": json.dumps(settings, ensure_ascii=False),
        "streamSettings": json.dumps(stream, ensure_ascii=False),
        "sniffing": json.dumps(sniffing, ensure_ascii=False),
        "shareAddrStrategy": "custom",
        "shareAddr": env("S_HOST"),
    }


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    which, out = sys.argv[1], sys.argv[2]
    flow = env("PROV_FLOW", "xtls-rprx-vision")

    if which == "main":
        payload = inbound(
            env("S_MAIN_PORT", "443"),
            env("PROV_REMARK_MAIN", "VLESS-Reality-main"),
            [
                client(env("U_MAIN"), "main", flow, "mainsub01", "Основной (ПК)"),
                client(env("U_PHONE"), "phone", flow, "phonesub01", "Телефон"),
            ],
            env("S_SNI"),
            env("K1_PRIV"), env("K1_PUB"),
            [env("SID1A"), env("SID1B")],
        )
    elif which == "backup":
        payload = inbound(
            env("S_BACKUP_PORT", "8443"),
            env("PROV_REMARK_BACKUP", "VLESS-Reality-backup"),
            [
                client(env("U_BACKUP"), "backup", flow, "backupsub01", "Резервный вход"),
                client(env("U_PHONE"), "phone", flow, "phonesub01", "Телефон"),
            ],
            env("S_SNI2"),
            env("K2_PRIV"), env("K2_PUB"),
            [env("SID2A"), env("SID2B")],
        )
    else:
        sys.exit(f"неизвестный тип инбаунда: {which}")

    with open(out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    print(f"  payload: {out} (порт {payload['port']}, SNI {json.loads(payload['streamSettings'])['realitySettings']['serverNames'][0]})")


if __name__ == "__main__":
    main()
