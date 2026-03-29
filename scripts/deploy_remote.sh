#!/usr/bin/env bash
# Синхронизация Docker-стека на удалённый хост (rsync + docker compose).
# Использование: ./scripts/deploy_remote.sh user@host [/opt/van3]
set -euo pipefail

TARGET="${1:?user@host}"
RDIR="${2:-/opt/van3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -f "$ROOT/.env.docker" ]]; then
  echo "Создайте $ROOT/.env.docker из .env.docker.example" >&2
  exit 1
fi

cd "$ROOT"
rsync -avz -e ssh docker-compose.yml .env.docker "$TARGET:$RDIR/"
rsync -avz -e ssh docker/initdb/ "$TARGET:$RDIR/docker/initdb/"

ssh "$TARGET" "cd '$RDIR' && docker compose --env-file .env.docker pull 2>/dev/null || true; docker compose --env-file .env.docker up -d && docker compose --env-file .env.docker ps"

echo "OK: $TARGET:$RDIR"
