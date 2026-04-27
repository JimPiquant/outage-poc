# Failover Demo Runbook — publix POC

**Audience:** Jim Welch (and anyone running the canonical "watch it fail over" demo).
**Author:** Amos
**Date:** 2026-04-27

This is the script to run the **kill-primary → watch failover → restore-primary**
demonstration end-to-end. Do not run this until Naomi has deployed infra and
Alex has published both sites. Pre-conditions live in [`README.md`](README.md) §2.

Total wall-clock for the demo: **~12–15 minutes** (two RTO windows + setup +
narration time).

---

## 0. Set your variables (do this once per session)

```bash
export TM_FQDN="publix-poc-tm.trafficmanager.net"          # from Naomi
export RG="publix-poc-rg"                                  # from Naomi
export TM_PROFILE="publix-poc-tm"                          # from Naomi
export PRIMARY_EP="primary"                                # from Naomi
export PRIMARY_HEALTH="https://<gh-user>.github.io/publix-primary/health"   # from Alex
export FALLBACK_HEALTH="https://<afd-endpoint>.z01.azurefd.net/health"      # from Naomi/Alex
```

Verify Azure session:

```bash
az account show --query '{name:name, id:id}' -o table
```

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

Expected output (all rows tagged `primary-github-pages`):

```
time                  resolved-ip       origin-tag             http-status
2026-04-27T18:40:05Z  185.199.108.153   primary-github-pages   200
2026-04-27T18:40:10Z  185.199.108.153   primary-github-pages   200
2026-04-27T18:40:15Z  185.199.108.153   primary-github-pages   200
...
```

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
BREAK at 2026-04-27T18:42:30Z
[break-primary] disabling endpoint primary in profile publix-poc-tm (rg=publix-poc-rg)
{
  "endpointStatus": "Disabled",
  ...
}
[break-primary] done. TM will route new DNS queries to the next-priority endpoint.
```

**Now watch the probe terminal.** You should see:

- For up to ~60s: rows still showing `primary-github-pages` (DNS resolvers caching).
- Then: rows flip to `origin-tag=fallback-swa`, `http-status=200`.
- Total time from BREAK to first `fallback-swa` row should be **≤ 240s**.

Annotate the row where the flip happens. That's your measured RTO.

---

## 4. Hold on fallback (≈2 min)

Let the probe run for a couple more minutes against the fallback to demonstrate
the AFD/SWA path is stable. All rows should be `fallback-swa` / `200`.

Optionally, in a third terminal, prove the AFD path is doing the work:

```bash
dig +short "$TM_FQDN"
# expect: a CNAME chain ending in *.z01.azurefd.net
```

---

## 5. Restore primary (T+~5 min from BREAK)

```bash
date -u +"RESTORE at %Y-%m-%dT%H:%M:%SZ"
./scripts/restore-primary.sh "$RG" "$TM_PROFILE" "$PRIMARY_EP"
```

Expected output:

```
RESTORE at 2026-04-27T18:47:35Z
[restore-primary] enabling endpoint primary in profile publix-poc-tm (rg=publix-poc-rg)
{
  "endpointStatus": "Enabled",
  ...
}
[restore-primary] done. TM will route new DNS queries back to primary once probes pass.
```

**Watch the probe terminal again.** TM needs at least 1 successful probe
(typically <30s) before marking primary Healthy, then DNS TTL must expire.
Expect rows to return to `primary-github-pages` within **≤ 240s** of RESTORE.

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
- Probe rows show 5xx after flip? Check AFD origin health and SWA deployment.
- `origin-tag` is `unknown`? Alex's `<meta name="origin">` tag is missing or
  renamed — fix the script's `FP_PRIMARY`/`FP_FALLBACK` constants.
