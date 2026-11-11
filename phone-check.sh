#!/bin/bash
# Проверяет, реально ли ТЕЛЕФОН гонит трафик через сервер.
# Смотрится не «подключено/не подключено», а байты в базе панели:
# если телефон подключился, но байты не растут — проблема на стороне клиента
# (DNS/маршрутизация/TUN), а не сервера.
#
#   ./phone-check.sh          # окно 60 секунд
#   ./phone-check.sh 120      # окно 120 секунд
set -uo pipefail
cd "$(dirname "$0")"
WINDOW="${1:-60}"

snapshot() {
  ./rssh.sh 'sqlite3 -separator "|" /etc/x-ui/x-ui.db "select email, up, down, last_online from client_traffics"' 2>/dev/null \
    | grep -v '^Warning' | grep '|'
}

echo "== срез ДО =="
BEFORE=$(snapshot)
printf '%s\n' "$BEFORE" | awk -F'|' '{printf "   %-8s up=%.1fMB down=%.1fMB\n", $1, $2/1048576, $3/1048576}'

echo
echo ">>> Подключите VPN на телефоне и откройте в браузере:"
echo ">>>   1) https://www.google.com"
echo ">>>   2) https://www.youtube.com"
echo ">>> Ждём ${WINDOW} секунд..."
echo
for i in $(seq 1 "$WINDOW"); do
  printf "\r   %ss / %ss" "$i" "$WINDOW"
  sleep 1
done
printf "\r   готово.        \n\n"

echo "== срез ПОСЛЕ =="
AFTER=$(snapshot)

python3 - "$BEFORE" "$AFTER" <<'PY'
import sys, datetime

def parse(block):
    out = {}
    for line in block.strip().splitlines():
        parts = line.split("|")
        if len(parts) < 4:
            continue
        email, up, down, last = parts[0], int(parts[1]), int(parts[2]), int(parts[3])
        out[email] = (up, down, last)
    return out

before, after = parse(sys.argv[1]), parse(sys.argv[2])
now = datetime.datetime.now(datetime.timezone.utc)
print(f"{'клиент':<10} {'up Δ':>10} {'down Δ':>12} {'онлайн':<22} вердикт")
print("-" * 78)
for email in sorted(after):
    if email not in before:
        continue
    du = after[email][0] - before[email][0]
    dd = after[email][1] - before[email][1]
    last = after[email][2]
    if last:
        t = datetime.datetime.fromtimestamp(last / 1000, datetime.timezone.utc)
        age = (now - t).total_seconds()
        online = t.strftime("%H:%M:%S") + f" ({int(age)}с назад)"
        fresh = age < 120
    else:
        online, fresh = "никогда", False
    if dd > 102400 or du > 102400:
        verdict = "✅ трафик идёт через VPN"
    elif fresh:
        verdict = "⚠️  подключился, но НЕ качает → DNS/маршрутизация в клиенте"
    else:
        verdict = "— не подключался в это окно"
    print(f"{email:<10} {du/1048576:>9.2f}M {dd/1048576:>11.2f}M {online:<22} {verdict}")
print()
print("Если у телефона «подключился, но НЕ качает»:")
print("  1. DNS в клиенте должен идти ЧЕРЕЗ туннель (DoH https://1.1.1.1/dns-query)")
print("  2. Mux — выключить, режим — TUN/VPN")
print("  3. Либо импортировать client/config-hardened.json (там DNS и маршруты уже верные)")
PY
