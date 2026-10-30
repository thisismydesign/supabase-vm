#!/usr/bin/env bash
# Copy a project's edge functions into the VM and restart the functions service.
# Usage: host/deploy-functions.sh <vm> <path/to/supabase/functions>
set -euo pipefail
NAME=${1:?vm name}; SRC=${2:?functions dir}
sudo incus exec "$NAME" -- rm -rf /opt/supabase/volumes/functions.new
sudo incus file push -r "$SRC" "$NAME/opt/supabase/volumes/functions.new"
sudo incus exec "$NAME" -- bash -c '
  cd /opt/supabase/volumes
  cp -r functions/main functions.new/ 2>/dev/null || true   # keep the bundle router
  rm -rf functions.old && mv functions functions.old && mv functions.new/'"$(basename "$SRC")"' functions && rm -rf functions.new
  cd /opt/supabase && docker compose restart functions'
