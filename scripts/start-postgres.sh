#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose up -d
docker compose ps
echo "Waiting for healthy..."
until docker compose exec -T db pg_isready -U postgres; do sleep 1; done
echo "OK — then: mix ecto.create && mix ecto.migrate"
