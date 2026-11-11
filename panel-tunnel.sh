#!/bin/bash
# Открывает SSH-туннель к панели 3x-ui (панель слушает только 127.0.0.1 на сервере).
# После запуска панель доступна локально по адресу из вывода.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOST=$(python3 -c "import json;print(json.load(open('$DIR/secrets/server.json'))['host'])")
USER=$(python3 -c "import json;print(json.load(open('$DIR/secrets/server.json'))['user'])")
PORT=$(python3 -c "import json;print(json.load(open('$DIR/secrets/panel.json'))['panel_port'])")
PATH_=$(python3 -c "import json;print(json.load(open('$DIR/secrets/panel.json'))['panel_path'])")

echo "Открываю туннель: localhost:${PORT} -> ${USER}@${HOST}:${PORT}"
echo "Панель:  http://localhost:${PORT}/${PATH_}/"
echo "Логин:   $(python3 -c "import json;print(json.load(open('$DIR/secrets/panel.json'))['panel_user'])")"
echo "Пароль:  $(python3 -c "import json;print(json.load(open('$DIR/secrets/panel.json'))['panel_pass'])")"
echo "Ctrl+C — закрыть туннель."
exec ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L "127.0.0.1:${PORT}:127.0.0.1:${PORT}" "${USER}@${HOST}"
