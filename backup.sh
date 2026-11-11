#!/bin/bash
# Бэкап базы 3x-ui (клиенты, инбаунды, настройки) в ./backups/
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/backups"
OUT="$DIR/backups/x-ui-$(date +%Y-%m-%d_%H%M).db"
"$DIR/rssh.sh" 'base64 -w0 /etc/x-ui/x-ui.db' | base64 -d > "$OUT"
echo "Сохранено: $OUT ($(wc -c < "$OUT") байт)"
