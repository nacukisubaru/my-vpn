#!/usr/bin/env python3
"""Состояние ротации: какие SNI и порты использованы и когда.

Файлы:
  data/sni.txt              — список кандидатов (правится руками)
  data/ports.txt            — список портов-кандидатов (правится руками)
  data/rotation-state.json  — состояние (verified / last_used), создаётся автоматически
"""
import json, os, random, sys, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(ROOT, "data", "rotation-state.json")
SNI_TXT = os.path.join(ROOT, "data", "sni.txt")
PORTS_TXT = os.path.join(ROOT, "data", "ports.txt")
DEFAULT_COOLDOWN = 60


def now():
    return datetime.datetime.now().astimezone()


def iso(dt):
    return dt.isoformat(timespec="seconds")


def parse(ts):
    try:
        return datetime.datetime.fromisoformat(ts)
    except Exception:
        return None


def read_list(path):
    if not os.path.exists(path):
        return []
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(line)
    return out


def load():
    if os.path.exists(STATE):
        d = json.load(open(STATE, encoding="utf-8"))
    else:
        d = {}
    d.setdefault("cooldown_minutes", DEFAULT_COOLDOWN)
    d.setdefault("sni", {})
    d.setdefault("ports", {})
    return d


def save(d):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    json.dump(d, open(STATE, "w", encoding="utf-8"), ensure_ascii=False, indent=2)


def cooldown_left(entry, minutes):
    """Сколько минут осталось до конца карантина. 0 = свободен."""
    if not entry or not entry.get("last_used"):
        return 0
    lu = parse(entry["last_used"])
    if not lu:
        return 0
    end = lu + datetime.timedelta(minutes=minutes)
    left = (end - now()).total_seconds() / 60
    return max(0, round(left))


def cmd_list(what):
    d = load()
    cd = d["cooldown_minutes"]
    if what == "sni":
        items = read_list(SNI_TXT)
        state = d["sni"]
        title = "SNI"
    else:
        items = read_list(PORTS_TXT)
        state = d["ports"]
        title = "ПОРТ"
    print(f"{title:<26} {'проверен':<12} {'использован':<21} {'статус'}")
    print("-" * 78)
    free = 0
    for it in items:
        e = state.get(it, {})
        left = cooldown_left(e, cd)
        if e.get("ok") is False:
            status = "❌ не работает"
        elif left:
            status = f"🟡 карантин {left}м"
        elif e.get("verified"):
            status = "🟢 свободен"
            free += 1
        else:
            status = "⚪ не проверен"
            free += 1
        ver = (e.get("verified") or "—")[:10]
        used = (e.get("last_used") or "—")[:19]
        print(f"{it:<26} {ver:<12} {used:<21} {status}")
    print("-" * 78)
    print(f"свободно сейчас: {free} из {len(items)} · карантин: {cd} мин")
    return 0


def cmd_pick(what, exclude=""):
    d = load()
    cd = d["cooldown_minutes"]
    if what == "sni":
        items, state = read_list(SNI_TXT), d["sni"]
    else:
        items, state = read_list(PORTS_TXT), d["ports"]
    ex = {x.strip() for x in exclude.split(",") if x.strip()}

    usable = []
    for it in items:
        if it in ex:
            continue
        e = state.get(it, {})
        if e.get("ok") is False:          # проверенно нерабочие не берём
            continue
        if cooldown_left(e, cd):          # недавно использованные пропускаем
            continue
        usable.append(it)

    if not usable:
        # все в карантине — сбрасываем отметки времени и начинаем заново
        for it in items:
            if it in ex:
                continue
            e = state.setdefault(it, {})
            if e.get("ok") is False:
                continue
            e.pop("last_used", None)
        save(d)
        usable = [it for it in items if it not in ex and state.get(it, {}).get("ok") is not False]
        print("ALL-USED-RESET", file=sys.stderr)
        if not usable:
            print("нет доступных вариантов", file=sys.stderr)
            return 1

    print(random.choice(usable))
    return 0


def cmd_mark(what, value):
    d = load()
    key = "sni" if what == "sni" else "ports"
    e = d[key].setdefault(str(value), {})
    e["last_used"] = iso(now())
    save(d)
    return 0


def cmd_verified(host, ok, cn=""):
    d = load()
    e = d["sni"].setdefault(host, {})
    e["ok"] = (ok == "1")
    e["verified"] = iso(now())
    if cn:
        e["cn"] = cn
    save(d)
    return 0


def cmd_reset(what):
    d = load()
    if what in ("sni", "all"):
        for e in d["sni"].values():
            e.pop("last_used", None)
    if what in ("ports", "all"):
        for e in d["ports"].values():
            e.pop("last_used", None)
    save(d)
    print(f"флаги использования сброшены: {what}")
    return 0


def cmd_json():
    print(json.dumps(load(), ensure_ascii=False, indent=2))
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    c = argv[1]
    if c == "list":
        return cmd_list(argv[2] if len(argv) > 2 else "sni")
    if c == "pick":
        return cmd_pick(argv[2] if len(argv) > 2 else "sni",
                        argv[3] if len(argv) > 3 else "")
    if c == "mark":
        return cmd_mark(argv[2], argv[3])
    if c == "verified":
        return cmd_verified(argv[2], argv[3], argv[4] if len(argv) > 4 else "")
    if c == "reset":
        return cmd_reset(argv[2] if len(argv) > 2 else "all")
    if c == "json":
        return cmd_json()
    print("неизвестная команда", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
