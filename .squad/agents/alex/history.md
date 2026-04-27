# Project Context

- **Owner:** Jim Welch
- **Project:** publix — Azure resiliency POC. Demonstrates failover from a non-Azure primary website to an Azure Static Web App (SWA) using Azure Traffic Manager (priority routing) in front of Azure Front Door. Reference design: techcommunity Azure Architecture Blog "Resiliency patterns for Azure Front Door — Field Lessons" Option #1.
- **Stack:** Azure (Front Door, Traffic Manager, Static Web Apps), Bicep (likely), HTML/CSS for the static fallback site, GitHub Actions for SWA deploy.
- **Created:** 2026-04-27

## Learnings

- **2026-04-27:** Architecture proposal delivered in `docs/architecture.md` and `.squad/decisions.md` — lists 6 blocking questions for Jim. Plan unblocks non-Azure primary stand-in and fallback site content in parallel once naming decisions confirmed.

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **2026-04-27:** Built primary stand-in (`sites/primary/`) for GitHub Pages and fallback (`sites/fallback/`) for Azure SWA. Visual styling intentionally divergent (green vs amber + banners + `meta name="origin"`) so browser tests immediately reveal which origin served. Both pages stamp render time in JS so refresh is visibly observable.
- **2026-04-27:** `/health` choice — **primary uses a plain `health.html` file** (GH Pages has no rewrite engine; folder-style `health/index.html` causes a 301 from `/health` → `/health/` which not all probes follow). **Fallback uses a `staticwebapp.config.json` `routes` rule** rewriting `/health` → `/health.html` with `text/plain`. Net: primary probe path is `/publix/health.html`, fallback probe path is `/health` (or `/health.html`).
- **2026-04-27:** ⚠️ GitHub Pages **subpath gotcha** for Naomi: project-repo Pages publish under `https://<owner>.github.io/<repo>/`, so the TM primary probe path must include `/publix/`. Skipping custom domain (per Jim's decision) means we live with the subpath. Documented in `sites/primary/README.md`.
- **2026-04-27:** SWA deploy workflow at `.github/workflows/deploy-swa.yml` uses `Azure/static-web-apps-deploy@v1`, `skip_app_build: true`, no API. Expects repo secret `AZURE_STATIC_WEB_APPS_API_TOKEN` (deployment token from the SWA resource). Triggers: push to main on `sites/fallback/**` or manual dispatch. Concurrency-guarded.
