#!/usr/bin/env bash
set -euo pipefail

# One-off helper to enable HTTPS on validator-0 without re-provisioning the VM.
# - Opens UFW for 80/443
# - Starts a Caddy container that reverse-proxies to the existing Silica validator API on :8545
#
# Usage (run on validator-0):
#   sudo ./enable-caddy-validator0.sh --domain rpc.testnet.silicaprotocol.network
#
# Notes:
# - Ensure OCI security lists also allow inbound 80/443.
# - Let’s Encrypt HTTP-01 validation requires port 80 reachable from the Internet.

DOMAIN=""
EMAIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="${2:-}"; shift 2 ;;
    --email)
      EMAIL="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --domain <hostname> [--email <letsencrypt-email>]"; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "Missing --domain (e.g. rpc.testnet.silicaprotocol.network)" >&2
  exit 2
fi

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found; install docker first." >&2
  exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw not found; install ufw first." >&2
  exit 1
fi

# Ensure the validator container exists and is running.
if ! docker ps --format '{{.Names}}' | grep -qx 'silica-validator'; then
  echo "silica-validator container not running (expected from /opt/silica docker-compose)." >&2
  echo "Start the node first: sudo systemctl start silica" >&2
  exit 1
fi

# Detect the docker network the validator is attached to.
NETWORK="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{printf "%s\n" $k}}{{end}}' silica-validator | head -n1)"
if [[ -z "$NETWORK" ]]; then
  echo "Failed to detect docker network for silica-validator." >&2
  exit 1
fi

echo "Using docker network: $NETWORK"

# Create directories for Caddy state.
install -d -m 0755 /opt/silica/caddy
install -d -m 0755 /opt/silica/caddy/data
install -d -m 0755 /opt/silica/caddy/config

# Write Caddyfile.
if [[ -n "$EMAIL" ]]; then
  cat > /opt/silica/caddy/Caddyfile <<EOF
{
  email $EMAIL
}

$DOMAIN {
  encode gzip
  reverse_proxy silica-validator:8545
}
EOF
else
  cat > /opt/silica/caddy/Caddyfile <<EOF
$DOMAIN {
  encode gzip
  reverse_proxy silica-validator:8545
}
EOF
fi

chmod 0644 /opt/silica/caddy/Caddyfile

# Open firewall.
ufw allow 80/tcp
ufw allow 443/tcp

# Start (or restart) caddy container.
if docker ps --format '{{.Names}}' | grep -qx 'silica-caddy'; then
  echo "Restarting existing silica-caddy container..."
  docker rm -f silica-caddy >/dev/null
fi

echo "Starting Caddy on :80/:443 for $DOMAIN ..."
docker run -d \
  --name silica-caddy \
  --restart unless-stopped \
  --network "$NETWORK" \
  -p 80:80 \
  -p 443:443 \
  -v /opt/silica/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v /opt/silica/caddy/data:/data \
  -v /opt/silica/caddy/config:/config \
  caddy:2.8

echo "Done. Next steps:"
echo "- Ensure DNS A record points $DOMAIN -> this VM public IP"
echo "- Verify: https://$DOMAIN/health and https://$DOMAIN/jsonrpc"
