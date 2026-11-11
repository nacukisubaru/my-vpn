#!/bin/bash
# Откат к снапшоту из docs/snapshots/<имя>
#   ./rollback.sh                       — список снапшотов
#   ./rollback.sh 2026-11-05-pre-rotation
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -eq 0 ]; then
  echo "Доступные снапшоты:"; ls -1 docs/snapshots/ | sed 's/^/  /'; exit 0
fi

SNAP="docs/snapshots/$1"
[ -d "$SNAP" ] || { echo "нет такого снапшота: $SNAP" >&2; exit 1; }

echo "== откат инбаундов из $SNAP =="
for f in "$SNAP"/inbound-*.json; do
  [ -e "$f" ] || continue
  id=$(basename "$f" .json | sed 's/inbound-//')
  echo "  inbound id=$id"
  ./xui-api.sh POST "/panel/api/inbounds/update/$id" "$f" | head -c 90; echo
done

echo "== пересборка клиентских файлов из панели =="
./sync-client.sh | tail -8

echo "== проверка =="
./diag.sh 2>/dev/null | sed -n '/3. Реальный/,/4. Сервер/p'
echo "Готово. Не забудьте переимпортировать профили на устройствах (ключи изменились)."
