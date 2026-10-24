#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  cp .env.example .env
  echo "AVISO: se creó .env. Revisa POSTGRES_PASSWORD."
fi

docker compose up -d
docker compose ps
