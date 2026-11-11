#!/usr/bin/env bash
# Inside the VM: serve the API at the public URL in .env, and let CI in to deploy.
# Tailscale, after its login is approved: expose.sh
# Cloudflare: expose.sh [access-team access-aud], the Zero Trust team and the audience tag of the Access application on <vm>-ssh.<domain>
set -euo pipefail
HOST=$(sed -n 's|^SUPABASE_PUBLIC_URL=https://||p' /opt/supabase/.env)

if [[ $HOST == *.ts.net ]]; then
  tailscale serve --bg --tcp=5432 5432 >/dev/null
  tailscale funnel --bg 8000 2>&1 | grep -E "https://|Funnel" || true
  tailscale serve status
  exit
fi

TEAM=${1:-}; AUD=${TEAM:+${2:?audience tag of the Access application}}
NAME=${HOST%%.*}; SSH_HOST=$NAME-ssh.${HOST#*.}
CREDENTIALS=/etc/cloudflared/$NAME.json; LOGIN=~/.cloudflared/cert.pem

if [ ! -f "$CREDENTIALS" ]; then
  [ -f $LOGIN ] || cloudflared tunnel login
  cloudflared tunnel create --credentials-file "$CREDENTIALS" "$NAME"
fi
if [ -f $LOGIN ]; then
  cloudflared tunnel route dns --overwrite-dns "$NAME" "$HOST"
  cloudflared tunnel route dns --overwrite-dns "$NAME" "$SSH_HOST"
  # The login may edit the whole zone; the tunnel runs on its own credentials.
  rm $LOGIN
fi

# Access is enforced here too, not only at Cloudflare: without it the hostname would hand sshd to anyone.
[ -z "$AUD" ] || SSH_RULE="
  - hostname: $SSH_HOST
    service: ssh://localhost:22
    originRequest:
      access:
        required: true
        teamName: $TEAM
        audTag: [$AUD]"
cat > /etc/cloudflared/config.yml <<EOF
tunnel: $(jq -r .TunnelID "$CREDENTIALS")
credentials-file: $CREDENTIALS
ingress:
  - hostname: $HOST
    service: http://localhost:8000${SSH_RULE:-}
  - service: http_status:404
EOF
if systemctl cat cloudflared >/dev/null 2>&1; then systemctl restart cloudflared; else cloudflared service install; fi
echo "https://$HOST${AUD:+, ssh at $SSH_HOST}"
