#!/usr/bin/env bash
# restore-primary.sh — restore the primary TM endpoint after a simulated outage.
#
# Sets `--endpoint-status Enabled`. TM resumes probing; once the endpoint passes
# its next probe (typically <30s), new DNS resolutions return primary again
# (subject to DNS TTL).
#
# Args:
#   $1  resource-group   e.g. publix-poc-rg
#   $2  profile-name     e.g. publix-poc-tm
#   $3  endpoint-name    e.g. primary
#
# Example:
#   ./restore-primary.sh publix-poc-rg publix-poc-tm primary

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <resource-group> <profile-name> <endpoint-name>" >&2
    exit 2
fi

RG="$1"
PROFILE="$2"
ENDPOINT="$3"

echo "[restore-primary] enabling endpoint ${ENDPOINT} in profile ${PROFILE} (rg=${RG})"
az network traffic-manager endpoint update \
    --resource-group  "$RG" \
    --profile-name    "$PROFILE" \
    --name            "$ENDPOINT" \
    --type            ExternalEndpoints \
    --endpoint-status Enabled \
    --output json
echo "[restore-primary] done. TM will route new DNS queries back to primary once probes pass."
