# Failover Test Plan — publix POC

**Author:** Amos (Tester / Chaos)
**Date:** 2026-04-27
**Status:** Authoring complete — execution blocked on Naomi (TM deploy) + Alex (sites live).

This plan validates the resiliency design in [`../docs/architecture.md`](../docs/architecture.md):
Traffic Manager (priority routing) in front of a non-Azure primary (GitHub Pages) and an
AFD-fronted Azure Static Web App fallback. We measure whether failover actually meets the
**~2.5–4 minute RTO** asserted in the architecture doc.

---

## 1. Goals — what success looks like

1. **Detection:** TM marks primary `Degraded` within `(tolerated_failures × interval) + timeout`
   = `(3 × 30s) + 10s = 100s` of the first failed probe.
2. **DNS swap:** New DNS resolutions of the TM FQDN return the AFD endpoint within
   `100s + TTL(60s) + resolver_jitter(0–60s)` = **160–220s** (≤4 minutes worst case).
3. **End-user observable:** A client polling the TM FQDN sees the response body fingerprint
   change from `primary-github-pages` → `fallback-swa` within the RTO window above.
4. **Failback:** When primary is restored, new resolutions return the primary endpoint
   within the same RTO window. No manual intervention.
5. **Cached clients:** Clients with a fresh DNS cache continue hitting whichever endpoint
   they resolved until their TTL expires — this is expected, not a bug.
6. **No drop to zero:** With `Always Serve` + priority routing, total request availability
   should remain ≥99% during the swap window (some 5xx from primary is expected before
   detection completes; the fallback should be serving 200 throughout).

If any of those fail, the architecture's RTO claim is wrong and we file a finding.

---

## 2. Pre-conditions

Before running ANY scenario in §3, verify:

- [ ] **Naomi** has deployed Bicep and shared:
  - Resource group name: `rg-publix-poc` (eastus2)
  - TM profile name: `publix-poc-tm`
  - TM FQDN: `publix-poc-tm.trafficmanager.net`
  - TM endpoint names: `primary-external` (priority 1), `fallback-afd` (priority 2)
  - AFD endpoint hostname: `publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net`
  - SWA hostname: `white-water-098b0170f.7.azurestaticapps.net`
- [ ] **Alex** has published:
  - Primary GitHub Pages URL: `https://jimpiquant.github.io/outage-poc/`
    (project Pages site — there is **no apex `/health`**; TM probes
    `/outage-poc/health` profile-wide)
  - `/outage-poc/health` returns HTTP 200 with body fingerprint
    `<meta name="origin" content="primary-github-pages">`
  - Fallback site deployed to SWA; both `/health` and `/outage-poc/health`
    return HTTP 200 with body fingerprint
    `<meta name="origin" content="fallback-swa">` (the `/outage-poc/health`
    route lives in `sites/fallback/staticwebapp.config.json`, commit `f5f3f8e`)
- [ ] `az login` is current and the test operator has at least
  `Traffic Manager Contributor` on the RG.
- [ ] Local tools: `bash >=4`, `curl`, `dig`, `az` CLI ≥ 2.55.
- [ ] Baseline health check passes:
  ```bash
  ./scripts/health-check.sh \
      https://jimpiquant.github.io/outage-poc/ \
      https://publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/
  ```
  Both return `200 OK`.
- [ ] Baseline probe shows traffic going to primary:
  ```bash
  ./scripts/probe.sh publix-poc-tm.trafficmanager.net 6 5
  ```
  All 6 rows show `origin-tag=primary-github-pages` (canonical smoke).
- [ ] TM profile is currently `Online`:
  ```bash
  az network traffic-manager profile show \
      -g rg-publix-poc -n publix-poc-tm \
      --query profileMonitorStatus -o tsv
  ```

If any pre-condition fails, **stop**. Do not run chaos scenarios against an
unverified baseline — you'll just measure noise.

---

## 3. Test matrix

