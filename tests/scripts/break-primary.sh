#!/usr/bin/env bash
# break-primary.sh — simulate a primary outage by disabling the primary TM endpoint.
#
# Uses `az network traffic-manager endpoint update --endpoint-status Disabled`.
# When disabled, TM treats the endpoint as down for routing purposes — new DNS
# resolutions return the next-priority endpoint within DNS TTL.
#
# This bypasses the probe-detection window (~100s) and exercises the DNS-swap
# half of RTO. To exercise the full detection-plus-DNS path, see scenario #3
# in tests/README.md (real /health break).
#
# Args:
#   $1  resource-group   e.g. publix-poc-rg
#   $2  profile-name     e.g. publix-poc-tm
#   $3  endpoint-name    e.g. primary
#
# Example:
#   ./break-primary.sh publix-poc-rg publix-poc-tm primary

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <resource-group> <profile-name> <endpoint-name>" >&2
    exit 2
fi

RG="$1"
PROFILE="$2"
ENDPOINT="$3"

echo "[break-primary] disabling endpoint ${ENDPOINT} in profile ${PROFILE} (rg=${RG})"
az network traffic-manager endpoint update \
    --resource-group  "$RG" \
    --profile-name    "$PROFILE" \
    --name            "$ENDPOINT" \
    --type            ExternalEndpoints \
    --endpoint-status Disabled \
    --output json
echo "[break-primary] done. TM will route new DNS queries to the next-priority endpoint."
