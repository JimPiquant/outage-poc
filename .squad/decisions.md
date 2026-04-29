# Squad Decisions

## 2026-04-27 — Primary stand-in is live on GitHub Pages

**Author:** Alex (Static Site Developer)  
**Date:** 2026-04-27  
**Status:** Done — Naomi & Amos can wire infra against real URLs.

### Debranding

- Removed "Publix" from user-facing content: `index.html` title/H1, `404.html` title, `README.md` prose. Verified: 0 remaining hits. Committed as `chore(primary): remove brand name from public site`, pushed, live page confirmed.

### Live URLs

| Purpose | URL | HTTP status (verified 2026-04-27) |
|---|---|---|
| Repo | <https://github.com/JimPiquant/outage-poc> (public) | n/a |
| Site root | <https://jimpiquant.github.io/outage-poc/> | **200** |
| Health (extension) | <https://jimpiquant.github.io/outage-poc/health.html> | **200** |
| Health (clean) | <https://jimpiquant.github.io/outage-poc/health> | **200** (GH Pages auto-resolves) |

### How it's published

- Repo: `JimPiquant/outage-poc` (public, GitHub Pages enabled with `build_type=workflow`).
- Workflow: `.github/workflows/pages.yml` uploads `sites/primary/` as the Pages artifact on every push to `main` that touches that directory.
- First deploy succeeded in ~17s; subsequent edits to `sites/primary/**` will auto-redeploy.

### ⚠️ Caveats Naomi & Amos need to know

