# Amos — Failover demo re-run (clean-evidence attempt)

**Date:** 2026-04-28T22:00Z
**Scenario:** #1 — TM endpoint disable / re-enable (Scenario #1 from `tests/README.md`)
**Tools:** rewritten `probe.sh` (commit 872879a) + new SWA `/outage-poc/health` (commit f5f3f8e)
**Evidence log:** `tests/results/probe-2026-04-28-failover-clean.log`

## Headline verdict

- **TM cutover behaviour: PASS (well under 240s RTO)**
- **Demo-evidence cleanliness: FAIL — probe.sh cannot fingerprint the fallback leg**

The infrastructure failed over and failed back correctly and inside the RTO
budget. However the probe instrument we are supposed to demo with cannot tell
you that during the fallback window — every fallback row reads
`unknown / 404` (or `curl-fail`). Finding #2 from yesterday is only
half-closed: Alex's `probe.sh` rewrite works for the primary leg (GH Pages)
but is broken on the fallback leg (AFD).

## Pre-flight (all clean before run)

| check | result |
|---|---|
| `az account show` | `ME-MngEnvMCAP866439-jimwelch-1` (`79eeeab6-...`) |
| `profileMonitorStatus` | `Online` |
| `primary-external` endpoint | `Enabled / Online` (priority 1) |
| `fallback-afd` endpoint | `Enabled / Online` (priority 2) |
| `curl -sI .../outage-poc/health` | `HTTP/2 200`, 14 bytes |
| Baseline `probe.sh ... 6 5` | 6/6 `200` `primary-github-pages` |

## Timeline (UTC, all times from log + recorded shell output)

| event | t (UTC) | offset |
|---|---|---|
| baseline probe started | 21:53:17Z | — |
| 60-iter timing probe launched (5s interval) | 21:53:49Z | — |
| **break-primary.sh** (`primary-external` → Disabled) | **21:53:56Z** | t₀ |
| first non-primary row visible to client | 21:54:05Z | t₀ + **9s** |
| first **sustained** fallback (no more primary rows in next ≥30s) | 21:54:42Z | t₀ + **46s** |
| **restore-primary.sh** (`primary-external` → Enabled) | **21:56:21Z** | t₁ |
| first primary row after restore | 21:57:10Z | t₁ + **49s** |
| first **sustained** primary (no more fallback rows after) | 21:57:57Z | t₁ + **96s** |
| probe finished (60th row) | 21:59:15Z | — |

**Time-to-failover (sustained):** 46s — PASS vs 240s RTO.
**Time-to-failback (sustained):** 96s — PASS vs 240s RTO.

(Initial-cutover and initial-failback are noticeably faster — 9s and 49s — but
in both cases the resolver pool flapped between the two endpoints for several
TTL cycles before settling. I'm reporting the **sustained** numbers as the
honest ones for an SRE budget.)

## What's wrong with the evidence

Every row during the fallback window — 21:54:05 to 21:57:10 — reads:

```
part-0010.t-0009.t-msedge.net     unknown     404       (or curl-fail)
```

Tag distribution today vs yesterday's CNAME-only probe:

| | primary-github-pages | fallback-afd | unknown |
|---|---|---|---|
| yesterday (DNS-only probe) | 30 | 30 | 0 |
| today (`probe.sh` rewrite) | 29 | **0** | **31** |

Yesterday: zero `unknown`. Today: 31 `unknown` rows — the entire fallback
window plus a couple of restore-flap rows.

### Root cause (two bugs in `probe.sh`)

`probe.sh` calls `dig +short publix-poc-tm.trafficmanager.net` and takes the
**last non-IP entry** as the "terminal host" to curl. The actual chain is:

```
publix-poc-tm.trafficmanager.net.
  → publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net.   ← what we want
    → mr-b02.tm-azurefd.net.
      → shed.dual-low.part-0010.t-0009.t-msedge.net.
        → part-0010.t-0009.t-msedge.net.              ← what the script picks
          → 13.107.246.38 / 13.107.213.38
```

