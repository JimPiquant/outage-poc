# Failover Demo Runbook — publix POC

**Audience:** Jim Welch (and anyone running the canonical "watch it fail over" demo).
**Author:** Amos (original) · refreshed by Alex
**Date:** 2026-04-27 · **Last validated:** 2026-04-29

**Last validated — 2026-04-29 (canonical evidence):**
- Failover: **38s** · Failback: **77s** · RTO budget: **240s** (both well inside)
- Evidence: [`tests/results/probe-2026-04-28-failover-final.log`](results/probe-2026-04-28-failover-final.log)
- Tag distribution 28 primary / 24 fallback / 8 transient curl-fail (zero classifier failures)
- Earlier reference run (DNS-only probe, all-degraded fallback): 18s failover / 28s failback — kept for comparison only, not the canonical demo.

This is the script to run the **kill-primary → watch failover → restore-primary**
demonstration end-to-end. Pre-conditions live in [`README.md`](README.md) §2.

Total wall-clock for the demo: **~12–15 minutes** (two RTO windows + setup +
narration time).

---

## Live infra (verify before each demo)

| Variable | Value |
|---|---|
| TM_FQDN | `publix-poc-tm.trafficmanager.net` |
| RG | `rg-publix-poc` (eastus2) |
| TM profile | `publix-poc-tm` |
| Primary TM endpoint name | `primary-external` |
| AFD endpoint | `publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net` |
| SWA hostname | `white-water-098b0170f.7.azurestaticapps.net` |
| Primary site (GH Pages) | `https://jimpiquant.github.io/outage-poc/` |
| Repo (primary content) | `JimPiquant/outage-poc` |
| Subscription | `ME-MngEnvMCAP866439-jimwelch-1` |
| TM probe path (profile-wide) | `/outage-poc/health` |

---

## 0. Set your variables (do this once per session)

```bash
export TM_FQDN="publix-poc-tm.trafficmanager.net"
export RG="rg-publix-poc"
export TM_PROFILE="publix-poc-tm"
export PRIMARY_EP="primary-external"
# GH Pages project sites publish under a /<repo>/ subpath. The apex /health 404s;
# use the subpath URL for the visual check. The TM probe path is /outage-poc/health
# (profile-wide) and is also served by the SWA via staticwebapp.config.json.
export PRIMARY_HEALTH="https://jimpiquant.github.io/outage-poc/"
export FALLBACK_HEALTH="https://publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/"
```

Verify Azure session and that the TM profile is currently healthy
(don't start a demo against a Degraded profile — you'll measure noise):

```bash
az account show --query '{name:name, id:id}' -o table

az network traffic-manager profile show \
    -g "$RG" -n "$TM_PROFILE" \
    --query profileMonitorStatus -o tsv
# expect: Online
```

> **gh CLI hygiene:** when piping `gh` output, use `| cat` — `| head` deadlocks
> the pager. Example: `gh run list --limit 5 | cat`.

---

## 1. Baseline (≈1 min)

Confirm both origins are healthy and TM is steering to primary.

```bash
cd tests
./scripts/health-check.sh "$PRIMARY_HEALTH" "$FALLBACK_HEALTH"
```

Expected output:

```
[2026-04-27T18:40:00Z] primary  https://<...>/health  -> 200 OK
[2026-04-27T18:40:00Z] fallback https://<...>/health  -> 200 OK
RESULT: both healthy
```

```bash
./scripts/probe.sh "$TM_FQDN" 6 5
```

Expected output (all 6 rows tagged `primary-github-pages`, status 200):

```
time                  resolved-host          origin-tag             http-status
2026-04-29T03:48:25Z  jimpiquant.github.io   primary-github-pages   200
2026-04-29T03:48:30Z  jimpiquant.github.io   primary-github-pages   200
2026-04-29T03:48:35Z  jimpiquant.github.io   primary-github-pages   200
...
```

**How `probe.sh` works** (current contract — commits `872879a` + `b07fad5`):

