#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "ADVERTENCIA: se eliminará el volumen PostgreSQL y todos los datos locales."
read -r -p "Escribe RESET para continuar: " ANSWER

if [ "$ANSWER" != "RESET" ]; then
  echo "Operación cancelada."
  exit 0
fi

docker compose down -v
