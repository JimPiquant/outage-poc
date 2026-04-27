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
- **2026-04-27 — dependency on Naomi:** Scripts are parameterized; I assumed her Bicep will produce endpoint name `primary` and TM endpoint `--type ExternalEndpoints` (since the GH Pages primary is external). If she uses Azure-typed endpoints or a different name, the `break-primary.sh`/`restore-primary.sh` `--type` and endpoint-name args will need updating. Need from her: RG name, TM profile name, TM FQDN, primary endpoint name, AFD endpoint hostname.
- **2026-04-27 — TM "Disabled" vs real outage:** Disabling the TM endpoint skips the 100s probe-detection window. That's fine for demoing the DNS-swap half of RTO cleanly, but it understates the real RTO. Scenario #3 in the matrix breaks `/health` for real to exercise full detection+DNS path. Both should be run before declaring victory.
