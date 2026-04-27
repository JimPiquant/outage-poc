# Project Context

- **Owner:** Jim Welch
- **Project:** publix — Azure resiliency POC. Demonstrates failover from a non-Azure primary website to an Azure Static Web App (SWA) using Azure Traffic Manager (priority routing) in front of Azure Front Door. Reference design: techcommunity Azure Architecture Blog "Resiliency patterns for Azure Front Door — Field Lessons" Option #1.
- **Stack:** Azure (Front Door, Traffic Manager, Static Web Apps), Bicep (likely), HTML/CSS for the static fallback site, GitHub Actions for SWA deploy.
- **Created:** 2026-04-27

## Learnings

- **2026-04-27:** Architecture proposal delivered in `docs/architecture.md` and `.squad/decisions.md` — lists 6 blocking questions for Jim. Phase 2 infrastructure work blocked until decisions made and Phase 1 deployed.

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **2026-04-27:** Authored `tests/README.md` (test plan w/ 6-scenario matrix), `tests/RUNBOOK.md` (canonical demo), and 4 chaos scripts under `tests/scripts/`. Did NOT execute — infra not deployed.
- **2026-04-27 — RTO budget I'm holding the team to:** detection 100s + DNS 60–120s = **160–220s**, with **240s as the pass threshold** (architecture upper bound + 20s grace). If real measurements exceed 240s, the architecture's RTO claim is wrong and I file a finding.
- **2026-04-27 — dependency on Alex:** I assumed his pages emit `<meta name="origin" content="primary-github-pages">` and `<meta name="origin" content="fallback-swa">`. `probe.sh` parses that meta tag first, then falls back to literal-substring match on those two strings. If Alex picks different fingerprint values, edit `FP_PRIMARY`/`FP_FALLBACK` at the top of `probe.sh`. Alex's decision file (`.squad/decisions/inbox/alex-sites-and-deploy.md`) didn't exist yet at authoring time — verify when it lands.
- **2026-04-27 — Naomi deployed infra:** All 7 resources succeeded. Three FQDNs now live and ready for failover tests:
  - **Traffic Manager (entry point):** `publix-poc-tm.trafficmanager.net`
  - **AFD endpoint (fallback path):** `publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net`
  - **SWA (fallback origin):** `white-water-098b0170f.7.azurestaticapps.net`
  - **Primary (GH Pages):** `jimpiquant.github.io/outage-poc/` (already live)
  Primary is healthy and TM DNS is pointing to it. SWA content deploying now (Alex's workflow). Ready for test scenarios once SWA `/health` returns 200.
- **2026-04-27 — TM "Disabled" vs real outage:** Disabling the TM endpoint skips the 100s probe-detection window. That's fine for demoing the DNS-swap half of RTO cleanly, but it understates the real RTO. Scenario #3 in the matrix breaks `/health` for real to exercise full detection+DNS path. Both should be run before declaring victory.
