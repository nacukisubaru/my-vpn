#!/bin/bash
# УСТАРЕЛО. Оставлено для совместимости: смена только SNI (ключи не трогаются).
# Используйте:  ./rotate.sh --sni <домен> --no-keys
# Полный список возможностей: ./rotate.sh --help   и   docs/ROTATION.md
set -euo pipefail
cd "$(dirname "$0")"
echo "[change-dest.sh] устарело → вызываю: ./rotate.sh --sni ${1:?домен} --no-keys"
echo "[change-dest.sh] теперь есть случайный выбор: ./rotate.sh"
exec ./rotate.sh --sni "$1" --no-keys