- CNAME-chases the TM hostname via single-step `dig +short CNAME` lookups,
  stopping at the **first** service-identity match: `*.github.io`,
  `*.azurefd.net`, `*.azurestaticapps.net`, `*.azureedge.net`. (Stopping at
  "last non-IP" was the old bug — the chain continues into shared MS edge
  anycast `*.t-msedge.net` past the AFD endpoint.)
- Curls the resolved origin with **default SNI/Host** (no `--resolve` override)
  on a per-origin path: `/outage-poc/` for `*.github.io`, `/` for AFD/SWA.
- Origin tags emitted: `primary-github-pages`, `fallback-swa`. Transient TLS or
  socket errors print `curl-fail` and the loop continues (`set -uo pipefail`,
  no `set -e`).

If you see `fallback-swa` in baseline, **stop** — the primary endpoint is
disabled or unhealthy. Do not proceed to chaos.

If you see `fallback-swa` here, **stop** — something is wrong with the baseline,
do not proceed to chaos.

---

## 2. Start a long-running probe (background, leave it running)

This is your timing graph. It records every 5s for 12 minutes (144 rows) so it
captures both the failover and the failback in a single output.

Open a **second terminal** for this:

```bash
cd tests
./scripts/probe.sh "$TM_FQDN" 144 5 | tee probe-$(date -u +%Y%m%dT%H%M%SZ).log
```

Let it run untouched. You'll watch this terminal during the demo.

---

## 3. Break primary (T+0)

Back in the first terminal:

```bash
date -u +"BREAK at %Y-%m-%dT%H:%M:%SZ"
./scripts/break-primary.sh "$RG" "$TM_PROFILE" "$PRIMARY_EP"
```

Expected output:

```
BREAK at 2026-04-29T03:48:25Z
[break-primary] disabling endpoint primary-external in profile publix-poc-tm (rg=rg-publix-poc)
{
  "endpointStatus": "Disabled",
  ...
}
[break-primary] done. TM will route new DNS queries to the next-priority endpoint.
```

**Now watch the probe terminal.** You should see:

- For up to ~60s: rows still showing `primary-github-pages` (DNS resolvers caching).
- Then: rows flip to `origin-tag=fallback-swa`, `http-status=200`,
  `resolved-host=publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net`.
- Total time from BREAK to first sustained `fallback-swa` row should be **≤ 240s**.
  Canonical measurement (2026-04-28 final run): **38s**.

Annotate the row where the flip happens. That's your measured RTO.

**AFD path quirk — read this once:** the probe asks `/` against AFD on purpose.
The AFD-fronted SWA serves `/`=200 with the correct `<meta name="origin"
content="fallback-swa">`. Asking `/outage-poc/` against AFD returns the SWA's
404 page, **which also carries the `fallback-swa` meta tag** — that's the trap
that fooled the first rerun. If you're hand-curling AFD to verify, use `/`.

---

## 4. Hold on fallback (≈2 min)

Let the probe run for a couple more minutes against the fallback to demonstrate
the AFD/SWA path is stable. All rows should be `fallback-swa` / `200`.

Optionally, in a third terminal, prove the AFD path is doing the work:

```bash
dig +short "$TM_FQDN"
# expect: a CNAME chain ending at the AFD endpoint
#         publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net
# (chain may continue into *.t-msedge.net shared anycast — that's fine,
#  probe.sh stops at the first *.azurefd.net match)
```

---

## 5. Restore primary (T+~5 min from BREAK)

```bash
date -u +"RESTORE at %Y-%m-%dT%H:%M:%SZ"
./scripts/restore-primary.sh "$RG" "$TM_PROFILE" "$PRIMARY_EP"
```

Expected output:

```
RESTORE at 2026-04-29T03:53:25Z
[restore-primary] enabling endpoint primary-external in profile publix-poc-tm (rg=rg-publix-poc)
{
  "endpointStatus": "Enabled",
  ...
}
[restore-primary] done. TM will route new DNS queries back to primary once probes pass.
```

