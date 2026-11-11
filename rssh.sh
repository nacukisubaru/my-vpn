#!/bin/bash
# Helper: run a command on the VPN server over SSH (with retries).
# Usage: ./rssh.sh 'command'  |  ./rssh.sh -f localfile 'cat > /root/file'
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
HOST=$(python3 -c "import json;print(json.load(open('$DIR/secrets/server.json'))['host'])")
USER=$(python3 -c "import json;print(json.load(open('$DIR/secrets/server.json'))['user'])")
export SSHPASS=$(python3 -c "import json;print(json.load(open('$DIR/secrets/server.json'))['password'])")
STDIN_FILE=""
if [ "${1:-}" = "-f" ]; then STDIN_FILE="$2"; shift 2; fi
CMD="${1:?command required}"
for i in 1 2 3 4 5; do
  if [ -n "$STDIN_FILE" ]; then
    sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=15 -o ServerAliveInterval=15 -o NumberOfPasswordPrompts=2 \
      "$USER@$HOST" "$CMD" < "$STDIN_FILE" && exit 0
  else
    sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=15 -o ServerAliveInterval=15 -o NumberOfPasswordPrompts=2 \
      "$USER@$HOST" "$CMD" && exit 0
  fi
  echo "[rssh] attempt $i failed, retrying..." >&2
  sleep 3
done
echo "[rssh] all attempts failed" >&2
exit 1
