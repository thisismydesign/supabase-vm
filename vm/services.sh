#!/usr/bin/env bash
# Inside the VM: run the bundle without the named services; with none named, run all of it.
# Usage: services.sh [service,...], named as in the bundle's docker-compose.yml
set -euo pipefail
EXCLUDED=${1:-}
OVERRIDE=docker-compose.excluded.yml
cd /opt/supabase

SERVICES=$(docker compose -f docker-compose.yml config --services)
for service in ${EXCLUDED//,/ }; do
  grep -qx "$service" <<<"$SERVICES" || { echo "no service $service; the bundle has: ${SERVICES//$'\n'/ }" >&2; exit 1; }
done

# Scaled to zero, not put in a profile: Compose rejects a dependency on a service outside the active profiles, and the gateway depends on Studio.
echo "services: {$(sed -E 's/[^,]+/&: {scale: 0}/g' <<<"$EXCLUDED")}" > $OVERRIDE
grep -q "^COMPOSE_FILE=.*$OVERRIDE" .env || sed -i "s|^COMPOSE_FILE=.*|&:$OVERRIDE|" .env
docker compose up -d