**Watch the probe terminal again.** TM needs at least 1 successful probe
(typically <30s) before marking primary Healthy, then DNS TTL must expire.
Expect rows to return to `primary-github-pages` within **≤ 240s** of RESTORE.
Canonical measurement (2026-04-28 final run): **77s**.

> **Always run `restore-primary.sh` at the end** — and defensively if anything
> fails mid-test. Leaving `primary-external` Disabled poisons the next
> operator's baseline.

---

## 6. Stop the long-running probe

Once you've seen the failback complete:

- Ctrl-C the probe terminal.
- The `probe-<timestamp>.log` file is your evidence artifact. Keep it.

---

## 7. Verify final state

```bash
./scripts/health-check.sh "$PRIMARY_HEALTH" "$FALLBACK_HEALTH"
./scripts/probe.sh "$TM_FQDN" 6 5
```

Both should look identical to §1 baseline.

---

## 8. Demo summary template

Paste your numbers into this template when reporting results:

```
publix POC failover demo — 2026-04-27

  Detection + DNS swap window:
    BREAK     at <ts1>
    First fallback row at <ts2>
    Measured failover RTO = <ts2 - ts1>  (target ≤ 240s)

  Failback window:
    RESTORE   at <ts3>
    First primary row at <ts4>
    Measured failback RTO = <ts4 - ts3>  (target ≤ 240s)

  Probe log:    probe-<timestamp>.log
  Errors during swap: <count of non-200 rows>
  Verdict: PASS / FAIL
```

---

## 9. If it fails

- Failover took > 240s? Check:
  - TM TTL via `az network traffic-manager profile show -g $RG -n $TM_PROFILE --query dnsConfig.ttl` — should be 60.
  - Probe interval and tolerated failures match architecture (`monitorConfig`).
  - Your local resolver isn't pinning a longer TTL (try `dig @1.1.1.1`).
  - Profile status is Online before you started: `az network traffic-manager
    profile show -g "$RG" -n "$TM_PROFILE" --query profileMonitorStatus -o tsv`.
- Probe rows show 5xx after flip? Check AFD origin health and SWA deployment.
- `origin-tag` is `unknown`? Either Alex's `<meta name="origin">` tag is
  missing/renamed (fix the script's `FP_PRIMARY`/`FP_FALLBACK` constants), or
  the CNAME walk landed on something other than a service-identity host
  (`*.github.io`, `*.azurefd.net`, `*.azurestaticapps.net`, `*.azureedge.net`)
  — see Findings #1–#3 history below.
- `gh` commands hang? You piped to `| head`. Use `| cat`.

---

## 10. Findings history

| # | Issue | Status | Resolution |
|---|---|---|---|
| #1 | `probe.sh` v1 forced SNI=TM-FQDN against origins (`*.github.io`, `*.azurefd.net`) whose certs don't include that SAN → 100% TLS handshake failures. | ✅ **CLOSED** | Commit `872879a`: rewrote `probe.sh` to CNAME-chase via `dig` and curl the resolved hostname with default SNI. |
| #2 | TM profile probe path is `/outage-poc/health` (constrained by the GH Pages project subpath), but the SWA only served `/health`, leaving the fallback endpoint Degraded. | ✅ **CLOSED** | Commit `f5f3f8e`: added `/outage-poc/health` route in `sites/fallback/staticwebapp.config.json`. TM `profileMonitorStatus = Online`, both endpoints `Online`. Required to keep TM healthy because the probe path is profile-wide. |
| #3 | `probe.sh` could not classify the AFD fallback leg — CNAME walk slid past AFD into shared `*.t-msedge.net` anycast, and an incorrect AFD path (`/outage-poc/`) was being asked. | ✅ **CLOSED** | Commit `b07fad5`: CNAME walk now stops at first service-identity host; AFD path is `/` (empirically verified — `/outage-poc/` returns the SWA 404 page which deceptively still carries the `fallback-swa` meta tag). Final clean rerun captured in `probe-2026-04-28-failover-final.log`. |
