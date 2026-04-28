#!/usr/bin/env bash
# probe.sh — timestamped HTTPS probe that follows TM's CNAME to the live origin.
#
# Uses default Host header — works because TM uses CNAME-based DNS, not anycast
# IPs. Each iteration:
#   1. dig the TM FQDN, chase CNAMEs, take the *terminal* hostname
#      (e.g. jimpiquant.github.io or <endpoint>.azurefd.net).
#   2. curl that resolved origin hostname directly with `-sk` so SNI/Host
#      naturally match the real origin's cert and routing.
#   3. Pick the path that the resolved origin actually serves on
#      (GitHub Pages project site lives under /outage-poc/, AFD/SWA at /).
#
# Why no `--resolve` / Host-header override:
#   The cutover signal we want is "where does the TM FQDN currently CNAME to"
#   — and the real origins (GH Pages = *.github.io, AFD = *.azurefd.net) do
#   NOT have publix-poc-tm.trafficmanager.net in their cert SANs, so forcing
#   that as Host/SNI breaks TLS. Following the CNAME and curling the
#   resolved hostname is what a real client effectively does once DNS
#   resolves.
#
# Output columns (one row per iteration, never exits on a single failure):
#   time | resolved-host | origin-tag | http-status
#
# Origin fingerprint detection (in order):
#   1. <meta name="origin" content="..."> tag (preferred — what Alex ships)
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

set -uo pipefail

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

# Pick a path appropriate for the origin we resolved to. Project-site GitHub
# Pages lives under /outage-poc/; AFD/SWA serve at /.
path_for_origin() {
    local host="$1"
    case "$host" in
        *.github.io)             echo "/outage-poc/" ;;
        *.azurefd.net|*.azureedge.net|*.azurestaticapps.net) echo "/" ;;
        *)                       echo "/" ;;
    esac
}

# Chase CNAME chain via `dig +short` and return the terminal label
# (last non-IP entry, with trailing dot stripped). Falls back to the
# original FQDN on dig failure so curl still has something to hit.
resolve_terminal_host() {
    local fqdn="$1"
    local chain
    chain="$(dig +short +time=2 +tries=1 "$fqdn" 2>/dev/null || true)"
    if [[ -z "$chain" ]]; then
        echo "$fqdn"
        return
    fi
    local terminal
    terminal="$(printf '%s\n' "$chain" \
        | grep -Ev '^[0-9.]+$' \
        | tail -n1 \
        | sed 's/\.$//')"
    if [[ -z "$terminal" ]]; then
        echo "$fqdn"
    else
        echo "$terminal"
    fi
}

printf '%-22s  %-42s  %-22s  %s\n' "time" "resolved-host" "origin-tag" "http-status"

for ((i = 1; i <= ITER; i++)); do
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    TARGET_HOST="$(resolve_terminal_host "$TM_FQDN")"
    REQ_PATH="$(path_for_origin "$TARGET_HOST")"

    BODY_FILE="$(mktemp -t probe-body.XXXXXX)"
    HTTP_STATUS="$(
        curl -sk \
            --max-time 10 \
            -o "$BODY_FILE" \
            -w '%{http_code}' \
            "https://${TARGET_HOST}${REQ_PATH}" 2>/dev/null
    )" || HTTP_STATUS="curl-fail"
    [[ -z "$HTTP_STATUS" ]] && HTTP_STATUS="curl-fail"

    # Fingerprint detection
    ORIGIN="unknown"
    if [[ -s "$BODY_FILE" ]]; then
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

    printf '%-22s  %-42s  %-22s  %s\n' "$NOW" "$TARGET_HOST" "$ORIGIN" "$HTTP_STATUS"

    if (( i < ITER )); then
        sleep "$INTERVAL"
    fi
done
