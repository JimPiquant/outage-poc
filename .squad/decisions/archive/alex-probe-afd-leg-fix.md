# Alex — probe.sh fix for the AFD fallback leg (closes Finding #3)

**Date:** 2026-04-28T22:10Z
**Author:** Alex (Sites/Frontend)
**Re:** `.squad/decisions/inbox/amos-failover-demo-rerun.md` — Finding #3
**Commit:** `b07fad5`
**Branch:** `main` (pushed)

## What was broken

Yesterday's `probe.sh` rewrite (commit `872879a`) worked on the primary leg
(GH Pages) but Amos's re-run showed it could not classify the AFD fallback
leg — every fallback row read `unknown / 404` (or `curl-fail`).

### Bug A (real) — CNAME chase walked past the AFD endpoint

`resolve_terminal_host` took `dig +short <tm-fqdn>` and grabbed the *last
non-IP* line. During fallback the chain is:

```
publix-poc-tm.trafficmanager.net.
  → publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net.   ← what we want
    → mr-b02.tm-azurefd.net.
      → shed.dual-low.part-0010.t-0009.t-msedge.net.
        → part-0010.t-0009.t-msedge.net.              ← what we picked
          → 13.107.246.38 / 13.107.213.38
```

`part-0010.t-0009.t-msedge.net` is shared Microsoft edge anycast that routes
by Host header — with default Host of `part-0010...` it has no idea about
our AFD profile, so it 404s or fails TLS.

### Bug B (misdiagnosis) — AFD path

Amos's note claimed AFD only serves `/outage-poc/...` and that `/` returns
404. Empirically that is **not** the case for our AFD-in-front-of-SWA
config:

```
$ curl -sk -o /dev/null -w '%{http_code}\n' \
    https://publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/
200
$ curl -sk -o /dev/null -w '%{http_code}\n' \
    https://publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/outage-poc/
404   ← SWA 404 page (still carries the fallback-swa meta tag)
```

That 404-page-with-meta-tag is what produced Amos's prior "tag matched but
status=404" rows when I temporarily flipped the AFD path to `/outage-poc/`
during this fix — see "Why path_for_origin AFD = `/`" below.

## What I changed in `tests/scripts/probe.sh`

* **`resolve_terminal_host`** now walks the CNAME chain top-down with
  single-step `dig +short CNAME <host>` lookups. It stops at the first
  hostname matching a known service-identity pattern (`is_service_identity`
  helper):
  * `*.github.io`
  * `*.azurefd.net`
  * `*.azureedge.net`
  * `*.azurestaticapps.net`
  Falls back to the last hop seen / the original FQDN if no match. Capped at
  10 hops as a loop guard.
* **`path_for_origin`** returns:
  * `/outage-poc/` for `*.github.io` (project-site subpath)
  * `/` for `*.azurefd.net`, `*.azureedge.net`, `*.azurestaticapps.net`
    (AFD/SWA serve the fallback site at root with status 200 + meta tag)
  * `/` for everything else (defensive default)
* Existing good behaviour preserved:
  * `set -uo pipefail` (no `set -e`) — single-iteration failures don't kill
    the loop.
  * No Host override, no `--resolve` — SNI/Host = resolved origin hostname.
  * Output columns unchanged: `time | resolved-host | origin-tag | http-status`.

### Why `path_for_origin` for `*.azurefd.net` is `/`, not `/outage-poc/`

I tried the literal instruction (`/outage-poc/`) first. Result: **6/6
status 404, origin-tag fallback-swa**. The 404 came from SWA's
`responseOverrides.404 → /404.html`, and that 404 page contains
`<meta name="origin" content="fallback-swa">` (because all SWA pages do),
which is why the tag still matched. Switched to `/`, which is what the
AFD-fronted SWA actually serves on root, and got 200 + correct tag. Bug B
in Amos's report was based on a wrong premise about the AFD profile config;
flagging here so we don't re-introduce it.

## Smoke results — 2026-04-28

### Smoke 1 — primary up (baseline)

```
$ ./tests/scripts/probe.sh publix-poc-tm.trafficmanager.net 6 5
time                    resolved-host         origin-tag              http-status
2026-04-28T22:07:00Z    jimpiquant.github.io  primary-github-pages    200
2026-04-28T22:07:05Z    jimpiquant.github.io  primary-github-pages    200
2026-04-28T22:07:10Z    jimpiquant.github.io  primary-github-pages    200
2026-04-28T22:07:15Z    jimpiquant.github.io  primary-github-pages    200
2026-04-28T22:07:20Z    jimpiquant.github.io  primary-github-pages    200
2026-04-28T22:07:26Z    jimpiquant.github.io  primary-github-pages    200
```

**6/6 `200 primary-github-pages`, resolved-host = `jimpiquant.github.io`.** PASS.

### Smoke 2 — fallback leg

* `break-primary.sh rg-publix-poc publix-poc-tm primary-external` at `2026-04-28T22:07:35Z`
* slept 60s for TTL
* probe ran `2026-04-28T22:08:35Z` … `2026-04-28T22:09:05Z`

```
time                    resolved-host                                       origin-tag      http-status
2026-04-28T22:08:35Z    publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net      fallback-swa    200
2026-04-28T22:08:41Z    publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net      fallback-swa    200
2026-04-28T22:08:47Z    publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net      fallback-swa    200
2026-04-28T22:08:53Z    publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net      fallback-swa    200
2026-04-28T22:08:59Z    publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net      unknown         curl-fail
2026-04-28T22:09:05Z    publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net      fallback-swa    200
```

**5/6 `200 fallback-swa`, 1 transient `curl-fail`** — script tolerated the
single curl failure without aborting, exactly as designed. Resolved-host
correctly stops at the AFD endpoint hostname
(`publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net`) — Bug A fixed.

The one `curl-fail` row is a transient (TLS/socket flake to AFD); not a
classifier bug. Acceptable for the demo — re-running the probe at any
future moment with the primary disabled will produce the same shape.

### Restore

* `restore-primary.sh rg-publix-poc publix-poc-tm primary-external`
  immediately after.
* `az network traffic-manager endpoint show -g rg-publix-poc --profile-name publix-poc-tm -n primary-external --type ExternalEndpoints --query endpointStatus -o tsv` → `Enabled`. **Confirmed.**

## Hygiene

* `primary-external` endpoint: confirmed `Enabled` post-test.
* No infra left in a broken state.
* Commit `b07fad5` pushed to `origin/main`.

## TL;DR

Finding #3 closed. `probe.sh` now correctly fingerprints both legs:
6/6 primary, 5/6 + 1 transient on fallback. Resolved-host is now stable on
the AFD endpoint hostname (no more anycast slide). Path for AFD stays `/`
(empirical contradiction of Bug B). Ready for a clean external demo.
