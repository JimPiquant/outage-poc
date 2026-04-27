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
