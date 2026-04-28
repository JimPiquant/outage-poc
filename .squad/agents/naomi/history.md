# Project Context

- **Owner:** Jim Welch
- **Project:** publix — Azure resiliency POC. Demonstrates failover from a non-Azure primary website to an Azure Static Web App (SWA) using Azure Traffic Manager (priority routing) in front of Azure Front Door. Reference design: techcommunity Azure Architecture Blog "Resiliency patterns for Azure Front Door — Field Lessons" Option #1.
- **Stack:** Azure (Front Door, Traffic Manager, Static Web Apps), Bicep (likely), HTML/CSS for the static fallback site, GitHub Actions for SWA deploy.
- **Created:** 2026-04-27

## Learnings

- **2026-04-27:** Architecture proposal delivered in `docs/architecture.md` and `.squad/decisions.md` — lists 6 blocking questions for Jim. Plan unblocks Bicep scaffolding once naming and resource group decisions are confirmed.

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **2026-04-27:** Authored the Phase 1+2 Bicep scaffold under `infra/`. Compiles clean with `az bicep build` (Azure CLI 2.85.0, bundled Bicep). Decisions worth remembering:
  - **Scope:** `resourceGroup` for `main.bicep`. Simpler than subscription-scope and matches the "caller does `az group create`" workflow documented in the README.
  - **Module-per-resource:** `swa.bicep`, `afd.bicep`, `trafficmanager.bicep`. Each module has explicit `@description` outputs that flow into the next module's params (SWA hostname → AFD origin → AFD hostname → TM fallback).
  - **AFD origin:** Used `Microsoft.Cdn/profiles@2024-02-01` (AFD Standard/Premium API). `originHostHeader` MUST equal the SWA `defaultHostname` or SNI/host routing breaks. `enforceCertificateNameCheck: true`.
  - **AFD route:** Needs `dependsOn: [origin]` because the route references the origin group but ARM doesn't infer the origin dependency. Bit me once mentally — added it explicitly.
  - **TM endpoints:** Both must be `externalEndpoints`. GH Pages is non-Azure; AFD is also modeled as external (TM has no first-class AFD endpoint type). Don't waste time hunting for `azureEndpoints` for AFD.
  - **TM probe:** Hardcoded HTTPS/443/30s/10s/3-failures/status-200 to match `docs/architecture.md` §3.3 exactly. Probe path is parameterized (`probePath`, default `/health`).
  - **TM DNS relative name:** Globally unique — `publix-poc-tm.trafficmanager.net`. Will collide if someone else has it; that's a deploy-time discovery, not a compile error.
  - **SWA:** Free SKU, no repo binding. Content deploy is decoupled — Alex pushes via SWA CLI / GH Actions. Keeping IaC and content-deploy separate avoids tangling Bicep with a GH PAT.
  - **Parameters file:** Used `.bicepparam` (typed) instead of legacy JSON parameters. Validated separately with `az bicep build-params`.
  - **Tags:** Single `commonTags` var in `main.bicep` passed into every module — one place to change project/owner/purpose.
  - **No deploy run.** Authoring only per task brief. README documents `what-if` → `create` → `delete` flow.

- **2026-04-27:** Renamed RG `publix-poc-rg` → `rg-publix-poc` (Azure CAF naming convention) in `infra/README.md`. RG name is CLI-time only — no Bicep change needed; `az bicep build` re-verified clean.

- **2026-04-27:** Deployed POC infra to Azure. Deployment name `publix-poc-20260427-221459` in RG `rg-publix-poc` (eastus2, sub `ME-MngEnvMCAP866439-jimwelch-1`). What-if was clean (7 resources, all `+ create`, no surprises). Provisioning state: **Succeeded**. Live FQDNs:
  - **SWA:** `white-water-098b0170f.7.azurestaticapps.net` (resource `publix-poc-swa`)
  - **AFD endpoint:** `publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net` (profile `publix-poc-afd`, endpoint `publix-poc-ep`, OG `publix-poc-og`, origin `publix-poc-origin-swa`)
  - **TM FQDN (user entry point):** `publix-poc-tm.trafficmanager.net`
  - SWA deployment token fetched via `az staticwebapp secrets list` and pushed to GH Actions secret `AZURE_STATIC_WEB_APPS_API_TOKEN` on `JimPiquant/outage-poc`. Token never echoed.
  - Smoke checks: SWA `/health` → 404 (expected, empty SWA), AFD root → 404 (expected, empty origin). TM DNS resolves to `jimpiquant.github.io` → GH Pages IPs (185.199.108-111.153) — confirms Priority 1 primary is healthy and selected. Primary `https://jimpiquant.github.io/outage-poc/` returns 200.
  - Triggered `deploy-swa.yml` (`gh workflow run …` run id 25022553077) so Alex's content lands on the SWA and Amos can run failover tests.
  - **Note for next time:** SWA deployment token is intentionally NOT a Bicep output (would leak in deployment history). Pull it on demand with `az staticwebapp secrets list`.

- **2026-04-28 (Amos failover demo findings):**
  - **TM probe path mismatch (MEDIUM):** Amos discovered that TM profile is configured to probe `/outage-poc/health` on all endpoints, but the fallback SWA only serves `/health` (not `/outage-poc/health`). Result: `fallback-afd` endpoint shows `Degraded` in TM console. The failover still worked via TM's last-resort all-degraded behavior, but the design is fragile. **Action for you:** coordinate with Sam/Alex to either (a) add the `/outage-poc/health` path to SWA config, or (b) update the TM probe path to `/health` and ensure GH Pages also serves `/outage-poc/health` as a fallback. Cleanest is (a).
  - **RUNBOOK staleness:** RUNBOOK.md still references old RG name `publix-poc-rg` and old endpoint names `primary`/`fallback`. Live infra uses `rg-publix-poc` and `primary-external`/`fallback-afd`. **Action for you:** Patch `tests/RUNBOOK.md` §0 to reflect current resource names so Amos (or the external demo person) has canonical instructions.
