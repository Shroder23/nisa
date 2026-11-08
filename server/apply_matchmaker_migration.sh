#!/usr/bin/env bash
set -euo pipefail
cd /srv/nisa
mkdir -p backups
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
sudo docker exec nisa-postgres pg_dump -U nisa_app -d nisa --format=custom > "backups/nisa_pre_matchmaker_${STAMP}.dump"
cat app/MATCHMAKER_SCHEMA.sql | sudo docker exec -i nisa-postgres psql -v ON_ERROR_STOP=1 -U nisa_app -d nisa
sudo docker compose up -d --build api
sudo docker exec nisa-postgres psql -U nisa_app -d nisa -c "SELECT to_regclass('public.matchmaker_accounts'), to_regclass('public.partner_profiles'), to_regclass('public.matchmaker_introductions');"
curl -fsS http://127.0.0.1:8080/health