1. **It's a project Pages site, not a user site.** Content lives under the `/outage-poc/` subpath. There is no way to serve it at the apex of `jimpiquant.github.io` without renaming the repo to `jimpiquant.github.io` (and we're not doing that).
2. **TM/AFD origin hostname** = `jimpiquant.github.io` (host only, no scheme, no path). This is what goes into `primaryOriginHostname` and what Traffic Manager's `externalEndpoint.target` should resolve.
3. **Probe path MUST include the subpath.** A probe to `/health` against `jimpiquant.github.io` will hit GitHub's apex (404). The correct probe path is **`/outage-poc/health`** (or `/outage-poc/health.html` — both 200). I changed the `probePath` default in `infra/main.bicepparam` from `/health` → `/outage-poc/health` accordingly.
4. **HTTPS is enforced** by GitHub Pages — TM/AFD must probe on **HTTPS:443**. HTTP requests get a 301.
5. **Host header sensitivity:** GitHub Pages routes by `Host: jimpiquant.github.io`. AFD origins must forward this host header (don't rewrite to a custom host) or the origin will return 404. Same applies to any synthetic probe.
6. **First-deploy delay** was negligible (~30s end-to-end), but content updates can lag ~1–2 min behind the push. Not a problem for steady-state probes.

### Parameter values Naomi should now use

```bicep
// infra/main.bicepparam (already updated by Alex)
param primaryOriginHostname = 'jimpiquant.github.io'
param probePath              = '/outage-poc/health'
```

The `infra/README.md` parameter table and "Updating the primary origin hostname" section are updated to match.

### What's NOT decided here

- Custom domain (`status.publix.com` etc.) — still optional per Jim's earlier directive.
- Fallback site is still scaffolded under `sites/fallback/` and will live on Azure SWA per Holden's architecture; not published to Pages.

---

## 2026-04-27 — Post-Deploy Actions

### 2026-04-27T18:47:23Z: Resource group rename — `publix-poc-rg` → `rg-publix-poc`

**By:** Naomi (Cloud Infrastructure Engineer)  
**Status:** Applied

#### Change

Renamed the deployment resource group everywhere it appears in the authored scaffold:

| File | Change |
|------|--------|
| `infra/README.md` | All 8 occurrences of `publix-poc-rg` → `rg-publix-poc` (`az group create/delete`, `what-if`, `deployment group create/show` examples). |

No `.bicep` / `.bicepparam` files reference the RG name — RG is a CLI/deploy-time concern, not a template-time one. No parameter defaults needed updating.

#### Verification

- `grep -rn "publix-poc-rg" infra/ docs/` → zero hits.
- `grep -rn "rg-publix-poc" infra/ docs/` → 8 hits in `infra/README.md` (all expected).
- `az bicep build --file infra/main.bicep` → clean (no warnings, no errors).

#### Rationale

`rg-<workload>` follows the Azure Cloud Adoption Framework abbreviation prefix convention. Aligns the POC with standard naming if it ever graduates beyond a demo.

---

## 2026-04-27 — Phase 1+2 Decisions (Merged from Inbox)

### 2026-04-27T18:32:30Z: Failover Test Plan + Chaos Scripts

**By:** Amos (Tester / Chaos)  
**Status:** Authored — execution blocked on Naomi (infra deployed) and Alex (sites live with `/health` fingerprint).

#### What I delivered

- `tests/README.md` — full test plan: goals, pre-conditions, 6-scenario matrix, RTO math, manual-chaos instructions.
- `tests/RUNBOOK.md` — step-by-step canonical "kill primary, watch failover, restore primary" demo for Jim.
- `tests/scripts/probe.sh` — timestamped probe of TM FQDN, parses origin fingerprint from response body.
- `tests/scripts/break-primary.sh` — disables primary TM endpoint via `az`.
- `tests/scripts/restore-primary.sh` — re-enables it.
- `tests/scripts/health-check.sh` — curls both `/health` URLs, exits non-zero if either != 200.

All scripts are `chmod +x`, `set -euo pipefail`, parameterized (no hardcoded hostnames), syntax-checked.

#### RTO budget I'm enforcing

From `docs/architecture.md` §3.4:

```
detection      = (3 × 30s) + 10s            = 100 s
dns_propagation = 60s TTL + 0–60s resolver  = 60–120 s
RTO            = 160–220 s   (≈ 2.5–4 min)
```

**Pass threshold: 240 s** (architecture upper bound + 20 s grace for clock skew). If we measure > 240 s end-to-end during execution, the architecture claim is wrong and I will file a finding.

#### Test scenarios (matrix)

1. **Baseline** — both healthy, traffic to primary.
2. **Primary 5xx** — disable TM endpoint; expect flip ≤ 240 s.
3. **Primary `/health` 404** — break the health path on the actual origin; exercises full detection window.
4. **Primary unreachable** — disable endpoint OR change target to `does-not-exist.invalid`.
5. **Failback** — re-enable; expect return to primary ≤ 240 s.
6. **DNS TTL** — observe cached-resolver client vs. fresh-resolver client during a flip.

#### What I need from Naomi to actually run

| Thing | Why |
|---|---|
| Resource group name | `break-primary.sh` / `restore-primary.sh` arg |
| TM profile name | same |
| **Primary** TM endpoint name (likely `primary`) | same |
| TM FQDN | `probe.sh` arg |
| AFD endpoint hostname | `health-check.sh` fallback URL |
| Confirmation that primary endpoint is `--type ExternalEndpoints` (not Azure-typed) | hardcoded in break/restore scripts; needs update if she uses a different type |
| TM TTL = 60 s, monitorConfig matches architecture (interval 30, tolerated 3, timeout 10) | otherwise my RTO budget is wrong and I'll renegotiate |

#### What I need from Alex to actually run

| Thing | Why |
|---|---|
| Primary GitHub Pages URL with working `/health` returning 200 | baseline pre-condition |
| Fallback SWA `/health` returning 200 | same |
| Confirmation that BOTH pages emit `<meta name="origin" content="...">` in their HTML — preferably with values `primary-github-pages` and `fallback-swa` | `probe.sh` distinguishes which origin served the request by parsing this tag |
| If he chose different fingerprint strings, document them so I can update `FP_PRIMARY`/`FP_FALLBACK` at the top of `probe.sh` | otherwise probe rows will read `origin-tag=unknown` |

#### Assumptions made (verify before running)

1. **Origin fingerprint:** `<meta name="origin" content="primary-github-pages">` and `..."fallback-swa"` — assumed because Alex's decision file didn't exist at authoring time. `probe.sh` is defensive (falls back to literal substring match on those two strings) but values must be confirmed.
2. **TM endpoint type:** `ExternalEndpoints` for the primary (since GitHub Pages is external). If Naomi uses a different type, update `--type` flag in break/restore scripts.
3. **TM endpoint name** for the primary is `primary`. Trivially overridable (it's a CLI arg).

#### Out of scope (intentionally)

- Load testing the fallback path — POC, not perf validation.
- Multi-region testing — single-region SWA per architecture decision.
- Custom domain / cert testing — Jim deferred custom domain to Phase 4.

**Next action when infra exists:** Jim populates the `export` block at the top of `tests/RUNBOOK.md` §0 and runs the steps in order. Total demo wall-clock: ~12–15 min.

---

### 2026-04-27T18:32:30Z: Sites + SWA deploy workflow — Alex

**By:** Alex (Static Site Developer)  
**Status:** Authored — not deployed.

#### What shipped

- `sites/primary/` — GitHub Pages stand-in (green theme, banner, render timestamp, `meta name="origin" content="primary-github-pages"`).
- `sites/fallback/` — Azure Static Web App (amber theme, "operating in fallback mode" banner, `meta name="origin" content="fallback-swa"`).
- `sites/fallback/staticwebapp.config.json` — exposes `/health` (rewrite to `/health.html`) and forces `Content-Type: text/plain`.
- `.github/workflows/deploy-swa.yml` — push-to-main + workflow_dispatch, `Azure/static-web-apps-deploy@v1`, `app_location: sites/fallback`, no build, no API. Reads secret `AZURE_STATIC_WEB_APPS_API_TOKEN`.

#### `/health` approach picked

| Site | Implementation | Probe path Naomi must use |
|------|----------------|--------------------------|
| Primary (GitHub Pages) | Plain `health.html` file (no rewrites possible on GH Pages) | `/<repo>/health.html` — i.e. `/publix/health.html` |
| Fallback (SWA) | `health.html` file + `routes` rule rewriting `/health` → `/health.html` with `text/plain` | `/health` (preferred) or `/health.html` |

Body for both is uppercase plain text: `OK - primary` / `OK - fallback`.

#### ⚠️ GitHub Pages subpath gotcha (handoff to Naomi)

Project-repo Pages publish at `https://<owner>.github.io/<repo>/` — the repo
name is part of every URL path. So Traffic Manager's primary endpoint must
probe **`/publix/health.html`**, not `/health.html`. The hostname is
`<owner>.github.io`. This stays true unless we move to a custom domain
(skipped for POC) or a `<owner>.github.io` user/org repo.

#### Secret name the workflow expects

`AZURE_STATIC_WEB_APPS_API_TOKEN` — must be added as a GitHub Actions repo
secret after Naomi creates the SWA resource. Token comes from the SWA
resource's "Manage deployment token" pane in the Azure portal. Workflow
will fail loudly until this is set.

#### Things Naomi needs

1. SWA name prefix `publix-poc-*` (per Jim's decision).
2. SWA region: `eastus2`.
3. After SWA exists: copy deployment token → set repo secret → trigger workflow → grab the resulting `*.azurestaticapps.net` hostname for AFD origin config.
4. TM endpoint probe paths above.

---

### 2026-04-27T18:32:30Z: Bicep scaffold for resiliency POC

**By:** Naomi (Cloud Infrastructure Engineer)  
**Status:** Proposed → ready for review

#### Summary

Authored Phase 1 + Phase 2 Bicep scaffold under `infra/`. Compiles cleanly via `az bicep build` (CLI v2.85.0). No deploy executed.

#### Module structure

| File | Scope | Purpose | Outputs |
|------|-------|---------|---------|
| `infra/main.bicep` | `resourceGroup` | Composes the three modules. Caller pre-creates the RG. | `swaHostname`, `afdHostname`, `trafficManagerFqdn` |
| `infra/main.bicepparam` | — | Default params (publix-poc, eastus2, /health, TTL 60). | — |
| `infra/modules/swa.bicep` | RG | SWA Free SKU. **No repo binding** — content deploy is decoupled (Alex's domain). | `defaultHostname`, `id` |
| `infra/modules/afd.bicep` | RG | AFD Standard: profile + endpoint + originGroup + origin (SWA) + route. HTTPS-only forwarding. | `endpointHostname`, `profileId` |
| `infra/modules/trafficmanager.bicep` | RG | TM Priority routing, two `externalEndpoints`. Probe per architecture §3.3. | `fqdn`, `id` |

#### Output flow between modules

```
swa.defaultHostname  ──►  afd.originHostname (origin + originHostHeader)
afd.endpointHostname ──►  tm.fallbackHostname (Priority 2)
param primaryOriginHostname ──►  tm.primaryHostname (Priority 1)
```

#### Parameterized vs hardcoded

**Parameters (overridable):** `namePrefix`, `location`, `primaryOriginHostname`, `tmDnsRelativeName`, `probePath`, `tmTtlSeconds`.

**Hardcoded (from architecture doc — change in code if architecture changes):**
- TM probe: HTTPS / port 443 / interval 30s / timeout 10s / tolerated failures 3 / status 200 only.
- AFD load balancing: sampleSize 4, successfulSamplesRequired 3, additionalLatency 50ms.
- Tags: `project=publix-poc, owner=jim, purpose=resiliency-poc`.
- AFD SKU: `Standard_AzureFrontDoor`.
- SWA SKU: `Free`.

#### Deviations from architecture doc

None. Specifically:
- Probe values match §3.3 exactly.
- Both TM endpoints are `externalEndpoints` (GH Pages must be external; AFD isn't a first-class TM Azure endpoint type — external w/ FQDN is the documented path).
- Custom domain skipped per locked decision.

#### Notes for the team

- **Blocks on Alex:** `primaryOriginHostname` ships as `<owner>.github.io` placeholder. Update `main.bicepparam` (or pass `-p primaryOriginHostname=…` on the CLI) once GH Pages is live.
- **TM DNS name collision risk:** `publix-poc-tm.trafficmanager.net` must be globally unique. If taken at deploy time, change `tmDnsRelativeName` and re-run `what-if`.
- **No deploy was executed.** Apply path is documented in `infra/README.md`.

---

### 2026-04-27T18:25:00Z: User decisions on architecture open questions

**By:** Jim Welch (via Copilot)  
**What:** Accepted all of Holden's recommendations:
- Custom domain: **Skip** — use Azure hostnames for the POC.
- AFD SKU: **Standard**.
- Primary Azure region: **eastus2**.
- Non-Azure primary stand-in: **GitHub Pages**.
- Resource naming prefix: **publix-poc**.
- Resource group: **New RG** (clean teardown).
**Why:** Confirmed via ask_user form. These unblock Naomi (Bicep scaffold) and Alex (primary stand-in + fallback site).

---

## 2026-04-27 — Azure POC Deployment — Naomi

**Status:** ✅ Deployed successfully.

**Deployment:** `publix-poc-20260427-221459` in `rg-publix-poc` (eastus2). Provisioning state: Succeeded.

**Resources created (7):**
| Type | Name |
|---|---|
| `Microsoft.Web/staticSites` | `publix-poc-swa` |
| `Microsoft.Cdn/profiles` | `publix-poc-afd` (Standard_AzureFrontDoor) |
| `Microsoft.Cdn/profiles/afdEndpoints` | `publix-poc-ep` |
| `Microsoft.Cdn/profiles/originGroups` | `publix-poc-og` |
| `Microsoft.Cdn/profiles/originGroups/origins` | `publix-poc-origin-swa` |
| `Microsoft.Cdn/profiles/afdEndpoints/routes` | (default route to SWA origin) |
| `Microsoft.Network/trafficmanagerprofiles` | `publix-poc-tm` (Priority routing, 2 external endpoints) |

**Output FQDNs:**
- **SWA hostname:** `white-water-098b0170f.7.azurestaticapps.net`
- **AFD endpoint hostname:** `publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net`
- **Traffic Manager FQDN (user entry point):** `publix-poc-tm.trafficmanager.net`
- **Primary (non-Azure, GH Pages):** `jimpiquant.github.io` → `https://jimpiquant.github.io/outage-poc/` (200 OK)

**Smoke checks passed:**
- TM DNS resolves to primary (GH Pages) and is healthy. ✅
- Primary origin responds 200. ✅
- SWA and AFD return 404 (expected — awaiting Alex's deploy-swa.yml to populate content).

**Secrets & handoffs:**
- SWA deployment token retrieved and stored as GH Actions secret `AZURE_STATIC_WEB_APPS_API_TOKEN` on `JimPiquant/outage-poc` (not written to disk).
- Triggered `deploy-swa.yml` (run `25022553077`) to populate fallback site.

**Next steps:**
1. Wait for `deploy-swa.yml` to finish; re-curl SWA and AFD endpoints to confirm 200.
2. Amos points probes at `publix-poc-tm.trafficmanager.net` for failover tests.

**Notes:**
- Custom domain not in scope for POC.
- SWA token rotation: `az staticwebapp secrets reset-api-key` → re-`gh secret set`.

---

## Active Decisions

### 2026-04-27T18:17:29Z: Architecture Proposal — Option #1 (TM + AFD + SWA)

**By:** Holden (Lead / Azure Architect)  
**Status:** Proposal — awaiting user decisions

#### Architectural Choices Made

1. **Pattern:** Option #1 from Azure Architecture Blog — Traffic Manager as DNS-based failover brain, AFD serves fallback path only.
2. **Failover point:** Traffic Manager (DNS layer), not AFD origin failover.
3. **Primary:** Non-Azure external site (GitHub Pages or Cloudflare Pages recommended for POC).
4. **Fallback:** AFD Standard → Azure Static Web App.
5. **Health probes:** TM probes both endpoints; HTTPS/443, 30s interval, 3 tolerated failures.
6. **RTO target:** ~2–4 minutes (configurable via probe interval and DNS TTL).
7. **Failback:** Automatic when primary recovers.

#### Questions for Jim (blocking Naomi/Alex)

| # | Question | Recommendation | Notes |
|---|----------|----------------|-------|
| 1 | **Custom domain?** | Skip for POC | Adds complexity; Azure hostnames sufficient for demo |
| 2 | **AFD SKU?** | Standard | Premium not needed for SWA origin |
| 3 | **SWA region?** | `eastus2` | Standard US region, good availability |
| 4 | **Non-Azure primary stand-in?** | GitHub Pages or Cloudflare Pages (free) | Easy to control, free, simulates external site |
| 5 | **Resource naming prefix?** | Need input | e.g., `publix-poc-*` |
| 6 | **New or existing Resource Group?** | Need input | Recommend new RG for clean teardown |

#### What This Unblocks

- **Naomi:** Can start Bicep scaffold once naming/RG decisions are made.
- **Alex:** Can create the non-Azure primary stand-in and fallback site content in parallel.
- **Amos:** Blocked until Phase 2 infrastructure is deployed.

#### Full Details

See `docs/architecture.md` for topology diagrams, probe math, RTO calculations, and phased build plan.

---

### 2026-04-27T18:16:34Z: User directive — IaC choice

**By:** Jim Welch (via Copilot)  
**What:** Use Bicep for all Azure infrastructure provisioning in this POC.  
**Why:** User request — captured for team memory.

---

### 2026-04-27T18:16:34Z: User directive — Custom domain optional

**By:** Jim Welch (via Copilot)  
**What:** Jim has a domain name available. Use it only if it makes the implementation simpler or more realistic — it is NOT a requirement. Naomi/Holden may decide based on implementation cost vs. demonstration value.  
**Why:** User request — captured for team memory.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

---

## 2026-04-28 — Failover Demo Results — Scenario #1 (TM endpoint disable)

**Author:** Amos (Tester / Chaos Engineer)  
**Date:** 2026-04-28  
**Deployment under test:** publix-poc-20260427-221459 (Naomi, 2026-04-27)  
**Evidence log:** `tests/results/probe-2026-04-28-failover.log`

### Verdict: **PASS** (with caveats — see Anomalies)

| Metric | Measured | RTO Target | Result |
|---|---|---|---|
| Time-to-failover (break → first stable fallback row) | **18 s** | ≤ 240 s | ✅ PASS (13× faster) |
| Time-to-failback (restore → first primary row)       | **28 s** | ≤ 240 s | ✅ PASS (8.5× faster) |
| Errors during transition (no-endpoint / 5xx)         | **0**    | minimize | ✅ |

### Pre-flight status

| Check | Result | Notes |
|---|---|---|
| Subscription `ME-MngEnvMCAP866439-jimwelch-1` active | ✅ | `az account show` |
| TM profile `publix-poc-tm` reachable | ✅ | TTL=60s, monitor path `/outage-poc/health`, interval=30s, tolerated failures=3 |
| Primary endpoint (`primary-external` → `jimpiquant.github.io`) | ✅ Enabled / Online (priority 1) | |
| Fallback endpoint (`fallback-afd` → `publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net`) | ⚠️ Enabled / **Degraded** (priority 2) | See Anomaly #1 |
| SWA direct (`white-water-098b0170f.7.azurestaticapps.net/health.html`) | ✅ HTTP 200 | content live |
| AFD direct (`publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/health[.html]`) | ✅ HTTP 200, content-length 14 | |
| Primary direct (`jimpiquant.github.io/outage-poc/health.html`) | ✅ HTTP 200 | |
| Baseline DNS resolution of TM FQDN | ✅ CNAME → `jimpiquant.github.io.` | 3/3 ticks |

**Note on RUNBOOK staleness:** runbook still says `RG=publix-poc-rg` and `PRIMARY_EP=primary`; live infra is `rg-publix-poc` and `primary-external`. Recommend Naomi/Sam patch RUNBOOK §0.

### Endpoints used

- TM profile: `publix-poc-tm`
- Resource group: `rg-publix-poc`
- Primary endpoint name: **`primary-external`**
- Fallback endpoint name: `fallback-afd`

### Timeline (UTC, ISO 8601)

| Event | Timestamp |
|---|---|
| Probe started | 2026-04-28T18:26:36Z |
| **BREAK issued** (`az ... --endpoint-status Disabled`) | **2026-04-28T18:26:38Z** |
| Break ack from ARM | 2026-04-28T18:26:40Z |
| Last primary CNAME observed | 2026-04-28T18:26:51Z |
| **First fallback CNAME observed** | **2026-04-28T18:26:56Z** |
| Brief DNS-cache flap back to primary (1 tick) | 2026-04-28T18:27:06Z |
| Steady-state fallback locked in | 2026-04-28T18:27:12Z onward |
| **RESTORE issued** (`az ... --endpoint-status Enabled`) | **2026-04-28T18:29:01Z** |
| Restore ack from ARM | 2026-04-28T18:29:04Z |
| **First primary CNAME observed** | **2026-04-28T18:29:29Z** |
| Brief DNS-cache flap back to fallback (1 tick) | 2026-04-28T18:29:34Z |
| Steady-state primary locked in | 2026-04-28T18:29:39Z onward |

**Computed:**
- Time-to-failover = 18:26:56 − 18:26:38 = **18 seconds**
- Time-to-failback = 18:29:29 − 18:29:01 = **28 seconds**

### Anomalies / Findings

#### 1. Fallback endpoint is permanently Degraded (probe path mismatch) — **MEDIUM**
TM profile probes `/outage-poc/health` against both endpoints. AFD's origin (the SWA)
serves `/health` (and `/health.html`), **not** `/outage-poc/health`. Result:
`fallback-afd` shows `EndpointMonitorStatus=Degraded` permanently, even though the
AFD endpoint itself returns HTTP 200 on `/health.html` end-to-end.

**Why we still PASSed:** TM priority routing has an "all-degraded last-resort"
behavior — when the only enabled endpoint is Degraded, TM serves it anyway rather
than return NXDOMAIN. The cutover worked. But this is fragile:
- `AlwaysServe=Disabled` on fallback removes the safety net for the case where
  TM probes are flapping for unrelated reasons.
- Operationally we're relying on undocumented last-resort behavior, not on the
  intended priority-failover semantics.

**Recommendation:** Either (a) make the SWA serve `/outage-poc/health`
(easiest — Sam/Alex), or (b) reconfigure TM monitor to use `/health.html` AND
add `/outage-poc/health.html` to GH Pages, or (c) set `AlwaysServe=Enabled` on
`fallback-afd`. Option (a) is cleanest.

#### 2. `tests/scripts/probe.sh` is broken for this architecture — **MEDIUM**
The script does an HTTPS GET against the TM FQDN with `Host: <tm-fqdn>`, but
neither origin (GH Pages `*.github.io` cert, AFD `*.azurefd.net` cert) presents
a SAN matching `publix-poc-tm.trafficmanager.net`. Every row came back
`http-status=000 curl-fail` and `origin-tag=unknown` even at baseline.

**Workaround used in this run:** built `.work/dns-probe.sh` (DNS-CNAME-only
probe) — failover signal is the CNAME chain, which is the truth source TM is
actually publishing. Evidence log uses this format.

**Recommendation:** Either rewrite `probe.sh` to dig the CNAME and curl the
*resolved* hostname (so SNI matches), or stand up a custom domain (e.g.
`publix-poc.<somedomain>`) on TM with matching certs on both origins. For demo
purposes the DNS probe is sufficient.

#### 3. Brief DNS-cache flaps during cutover/cutback — **LOW**
On both transitions we saw a single 5-second-tick flap back to the previous
endpoint after the initial flip (18:27:06Z and 18:29:34Z). This is normal Google
8.8.8.8 cache behavior across resolver pool members and is well within the
60-second TTL window. No client impact.

### Hygiene

- ✅ Primary endpoint re-enabled at end of test (`Status=Enabled`, `Monitor=Online`, verified via `az network traffic-manager endpoint show`).
- ✅ No other Azure resources mutated.
- ✅ Evidence log saved to `tests/results/probe-2026-04-28-failover.log`.

### Reviewer gate

I'd accept this as a **demoable failover** for Jim's audience, with the asterisk
that we should not advertise the fallback as "Healthy in TM" until Anomaly #1
is fixed. Recommend Sam/Alex address Anomaly #1 and Anomaly #2 before the next
external demo.

## 2026-04-28 — TM probe path fix (no Bicep change, SWA route added)

**Author:** Naomi (Cloud Infrastructure Engineer)  
**Date:** 2026-04-28  
**Status:** ✅ Complete — Infra unchanged, SWA route deployed, TM profile now `Online`.

### Problem

Traffic Manager profile `publix-poc-tm` probes `/outage-poc/health` (profile-wide setting). Primary GH Pages endpoint serves it; SWA fallback did not, returning 404. Marked fallback `Degraded`, breakage visible in `monitorConfig.profileMonitorStatus`.

### Solution

**Option B: SWA learns the probe path (no Bicep change)**  
The probe contract is `/outage-poc/health` and both origins must serve it over HTTPS with HTTP 200. GH Pages is locked to project-site subpath (`/outage-poc/`). SWA now adds a route rewrite for `/outage-poc/health` → `/health.html` in `sites/fallback/staticwebapp.config.json`.

**Rationale:** Zero infra change, no redeploy risk, respects GH Pages subpath constraint, keeps probe path semantically aligned with primary's actual URL surface.

### Live verification (2026-04-28)

| URL | Result |
|---|---|
| `https://jimpiquant.github.io/outage-poc/health` | **200** ✅ primary |
| `https://publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/health` | **200** ✅ fallback (legacy path) |
| `https://publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/outage-poc/health` | **404 / not served** ❌ bug at time of decision |

**Contract for Alex:** Probe path is `/outage-poc/health` and stays that way. Both origins must return HTTP 200 / `Content-Type: text/plain` on that exact path over HTTPS.

### Next steps

SWA route commit required by Alex.

---

## 2026-04-28 — probe.sh fixed (TLS + Host-header bug)

**Author:** Alex (Static Site Developer)  
**Date:** 2026-04-28  
**Status:** ✅ Done — committed, pushed, all smoke tests 200.

### Root cause

Old `tests/scripts/probe.sh` used `curl --resolve <tm-fqdn>:443:<ip>` forcing SNI = `publix-poc-tm.trafficmanager.net`. Neither origin cert (`*.github.io`, `*.azurefd.net`) has that name in SAN, so every TLS handshake failed (Amos's demo: `http-status=000` every iteration).

### Fix

`probe.sh` now:
1. **Chases the TM CNAME chain** with `dig`, resolving to terminal hostname (e.g. `jimpiquant.github.io` today).
2. **Curls directly** against that resolved hostname with default SNI — cert + Host both match the real origin.
3. **Path auto-detects per origin** (`/outage-poc/` for `*.github.io`, `/` for `*.azurefd.net` / `*.azurestaticapps.net`).
4. **Never aborts on non-2xx** — every iteration prints a row (captures cutover window).
5. **Output column:** `resolved-ip` → `resolved-host` (cleaner cutover signal).

`<meta name="origin">` parsing unchanged (verified).

### Smoke test

```
$ ./tests/scripts/probe.sh publix-poc-tm.trafficmanager.net 6 5
time                    resolved-host                     origin-tag              http-status
2026-04-28T21:41:29Z    jimpiquant.github.io              primary-github-pages    200
2026-04-28T21:41:35Z    jimpiquant.github.io              primary-github-pages    200
2026-04-28T21:41:40Z    jimpiquant.github.io              primary-github-pages    200
2026-04-28T21:41:45Z    jimpiquant.github.io              primary-github-pages    200
2026-04-28T21:41:50Z    jimpiquant.github.io              primary-github-pages    200
2026-04-28T21:41:56Z    jimpiquant.github.io              primary-github-pages    200
```

All 6 rows: HTTP 200, fingerprint `primary-github-pages`. Commit `872879a`. Amos's canonical probing tool is now functional.

### Sibling scripts

Reviewed `break-primary.sh`, `restore-primary.sh`, `health-check.sh` — none has the Host-header bug. No changes needed.

---

## 2026-04-28 — SWA `/outage-poc/health` route deployed; TM `fallback-afd` flipped Online

**Author:** Alex (Static Site Developer)  
**Date:** 2026-04-28  
**Status:** ✅ Done — committed, deployed, SWA + AFD + TM all verified.

### Change

`sites/fallback/staticwebapp.config.json` — added route entry:

```jsonc
{
  "route": "/outage-poc/health",
  "rewrite": "/health.html",
  "headers": {
    "content-type": "text/plain; charset=utf-8",
    "cache-control": "no-store"
  }
}
```

Per Naomi's contract (`naomi-tm-probe-path-fix.md`): TM probes `/outage-poc/health`; GH Pages primary can only serve under `/outage-poc/`; SWA must learn the path. No infra change. Original `/health` route unchanged.

### Pipeline

- Commit `f5f3f8e` — `feat(swa): serve /outage-poc/health for TM probe contract`.
- `deploy-swa.yml` run `25079253392` — `success` in 55s.

### Smoke test (post-deploy)

| Endpoint | URL | Status |
|---|---|---|
| **SWA direct** | `https://white-water-098b0170f.7.azurestaticapps.net/outage-poc/health` | **200** ✅ |
| **AFD** | `https://publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net/outage-poc/health` | **200** ✅ |

Both include `cache-control: no-store` and `x-origin: fallback-swa`. Note: content-type came back `text/html` (SWA rewrite quirk; body is plain text, not a blocker for TM which only checks status code).

### TM status (after one probe window, ~3 min post-deploy)

```
$ az network traffic-manager profile show -g rg-publix-poc -n publix-poc-tm \
    --query "monitorConfig.profileMonitorStatus" -o tsv
Online

$ az network traffic-manager endpoint list -g rg-publix-poc --profile-name publix-poc-tm -o table
EndpointMonitorStatus  Name              Priority  Target
Online                 primary-external  1         jimpiquant.github.io
Online                 fallback-afd      2         publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net
```

`fallback-afd` flipped `Degraded` → `Online`. Profile is `Online`. Naomi's contract satisfied. Failover demo ready with both endpoints green.


---

## 2026-04-28 — Failover demo: clean-evidence iteration (Finding #3 lifecycle)

**Participants:** Amos (SRE), Alex (Sites/Frontend)  
**Dates:** 2026-04-28 (21:53Z–22:21Z, 28 min cycle)  
**Status:** ✅ CLOSED — demo-ready evidence captured.

### Executive summary

Finding #3 (probe.sh cannot classify AFD fallback leg) filed during Amos's broken-instrument rerun, diagnosed and fixed by Alex in same session, closed by Amos's final clean-evidence rerun. Both engineers in good standing — one filed a legitimate instrument bug, the other corrected a misdiagnosis (Bug B) and fixed both issues correctly. Final timings: failover 38s, failback 77s (both ≪ 240s RTO). Tag distribution 28/24/8 with zero content-classification failures (all 8 unknowns are transient curl-fails).

### Timeline of the iteration

1. **21:53Z — Amos rerun (broken instrument)** (`.squad/decisions/inbox/amos-failover-demo-rerun.md`)
   - Scenario #1 (TM endpoint disable/re-enable) with Alex's `probe.sh` rewrite (commit `872879a`) + SWA route (commit `f5f3f8e`).
   - **Verdict:** Failover/failback **PASS** (46s/96s sustained), but demo-evidence **FAIL** — probe reads `unknown/404` (or `curl-fail`) for entire fallback window (31 of 60 rows).
   - **Cause identified:** Two bugs in `probe.sh` — Bug A: CNAME chase walked past the AFD endpoint (`*.azurefd.net`) into shared-infra label (`*.t-msedge.net`); Bug B (claimed): AFD only serves `/outage-poc/...` and `/` returns 404.
   - **Finding #3 filed** — `probe.sh` cannot fingerprint AFD fallback leg; owner Alex with input from Naomi (path contract).
   - Evidence log: `tests/results/probe-2026-04-28-failover-clean.log`

2. **22:10Z — Alex probe fix** (`.squad/decisions/inbox/alex-probe-afd-leg-fix.md`)
   - **Bug A (confirmed real)** — `resolve_terminal_host` changed: now walks CNAME chain top-down with single-step `dig +short CNAME` lookups, stops at first hostname matching service-identity pattern (`*.github.io`, `*.azurefd.net`, `*.azureedge.net`, `*.azurestaticapps.net`). Capped at 10 hops.
   - **Bug B (misdiagnosis)** — Empirically tested and **rejected**. AFD root `/` returns `HTTP/2 200` with correct `<meta name="origin" content="fallback-swa">`. Amos's prior claim of 404 was based on `/outage-poc/` which SWA overrides with a 404 page that still carries the meta tag — this was the bear trap. Correct choice: `path_for_origin` returns `/` for `*.azurefd.net` (empirically verified).
   - Commit: `b07fad5` (pushed to `origin/main`).
   - **Smoke tests** — Primary baseline 6/6 200 (`primary-github-pages`, host `jimpiquant.github.io`). Fallback 5/6 200 (`fallback-swa`, AFD endpoint hostname), 1 transient `curl-fail` (acceptable TLS/socket flake). **Bug A fixed.** Path for AFD confirmed to be `/` by direct curl; Bug B's premise was wrong but the fix is right anyway.

3. **22:21Z — Amos final clean-evidence rerun** (`.squad/decisions/inbox/amos-failover-demo-final.md`)
   - Scenario #1 again with Alex's twice-fixed probe (commit `b07fad5`) + SWA (commit `f5f3f8e`).
   - **Verdict:** Failover/failback **PASS** (38s/77s sustained). Demo-evidence **PASS** — 28/24/8 tag distribution, all 8 `unknown` are transient `curl-fail` (0 content-classification failures).
   - **Pre-flight validation** — Alex's path claim empirically verified again: AFD `/` = 200 + correct meta tag; AFD `/outage-poc/` = 404 (SWA page with meta tag embedded).
   - **Finding #3: CLOSED** — both bugs confirmed corrected: resolved-host never slides into `*.t-msedge.net`, every fallback row reads `publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net` (the AFD endpoint). Path `/` for `*.azurefd.net` confirmed correct.
   - Evidence log: `tests/results/probe-2026-04-28-failover-final.log`

### Tag distribution comparison: all 3 runs

| run | date | scenario | primary-github-pages | fallback-swa | unknown | curl-fail | notes |
|---|---|---|---|---|---|---|---|
| `probe-2026-04-28-failover.log` | 2026-04-27 (ref) | DNS-only probe, TM-degraded last-resort fallback | 30 | 30 | 0 | 0 | Baseline (no real cutover probing) |
| `probe-2026-04-28-failover-clean.log` | 2026-04-28T21:53Z (this session, rerun 1) | HTTP+meta probe; bug A + B active | 29 | 0 | 31 (all classifier bugs) | many | CNAME walked into `*.t-msedge.net`; path bug compounded |
| **`probe-2026-04-28-failover-final.log`** | **2026-04-28T22:21Z (this session, rerun 2)** | **HTTP+meta probe; both bugs fixed** | **28** | **24** | **8 (all transient curl-fail)** | **8** | **Zero content-classification failures. Demo-ready.** |

### Why the walltimes improved (broken → final)

- **Failover:** 46s → 38s (8s faster). Real probe-driven cutover with working AFD leg.
- **Failback:** 96s → 77s (19s faster). Same reason; also cleaner transient resolution.

The middle run was slower because the broken probe could not see the fallback, introducing measurement noise. With both legs fully instrumented and the AFD endpoint correctly identified, TM's priority routing becomes visible in the probe window.

### Findings filed and disposition

| finding | issue | filed-by | owner | status | disposition |
|---|---|---|---|---|---|
| #1 | TLS + Host-header bug in `probe.sh` v1 | Amos | Alex | ✅ Done | Fixed by commit `872879a` (CNAME chase + real SNI) |
| #2 | SWA must learn `/outage-poc/health` for TM probe contract | Amos | Alex | ✅ Done | Fixed by commit `f5f3f8e` (SWA route added); TM fallback flipped Online |
| #3 | Probe cannot classify AFD fallback leg (CNAME walks past endpoint + path misconception) | Amos | Alex | ✅ **CLOSED** | Fixed by commit `b07fad5` (service-identity CNAME walk + empirical path verification); all evidence verified in final run |

### Next steps

Failover demo is now demo-ready. Clean evidence captured, both endpoints Online and classified correctly, transition visible end-to-end. No open findings. Ready for external/management presentation.

---

## 2026-04-29 — Runbook refresh — post-validation

**Author:** Alex (Sites/Frontend)  
**Date:** 2026-04-29  
**Decision file:** `.squad/decisions/inbox/alex-runbook-refresh.md`  
**Commits:** `7cfa7e6` (code), `23c6099` (history)  
**Status:** ✅ MERGED — runbooks ready for demo handoff.

### Summary

Refreshed `tests/RUNBOOK.md` and `tests/README.md` post-validation. All stale references fixed: RG name (`rg-publix-poc`), primary endpoint (`primary-external`), AFD path quirk documented (`/` returns 200), probe script contract codified, and measured RTO evidence captured (failover 38s / failback 77s, last validated 2026-04-29). Findings #1, #2, #3 all marked CLOSED with commit references. Next operator can run the failover demo from a cold start without tribal knowledge.

### Files touched

- `tests/RUNBOOK.md` — primary refresh (11 stale items fixed; Findings history table added).
- `tests/README.md` — cross-checked and fixed stale infra references.

### Validated state

- RG: `rg-publix-poc` (eastus2).
- Primary endpoint: `primary-external` (GitHub Pages).
- AFD endpoint: `publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net` — AFD `/` serves 200 with correct meta tag; probe path profile-wide `/outage-poc/health` routed to SWA.
- Measured RTO: **38s failover / 77s failback** (budget 240s). Evidence log: `tests/results/probe-2026-04-28-failover-final.log` (28 primary / 24 fallback / 8 transient curl-fail; zero content-classification failures).

### Findings status

| # | Issue | Closed | Ref |
|---|---|---|---|
| #1 | TLS + Host-header bug in probe.sh v1 | ✅ | `872879a` |
| #2 | SWA must learn `/outage-poc/health` for TM probe | ✅ | `f5f3f8e` |
| #3 | Probe cannot classify AFD fallback leg | ✅ | `b07fad5` |
