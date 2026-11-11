#!/usr/bin/env python3
"""Генерирует client/config-hardened.json из client/vless-url.txt + списки правил.

Запускается автоматически из sync-client.sh, поэтому после каждой ротации
«закалённый» конфиг остаётся актуальным.

Использование: python3 tools/build-client.py
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL_FILE = os.path.join(ROOT, "client", "vless-url.txt")
OUT = os.path.join(ROOT, "client", "config-hardened.json")
PROXY = os.path.join(ROOT, "data", "rules-proxy.txt")
DIRECT = os.path.join(ROOT, "data", "rules-direct.txt")


def domains(path):
    if not os.path.exists(path):
        return []
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(line)
    return out


def main():
    url = open(URL_FILE, encoding="utf-8").read().strip()
    p = dict(x.split("=", 1) for x in url.split("?", 1)[1].split("#", 1)[0].split("&"))
    user, hostport = url[len("vless://"):].split("@", 1)
    host, port = hostport.split("/")[0].split("?")[0].rsplit(":", 1)

    proxy = domains(PROXY)
    direct = domains(DIRECT)
    px = [f"domain:{d}" for d in proxy]
    dx = [f"domain:{d}" for d in direct]

    cfg = {
        "log": {"loglevel": "warning"},
        "dns": {
            # DNS для проксируемых доменов — только через туннель (без утечки к провайдеру)
            "servers": [
                {"address": "https://1.1.1.1/dns-query", "domains": px},
                {"address": "1.1.1.1", "domains": px},
                "localhost",
            ],
            "queryStrategy": "UseIP",
        },
        "inbounds": [
            {"tag": "socks-in", "listen": "127.0.0.1", "port": 1080, "protocol": "socks",
             "settings": {"auth": "noauth", "udp": True, "ip": "127.0.0.1"},
             "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"],
                          "routeOnly": True}},
            {"tag": "http-in", "listen": "127.0.0.1", "port": 1081, "protocol": "http",
             "settings": {"allowTransparent": False},
             "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"],
                          "routeOnly": True}},
        ],
        "outbounds": [
            {"tag": "proxy", "protocol": "vless",
             "settings": {"vnext": [{"address": host, "port": int(port),
                "users": [{"id": user, "encryption": "none",
                           "flow": p.get("flow", "xtls-rprx-vision")}]}]},
             "streamSettings": {
                 "network": "tcp", "security": "reality",
                 "realitySettings": {
                     "serverName": p["sni"],
                     "fingerprint": p.get("fp", "chrome"),
                     "publicKey": p["pbk"],
                     "shortId": p["sid"],
                     "spiderX": p.get("spx", "/").replace("%2F", "/"),
                 }}},
            {"tag": "direct", "protocol": "freedom", "settings": {}},
            {"tag": "block", "protocol": "blackhole", "settings": {}},
        ],
        "routing": {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                # 1. локальная сеть — всегда напрямую
                {"type": "field",
                 "ip": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8",
                        "169.254.0.0/16", "::1/128", "fc00::/7", "fe80::/10"],
                 "outboundTag": "direct"},
                # 2. торренты — напрямую (в туннеле выглядят как аномалия)
                {"type": "field", "protocol": ["bittorrent"], "outboundTag": "direct"},
                # 3. QUIC (UDP/443) для проксируемых доменов — БЛОКИРУЕМ.
                #    Приложение само откатится на TCP, и в туннель не попадёт UDP-поток:
                #    UDP внутри VLESS/TCP не защищён Vision и является сильным признаком для DPI.
                {"type": "field", "network": "udp", "port": 443,
                 "domain": px, "outboundTag": "block"},
                # 4. российское/локальное — напрямую
                {"type": "field", "domain": dx, "outboundTag": "direct"},
                {"type": "field", "domain": ["geosite:category-ru", "geosite:private"],
                 "outboundTag": "direct"},
                {"type": "field", "ip": ["geoip:ru", "geoip:private"], "outboundTag": "direct"},
                # 5. DNS — через туннель
                {"type": "field", "port": 53, "outboundTag": "proxy"},
                # 6. явный список «через VPN»
                {"type": "field", "domain": px, "outboundTag": "proxy"},
                # 7. остальное — напрямую (не гоняем весь трафик через сервер)
                {"type": "field", "network": "tcp,udp", "outboundTag": "direct"},
            ],
        },
    }

    json.dump(cfg, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"wrote {os.path.relpath(OUT, ROOT)}  "
          f"(proxy: {len(proxy)} доменов, direct: {len(direct)}, {len(cfg['routing']['rules'])} правил)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
