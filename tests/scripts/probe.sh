#!/usr/bin/env bash
# probe.sh — timestamped HTTPS probe that follows TM's CNAME to the live origin.
#
# Uses default Host header — works because TM uses CNAME-based DNS, not anycast
# IPs. Each iteration:
#   1. Walk the CNAME chain top-down with single-step `dig +short CNAME` calls
#      and stop at the first hostname matching a known service-identity
#      pattern (*.github.io, *.azurefd.net, *.azureedge.net,
#      *.azurestaticapps.net). Don't take "last non-IP" blindly — past the AFD
#      endpoint the chain enters shared MS edge anycast labels
#      (*.t-msedge.net) that route by Host header and will 404 us.
#   2. curl that resolved origin hostname directly with `-sk` so SNI/Host
#      naturally match the real origin's cert and routing.
#   3. Pick the path that the resolved origin actually serves on
#      (GH Pages project site → /outage-poc/, AFD/SWA → /).
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

# Pick a path appropriate for the origin we resolved to.
#   * GH Pages project site lives under /outage-poc/
#   * AFD-in-front-of-SWA serves SWA content at the root → /
#   * SWA direct hits also serve at /
# (Note: per Amos's Finding #3, /outage-poc/ on AFD was suspected to be the
# only served path; verified empirically that AFD/SWA serves /=200 with the
# fallback-swa meta tag, while /outage-poc/ returns SWA's 404 page — which
# *still* carries the meta tag, hence the misleading "tag matched but
# status=404" rows in the prior demo. Keeping /.)
path_for_origin() {
    local host="$1"
    case "$host" in
        *.github.io)             echo "/outage-poc/" ;;
        *.azurefd.net)           echo "/" ;;
        *.azureedge.net)         echo "/" ;;
        *.azurestaticapps.net)   echo "/" ;;
        *)                       echo "/" ;;
    esac
}

# Return 0 if $1 looks like a known service-identity hostname (i.e. an actual
# origin we own/configure), 1 otherwise. Used to stop the CNAME walk before it
# slides into shared Microsoft anycast labels (e.g. *.t-msedge.net) that route
# by Host header rather than by name.
is_service_identity() {
    case "$1" in
        *.github.io)            return 0 ;;
        *.azurefd.net)          return 0 ;;
        *.azureedge.net)        return 0 ;;
        *.azurestaticapps.net)  return 0 ;;
    esac
    return 1
}

# Walk the CNAME chain top-down using single-step `dig +short CNAME <host>`
# lookups, starting from $1. Stop and return the first hostname that matches a
# known service-identity pattern (is_service_identity). If the walk runs out of
# CNAMEs before hitting one, fall back to the last non-IP host seen, and
# finally to the original FQDN. This avoids the prior bug where "last non-IP"
# blindly grabbed shared MS edge anycast labels past the AFD endpoint.
resolve_terminal_host() {
    local fqdn="$1"
    local current="$fqdn"
    local last_host="$fqdn"
    local hops=0
    local max_hops=10
    local next

    while (( hops < max_hops )); do
        local stripped="${current%.}"
        if is_service_identity "$stripped"; then
            echo "$stripped"
            return
        fi
        next="$(dig +short +time=2 +tries=1 CNAME "$current" 2>/dev/null \
            | head -n1 | sed 's/\.$//')"
        if [[ -z "$next" ]]; then
            break
        fi
        last_host="$next"
        current="$next"
        hops=$((hops + 1))
    done

    # No service-identity hit; return the last hostname we resolved (with
    # trailing dot stripped) so curl still has something sensible to try.
    echo "${last_host%.}"
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
