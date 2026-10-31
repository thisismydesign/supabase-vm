#!/usr/bin/env bash
# Inside the VM: install the Supabase self-hosting bundle, configure it, start it, begin the Tailscale login.
# Usage: setup.sh <name> <public-url> <site-url>
set -euo pipefail
NAME=$1; PUBLIC_URL=$2; SITE_URL=$3
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update && apt-get -y -qq install curl git jq openssl ca-certificates
mkdir -p /etc/docker && echo '{"ip": "127.0.0.1"}' > /etc/docker/daemon.json   # before Docker is installed: publish on localhost only
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
cd /opt
if [ ! -d /opt/supabase ]; then
  curl -fsSL https://raw.githubusercontent.com/supabase/supabase/master/docker/setup.sh | sh -s -- -y --project-dir supabase
fi
cd /opt/supabase
set_env() { sed -i "s|^$1=.*|$1=$2|" .env; }
set_env SUPABASE_PUBLIC_URL "$PUBLIC_URL"
set_env API_EXTERNAL_URL "$PUBLIC_URL/auth/v1"
set_env SITE_URL "$SITE_URL"
set_env ADDITIONAL_REDIRECT_URLS "$SITE_URL"
set_env STUDIO_DEFAULT_PROJECT "$NAME"
set_env FUNCTIONS_VERIFY_JWT false
set_env POOLER_TENANT_ID "${NAME#supabase-}"
cp /opt/supabase-vm/docker-compose.localhost.yml .
set_env COMPOSE_FILE docker-compose.yml:docker-compose.localhost.yml
docker compose up -d
# CI deploys functions over SSH as ubuntu: it needs sshd, Docker, and the functions dir.
apt-get -y -qq install openssh-server
usermod -aG docker ubuntu
chown -R ubuntu:ubuntu volumes/functions
install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh
install -m 600 -o ubuntu -g ubuntu /opt/supabase-vm/ci.pub /home/ubuntu/.ssh/authorized_keys
tailscale up --ssh --hostname "$NAME" --timeout 10s 2>&1 | grep -E "https://|Success" || true
echo "approve the login URL above, then run /opt/supabase-vm/expose.sh"
