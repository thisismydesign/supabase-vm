#!/usr/bin/env bash
# Create a Supabase VM on this host. Usage: host/create-vm.sh <name> <frontend-url> [cpu] [memory] [disk]
# SUPABASE_REF=self-hosted/v0.8.3 pins the bundle version; the default is the latest release.
# SUPABASE_EXCLUDE=realtime,imgproxy leaves those services of the bundle off; the default runs all of them.
# SUPABASE_DOMAIN=example.com serves the VM at https://<name>.example.com through a Cloudflare Tunnel; the default is Tailscale.
set -euo pipefail
NAME=${1:?vm name, e.g. supabase-stash}
SITE_URL=${2:?frontend url, e.g. https://stash.example.workers.dev}
CPU=${3:-4}; MEM=${4:-4GiB}; DISK=${5:-30GiB}; REF=${SUPABASE_REF:-}; EXCLUDED=${SUPABASE_EXCLUDE:-}; DOMAIN=${SUPABASE_DOMAIN:-}
HERE=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v incus >/dev/null; then
  sudo apt-get install -y -qq incus
  sudo incus admin init --auto
  sudo usermod -aG incus-admin "$USER"
  # ufw: let the VM bridge forward; Docker's FORWARD policy would otherwise drop it.
  sudo ufw allow in on incusbr0 >/dev/null
  sudo ufw route allow in on incusbr0 >/dev/null
  sudo ufw route allow out on incusbr0 >/dev/null
  # Each declaration empties DOCKER-USER: declare it only when no earlier block does.
  sudo grep -q '^:DOCKER-USER ' /etc/ufw/after.rules && DECLARE= || DECLARE=':DOCKER-USER - [0:0]'
  sudo tee -a /etc/ufw/after.rules >/dev/null <<RULES

# BEGIN incus: VM bridge traffic bypasses Docker's FORWARD drop
*filter
$DECLARE
-I DOCKER-USER -i incusbr0 -j ACCEPT
-I DOCKER-USER -o incusbr0 -j ACCEPT
COMMIT
# END incus
RULES
  sudo ufw reload >/dev/null
fi

INCUS="sudo incus"
PUBLIC_URL="https://$NAME.${DOMAIN:-$(tailscale status --json | jq -r .MagicDNSSuffix)}"

$INCUS launch images:ubuntu/24.04/cloud "$NAME" --vm \
  -c limits.cpu="$CPU" -c limits.memory="$MEM" -c boot.autostart=true \
  -d root,size="$DISK"
echo "waiting for the VM agent"
until $INCUS exec "$NAME" -- true 2>/dev/null; do sleep 5; done
$INCUS file push -r "$HERE/vm" "$NAME/opt/" && $INCUS exec "$NAME" -- mv /opt/vm /opt/supabase-vm
$INCUS exec "$NAME" -- chmod +x /opt/supabase-vm/setup.sh /opt/supabase-vm/expose.sh /opt/supabase-vm/services.sh
# CI deploys over SSH with this key; its private half becomes the project's repo secret.
[ -f ~/.ssh/"$NAME"-ci ] || ssh-keygen -q -t ed25519 -N "" -C "$NAME-ci" -f ~/.ssh/"$NAME"-ci
$INCUS file push ~/.ssh/"$NAME"-ci.pub "$NAME/opt/supabase-vm/ci.pub"
$INCUS exec "$NAME" -- /opt/supabase-vm/setup.sh "$NAME" "$PUBLIC_URL" "$SITE_URL" "$REF" "$EXCLUDED"
