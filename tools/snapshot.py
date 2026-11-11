#!/usr/bin/env python3
"""Раскладывает снапшот инбаундов на отдельные payload-файлы (для rollback.sh).

Использование: python3 tools/snapshot.py docs/snapshots/<имя>
На входе: <снапшот>/inbounds.json ; на выходе: <снапшот>/inbound-<id>.json
"""
import json, sys, os

KEEP = ("up","down","total","remark","enable","expiryTime","listen","port","protocol",
        "settings","streamSettings","sniffing","shareAddrStrategy","shareAddr",
        "subSortIndex","excludeFromSub","trafficReset","trafficResetDay")


def main(snap):
    src = os.path.join(snap, "inbounds.json")
    if not os.path.exists(src):
        print(f"нет {src}", file=sys.stderr)
        return 1
    for i in json.load(open(src))["obj"]:
        out = os.path.join(snap, f"inbound-{i['id']}.json")
        json.dump({k: i[k] for k in KEEP if k in i}, open(out, "w"),
                  ensure_ascii=False, indent=2)
        print(f"  {out}  (порт {i['port']})")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(1)
    raise SystemExit(main(sys.argv[1]))