1. **Bug A — CNAME chase walks past the AFD endpoint hostname.** The script
   should stop at the first `*.azurefd.net` (or `*.azurestaticapps.net`,
   `*.github.io` …) — i.e. the first hostname that's actually a service
   identity, not a Microsoft anycast label. Picking the last label puts us at
   `part-0010.t-0009.t-msedge.net`, which is shared infra and routes by Host
   header.
2. **Bug B — `path_for_origin` returns `/` for `*.azurefd.net`.** Our AFD
   profile only serves `/outage-poc/...`. Even if Bug A were fixed and we
   curled the AFD hostname directly, `GET /` returns `404`. It needs
   `/outage-poc/`.

Verification that the failover itself is genuine and the AFD origin is
healthy (this is what makes me confident calling RTO PASS despite the
instrument being broken):

```
$ curl -sk https://publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/outage-poc/ \
    | grep -Eo '<meta[^>]*origin[^>]*>'
<meta name="origin" content="fallback-swa">
```

So during the entire fallback window, real users **were** being served the
SWA fallback page with the correct origin tag — `probe.sh` just couldn't see
it because it was hitting the wrong hostname on the wrong path.

## Comparison vs yesterday's run (`probe-2026-04-28-failover.log`)

| metric | yesterday | today | delta |
|---|---|---|---|
| time-to-failover (sustained) | 18s | 46s | **slower (+28s)** |
| time-to-failback (sustained) | 28s | 96s | **slower (+68s)** |
| transition errors / `unknown` | 0 | 31 | **worse** |
| primary leg classified | ✔ | ✔ | same |
| fallback leg classified | ✔ (DNS-only) | ✘ (HTTP probe broken) | **regressed for instrument** |
| fallback endpoint TM status | Degraded (last-resort cutover) | **Online** (real cutover) | **better infra** |

So: **infra got better** (fallback is now genuinely Online and chosen by
priority routing instead of last-resort), **instrument got worse** (HTTP
probe can't see the fallback). The slower wall-clock numbers are partly real
(real probe-driven cutover takes longer than yesterday's all-degraded
last-resort fallback) and partly noise from the resolver pool flapping. Both
sides are still well inside RTO.

## Findings filed

### Finding #3 (NEW — re-opens #2 partially): `probe.sh` cannot classify the AFD fallback leg
- **Severity:** blocks "clean external demo" but does not block PASS verdict.
- **Owner:** Alex (probe.sh) with input from Naomi (correct AFD path).
- **Fix sketch:**
  - In `resolve_terminal_host`, walk the CNAME chain and stop at the first
    label matching a known service-identity pattern
    (`*.github.io`, `*.azurefd.net`, `*.azureedge.net`,
    `*.azurestaticapps.net`). Don't take "last non-IP" blindly.
  - In `path_for_origin`, return `/outage-poc/` (not `/`) for
    `*.azurefd.net` because that is what the AFD profile is configured to
    serve. Or — better — make the path configurable per-leg via env vars and
    keep the test data identical to what real clients hit through TM.
- **Smoke test for the fix:** with `primary-external` Disabled, a 6-iter
  probe must show 6/6 `200` and tag `fallback-swa`.

## Hygiene

- `primary-external` endpoint: confirmed `Enabled / Online` post-test.
- `publix-poc-tm` profile: `profileMonitorStatus = Online` post-test.
- No infra was left in a broken state.

## TL;DR for the standup

> Failover and failback both worked and both fit inside the 240s RTO (46s /
> 96s sustained). Infra side of yesterday's findings is genuinely closed —
> fallback is `Online`, not last-resort. **But** Alex's `probe.sh` rewrite
> only works for the primary leg; it can't fingerprint the fallback leg
> because it chases CNAMEs past the AFD endpoint and asks for the wrong
> path. We can't do a clean external demo with the current probe — need
> Finding #3 fixed first. Evidence: `tests/results/probe-2026-04-28-failover-clean.log`.
