#!/usr/bin/env bash
# probe.sh — timestamped HTTPS probe against a Traffic Manager FQDN.
#
# Resolves the FQDN, fetches `/`, parses an origin fingerprint from the
# response body, and prints one row per iteration:
#
#     time | resolved-ip | origin-tag | http-status
#
# Origin fingerprint detection (in order):
#   1. <meta name="origin" content="..."> tag (preferred — what Alex should ship)
#   2. literal substring "primary-github-pages"
#   3. literal substring "fallback-swa"
#   4. otherwise: "unknown"
#
# Args:
#   $1  tm-fqdn          e.g. publix-poc-tm.trafficmanager.net
#   $2  iterations       integer, e.g. 60
#   $3  interval-seconds integer, e.g. 5
#
# Example:
#   ./probe.sh publix-poc-tm.trafficmanager.net 60 5

set -euo pipefail

# Override these if Alex publishes different fingerprint strings.
FP_PRIMARY="primary-github-pages"
FP_FALLBACK="fallback-swa"

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <tm-fqdn> <iterations> <interval-seconds>" >&2
    exit 2
fi

TM_FQDN="$1"
ITER="$2"
INTERVAL="$3"

printf '%-22s  %-18s  %-22s  %s\n' "time" "resolved-ip" "origin-tag" "http-status"

for ((i = 1; i <= ITER; i++)); do
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # dig — tolerate failure
    IP="$(dig +short +time=2 +tries=1 "$TM_FQDN" 2>/dev/null | grep -E '^[0-9.]+$' | head -n1 || true)"
    [[ -z "$IP" ]] && IP="dns-fail"

    # curl — capture body + status; tolerate failure
    BODY_FILE="$(mktemp -t probe-body.XXXXXX)"
    HTTP_STATUS="$(
        curl -sS \
            --max-time 10 \
            --resolve "${TM_FQDN}:443:${IP}" 2>/dev/null \
            -o "$BODY_FILE" \
            -w '%{http_code}' \
            "https://${TM_FQDN}/" 2>/dev/null \
        || echo "curl-fail"
    )"
    # If --resolve failed (e.g. IP=dns-fail), retry without it
    if [[ "$HTTP_STATUS" == "curl-fail" || "$HTTP_STATUS" == "000" ]]; then
        HTTP_STATUS="$(
            curl -sS --max-time 10 -o "$BODY_FILE" -w '%{http_code}' "https://${TM_FQDN}/" 2>/dev/null \
            || echo "curl-fail"
        )"
    fi

    # Fingerprint detection
    ORIGIN="unknown"
    if [[ -s "$BODY_FILE" ]]; then
        # Preferred: <meta name="origin" content="...">
        META_VAL="$(grep -Eio '<meta[^>]+name=["'"'"']?origin["'"'"']?[^>]*content=["'"'"']?[^"'"'"' >]+' "$BODY_FILE" \
            | sed -E 's/.*content=["'"'"']?([^"'"'"' >]+).*/\1/' \
            | head -n1 || true)"
        if [[ -n "$META_VAL" ]]; then
            ORIGIN="$META_VAL"
        elif grep -qF "$FP_PRIMARY" "$BODY_FILE"; then
            ORIGIN="$FP_PRIMARY"
        elif grep -qF "$FP_FALLBACK" "$BODY_FILE"; then
            ORIGIN="$FP_FALLBACK"
        fi
    fi
    rm -f "$BODY_FILE"

    printf '%-22s  %-18s  %-22s  %s\n' "$NOW" "$IP" "$ORIGIN" "$HTTP_STATUS"

    if (( i < ITER )); then
        sleep "$INTERVAL"
    fi
done
