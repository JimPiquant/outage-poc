#!/usr/bin/env bash
# DNS-based TM failover probe. Captures CNAME target each tick.
# Args: <tm-fqdn> <iterations> <interval>
TM="$1"; ITER="$2"; INT="$3"
printf '%-22s  %-50s  %s\n' "time" "cname-target" "tag"
for ((i=1;i<=ITER;i++)); do
  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  CNAME="$(dig +short +time=2 +tries=1 CNAME "$TM" @8.8.8.8 2>/dev/null | head -n1)"
  [[ -z "$CNAME" ]] && CNAME="(none)"
  TAG="unknown"
  if [[ "$CNAME" == *"github.io"* ]]; then TAG="primary-github-pages"
  elif [[ "$CNAME" == *"azurefd.net"* ]]; then TAG="fallback-afd"
  elif [[ "$CNAME" == "(none)" ]]; then TAG="no-endpoint"
  fi
  printf '%-22s  %-50s  %s\n' "$NOW" "$CNAME" "$TAG"
  (( i < ITER )) && sleep "$INT"
done
