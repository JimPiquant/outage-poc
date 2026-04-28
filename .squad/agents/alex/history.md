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
- **2026-04-27:** Published primary stand-in live. Created public repo `JimPiquant/outage-poc`, pushed initial commit, added `.github/workflows/pages.yml` (uploads `sites/primary/` via `actions/upload-pages-artifact@v3` + `actions/deploy-pages@v4`) because the Pages REST API only accepts `/` or `/docs` as `source[path]` — workflow build was the only way to publish from `sites/primary/`. Pages enabled with `build_type=workflow`, first run succeeded in ~17s. Live at <https://jimpiquant.github.io/outage-poc/>; `/`, `/health.html`, and `/health` all return HTTP 200. Updated `infra/main.bicepparam` defaults: `primaryOriginHostname=jimpiquant.github.io`, `probePath=/outage-poc/health` (subpath required because it's a project Pages site). Decision dropped at `.squad/decisions/inbox/alex-pages-published.md` for Naomi & Amos.
- 2026-04-27 — Removed "Publix" brand name from public primary site (index.html title+H1, 404.html title) and corrected README URLs to https://jimpiquant.github.io/outage-poc/. Fallback site untouched.
- **2026-04-27 — Naomi deployed infra:** SWA deployment token now stored as GH secret `AZURE_STATIC_WEB_APPS_API_TOKEN`; `deploy-swa.yml` workflow triggered (run 25022553077). Fallback site now deploying. SWA hostname: `white-water-098b0170f.7.azurestaticapps.net`. Ready for Amos's failover tests once SWA content is live.

- **2026-04-28 (Amos failover demo findings):**
  - **probe.sh SNI failure (MEDIUM):** Amos discovered that `tests/scripts/probe.sh` does an HTTPS GET against the TM FQDN (`publix-poc-tm.trafficmanager.net`) with `Host: <tm-fqdn>`, but neither origin (GH Pages `*.github.io` cert, AFD `*.azurefd.net` cert) presents a SAN matching `publix-poc-tm.trafficmanager.net`. Every TLS handshake failed (`curl-fail`, `http-status=000`). Amos worked around by building a DNS-only probe (DNS CNAME) to capture the failover signal.
    - **Action for you:** Rewrite `tests/scripts/probe.sh` to resolve the CNAME chain with `dig` first, then curl the *resolved* hostname (so SNI matches the cert). Alternatively, stand up a custom domain (e.g., `publix-poc.<yourdomain>`) on TM with matching certs on both origins — but that's infrastructure scope, not site scope.
  - **TM probe path mismatch (also hits fallback SWA):** Same issue as in Naomi's note — TM probes `/outage-poc/health` but SWA serves `/health`. **Action for you:** Coordinate with Naomi/Sam — either (a) add `staticwebapp.config.json` route to serve `/outage-poc/health` (easiest), or (b) add `/outage-poc/health` path to primary GH Pages and update TM probe path to `/health`. Option (a) is cleanest if feasible.
