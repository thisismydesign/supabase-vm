#!/usr/bin/env bash
# Inside the VM, after the Tailscale login is approved: public API via Funnel, tailnet-only Postgres.
set -euo pipefail
tailscale serve --bg --tcp=5432 5432 >/dev/null
tailscale funnel --bg 8000 2>&1 | grep -E "https://|Funnel" || true
tailscale serve status
