#!/usr/bin/env bash
# Create a Supabase VM on this host. Usage: host/create-vm.sh <name> <frontend-url> [cpu] [memory] [disk]
set -euo pipefail
NAME=${1:?vm name, e.g. supabase-stash}
SITE_URL=${2:?frontend url, e.g. https://stash.example.workers.dev}
CPU=${3:-4}; MEM=${4:-6GiB}; DISK=${5:-60GiB}
HERE=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v incus >/dev/null; then
  sudo apt-get install -y -qq incus
  sudo incus admin init --auto
  sudo usermod -aG incus-admin "$USER"
  # ufw: let the VM bridge forward; Docker's FORWARD policy would otherwise drop it.
  sudo ufw allow in on incusbr0 >/dev/null
  sudo ufw route allow in on incusbr0 >/dev/null
  sudo ufw route allow out on incusbr0 >/dev/null
  sudo tee -a /etc/ufw/after.rules >/dev/null <<'RULES'

# BEGIN incus: VM bridge traffic bypasses Docker's FORWARD drop
*filter
:DOCKER-USER - [0:0]
-I DOCKER-USER -i incusbr0 -j ACCEPT
-I DOCKER-USER -o incusbr0 -j ACCEPT
COMMIT
# END incus
RULES
  sudo ufw reload >/dev/null
fi

INCUS="sudo incus"
TAILNET=$(tailscale status --json | jq -r .MagicDNSSuffix)
PUBLIC_URL="https://$NAME.$TAILNET"

$INCUS init images:ubuntu/24.04/cloud "$NAME" --vm \
  -c limits.cpu="$CPU" -c limits.memory="$MEM" -c boot.autostart=true \
  -d root,size="$DISK"
$INCUS config set "$NAME" cloud-init.user-data "$(cat "$HERE/vm/cloud-init.yaml")"
$INCUS start "$NAME"
echo "waiting for cloud-init"
until $INCUS exec "$NAME" -- cloud-init status --wait >/dev/null 2>&1; do sleep 5; done
$INCUS file push -r "$HERE/vm" "$NAME/opt/" && $INCUS exec "$NAME" -- mv /opt/vm /opt/supabase-vm
$INCUS exec "$NAME" -- chmod +x /opt/supabase-vm/setup.sh /opt/supabase-vm/expose.sh
$INCUS exec "$NAME" -- /opt/supabase-vm/setup.sh "$NAME" "$PUBLIC_URL" "$SITE_URL"
