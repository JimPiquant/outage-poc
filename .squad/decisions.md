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
