#!/usr/bin/env bash
# health-check.sh — curl both /health URLs and report 200 vs non-200.
#
# Used as a baseline pre-condition check before running any chaos scenario,
# and as a post-test sanity check after a failover/failback cycle.
#
# Args:
#   $1  primary-health-url   e.g. https://<user>.github.io/publix-primary/health
#   $2  fallback-health-url  e.g. https://<afd-endpoint>.z01.azurefd.net/health
#
# Exit code: 0 if both return 200, 1 otherwise.
#
# Example:
#   ./health-check.sh \
#       https://example.github.io/publix-primary/health \
#       https://publix-poc-afd-xxxx.z01.azurefd.net/health

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <primary-health-url> <fallback-health-url>" >&2
    exit 2
fi

PRIMARY_URL="$1"
FALLBACK_URL="$2"

check() {
    local label="$1"
    local url="$2"
    local now status
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "curl-fail")"
    printf '[%s] %-9s %s -> %s\n' "$now" "$label" "$url" "$status"
    [[ "$status" == "200" ]]
}

ok=0
check "primary"  "$PRIMARY_URL"  || ok=1
check "fallback" "$FALLBACK_URL" || ok=1

if [[ "$ok" -eq 0 ]]; then
    echo "RESULT: both healthy"
    exit 0
else
    echo "RESULT: at least one endpoint is NOT returning 200" >&2
    exit 1
fi