| # | Scenario | How to break primary | Expected behavior | How we measure | Pass criteria |
|---|----------|----------------------|-------------------|----------------|---------------|
| 1 | **Baseline — both healthy** | nothing — both endpoints up | TM resolves to primary; `/health` on both returns 200 | `probe.sh <tm> 6 10` (60s window) + `health-check.sh` | 6/6 probes show `origin=primary-github-pages`, both `/health` = 200 |
| 2 | **Primary returns 5xx** | Disable TM primary endpoint via `break-primary.sh` (cleanest simulation of "primary fails probes"). For a true 5xx, swap the GH Pages repo content for a 503 page — slower to revert. | TM marks primary Degraded after ~100s; new DNS resolutions return AFD; probe body fingerprint flips to `fallback-swa` | `probe.sh <tm> 60 10` (10 min window) started **before** breaking; record timestamp of the disable command; find the row where `origin-tag` first becomes `fallback-swa` | Flip happens ≤ **240s** after disable command. No probe row shows `http-status` outside `[200, 599]` (we tolerate transient errors but not connection-level fails after flip). |
| 3 | **Primary `/health` returns 404** | Push a commit to the primary repo that removes/renames `/health`. (Or, if Alex set up a query-param toggle, hit it.) | Same as #2 — TM marks Degraded after 3 consecutive 404s | Same as #2 | Same as #2. Note: probe body still shows primary content for clients that bypass `/health` — TM only cares about the probe path. |
| 4 | **Primary completely unreachable** | Easiest: `break-primary.sh` (TM treats Disabled like dead). For a true network-level break, change the TM endpoint's target FQDN to a deliberately-bad parameter (e.g., `does-not-exist.invalid`) via Bicep redeploy or `az network traffic-manager endpoint update --target ...`. | TM probes time out (10s each) → marks Degraded after 3 cycles → DNS flips | Same as #2. Additionally `dig +short <tm-fqdn>` should resolve to AFD-shaped CNAME chain. | Flip ≤ **240s**. `dig` shows AFD hostname in CNAME chain after flip. |
| 5 | **Failback — primary recovers** | Run `restore-primary.sh` after scenario 2/3/4 has flipped to fallback | TM marks primary Healthy after 1 successful probe (TM's healthy threshold is 1 by default). DNS reverts to primary within RTO. Existing cached clients continue on fallback until their TTL expires. | Continue the same `probe.sh` run; record timestamp of restore command; find row where `origin-tag` returns to `primary-github-pages` | Flip back ≤ **240s** after restore command. |
| 6 | **DNS TTL behavior** | Mid-failover (after scenario 2 flip), open a second terminal and run `probe.sh` from a host that already cached the primary IP just before the break. | Cached-DNS client keeps hitting primary (and seeing 5xx or connection errors) until its local TTL expires (~60s). New `dig` lookups return AFD immediately after TM flips. | Run `dig +short <tm-fqdn>` repeatedly during the flip; compare with `probe.sh` output. Note timestamps where `dig` answer changes vs. when `probe.sh` (which re-resolves each curl) flips. | New resolutions flip within RTO. Cached clients flip within `cache_age + TTL`. Behavior is documented, not "passing/failing" per se — this scenario validates the RTO model is honest about cache. |

---

## 4. Expected RTO math (re-derived from `docs/architecture.md` §3.4)

```
detection_time = (tolerated_failures × probe_interval) + probe_timeout
               = (3 × 30s) + 10s
               = 100 s

dns_propagation = TM_TTL + downstream_resolver_variance
                = 60s + (0–60s)
                = 60–120 s

RTO            = detection_time + dns_propagation
               = 100s + 60–120s
               = 160–220 s   (≈ 2.5–4 min)
```

**We use 240s as the pass threshold** (architecture upper bound + 20s grace for
clock skew between operator wall-clock and TM's internal probe schedule).

---

## 5. Manual chaos via Azure (clean, repeatable)

For Scenarios 2 and 4, the cleanest simulated failure is to disable the primary
TM endpoint. TM treats `Disabled` exactly like `Degraded` for routing purposes —
no probe lag waiting for the 100s detection window — which makes it ideal for
demonstrating the **DNS propagation half** of RTO in isolation.

### 5.1 Via Azure CLI

```bash
# DISABLE primary (simulate outage)
az network traffic-manager endpoint update \
    --resource-group   rg-publix-poc \
    --profile-name     publix-poc-tm \
    --name             primary-external \
    --type             ExternalEndpoints \
    --endpoint-status  Disabled

# RE-ENABLE primary (restore) — ALWAYS run this at the end of a test,
# and defensively if anything fails mid-run.
az network traffic-manager endpoint update \
    --resource-group   rg-publix-poc \
    --profile-name     publix-poc-tm \
    --name             primary-external \
    --type             ExternalEndpoints \
    --endpoint-status  Enabled
```

These are wrapped by `scripts/break-primary.sh` and `scripts/restore-primary.sh`.

### 5.2 Via Azure Portal

1. Portal → Resource groups → `rg-publix-poc` → `publix-poc-tm` (Traffic Manager profile).
2. **Endpoints** blade → click `primary-external`.
3. Set **Status** to `Disabled` → Save. (Restore by setting back to `Enabled`.)

### 5.3 Real outage simulation (slower, more realistic)

If you want to exercise the **detection** half of RTO too (not just DNS), break
the actual origin instead of the TM endpoint:

- **GitHub Pages 503:** push a commit replacing `/health` body with a hard-coded
  503 response (GitHub Pages doesn't let you set status codes, so use
  `<meta http-equiv="refresh" content="0;url=/__broken">` and have TM probe a
  path that 404s) — fiddly. Easier: **rename the `/health` file** so the probe
  hits a real 404. Use scenario #3 for that.
- **DNS-level break:** change the TM endpoint's `--target` to
  `does-not-exist.invalid` and let TM probes time out for 100s. Restore by
  setting the target back. This is the fullest simulation but redeploys Bicep
  state, so prefer endpoint-disable for quick demos.

---

## 6. What's parameterized vs. hardcoded

All scripts under `scripts/` take their target endpoints as **arguments** — there
are no baked-in hostnames. Once Naomi shares the deployed names, populate this
file's pre-conditions section and you can run.

Anticipated argument set (Jim, you'll need these handy):

| Variable | Source | Value |
|---|---|---|
| `<tm-fqdn>` | Naomi (Bicep output) | `publix-poc-tm.trafficmanager.net` |
| `<rg>` | Naomi (Bicep param) | `rg-publix-poc` |
| `<profile>` | Naomi (Bicep output) | `publix-poc-tm` |
| `<primary-endpoint-name>` | Naomi (Bicep) | `primary-external` |
| `<primary-health-url>` | Alex | `https://jimpiquant.github.io/outage-poc/` (visual) · TM probe path `/outage-poc/health` |
| `<fallback-health-url>` | Alex / Naomi | `https://publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/` |
| Body fingerprint (primary) | Alex's site `<meta>` tag | `primary-github-pages` |
| Body fingerprint (fallback) | Alex's site `<meta>` tag | `fallback-swa` |

If Alex deviates from the fingerprint strings above, edit the `FP_PRIMARY` and
`FP_FALLBACK` constants at the top of `scripts/probe.sh`.

---

## 7. See also

- [`RUNBOOK.md`](RUNBOOK.md) — step-by-step canonical demo for Jim.
- [`scripts/`](scripts/) — chaos and probe scripts.
- [`../docs/architecture.md`](../docs/architecture.md) — design + RTO derivation.
