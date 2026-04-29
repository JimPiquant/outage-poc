# Decision: tests/RUNBOOK.md + tests/README.md refreshed for demo-handoff

**Author:** Alex (Sites/Frontend)
**Date:** 2026-04-29
**Requested by:** Jim Welch (via Holden)
**Commit:** `7cfa7e6` (pushed to `origin/main`)

## Summary

Refreshed `tests/RUNBOOK.md` and `tests/README.md` so the next operator can run
the failover demo without tribal knowledge. Edits made in place — preserved
existing structure where it was good. The runbook now reflects the live
deployment, the actual `probe.sh` contract, and the canonical evidence run.

## Files touched

- `tests/RUNBOOK.md` — primary refresh target.
- `tests/README.md` — cross-checked and fixed the same stale references in the
  pre-conditions, manual-chaos CLI, portal steps, and parameter table.

## What was stale (and what it is now)

| # | Stale | Now |
|---|---|---|
| 1 | RG `publix-poc-rg` | `rg-publix-poc` (eastus2) |
| 2 | `PRIMARY_HEALTH=https://<gh-user>.github.io/publix-primary/health` (apex 404s on GH Pages project sites) | `https://jimpiquant.github.io/outage-poc/` for visual; TM probe path `/outage-poc/health` (profile-wide) |
| 3 | `PRIMARY_EP=primary` (placeholder) | `primary-external` (verified by Amos's two reruns) |
| 4 | `probe.sh` documented as outputting `resolved-ip` with vague fingerprint logic | Documented current contract (commits `872879a` + `b07fad5`): CNAME-chase top-down, stop at first `*.github.io` / `*.azurefd.net` / `*.azurestaticapps.net` / `*.azureedge.net`, curl resolved host with default SNI, per-origin path (`/outage-poc/` for github.io, `/` for AFD/SWA). Columns: `time | resolved-host | origin-tag | http-status`. |
| 5 | AFD path quirk undocumented | Explicit warning: AFD `/`=200 with correct meta tag; AFD `/outage-poc/` returns the SWA 404 page that **also** carries `fallback-swa` meta tag — the trap. Probe asks `/` against AFD by design. |
| 6 | SWA `/outage-poc/health` route undocumented | Called out: lives in `sites/fallback/staticwebapp.config.json` (commit `f5f3f8e`); required to keep TM `profileMonitorStatus = Online` because the probe path is profile-wide. |
| 7 | No measured-RTO evidence cited | Added "Last validated — 2026-04-29" line up top: failover **38s** / failback **77s** (RTO budget 240s). Canonical evidence: `tests/results/probe-2026-04-28-failover-final.log`. First DNS-only run (18s/28s) noted as reference only. |
| 8 | No live-infra block | Added a table at the top with TM_FQDN, RG, TM profile, AFD endpoint, SWA hostname, primary URL, repo, subscription, and TM probe path. |
| 9 | No hygiene rules | Added: always run `restore-primary.sh` (and defensively on any mid-test failure); pre-check `profileMonitorStatus = Online` before starting; use `gh ... | cat` (not `| head` — pager hangs). |
| 10 | RUNBOOK had no Findings/Caveats section | Added a "Findings history" table (§10) marking #1, #2, #3 all **CLOSED** with one-line resolutions and commit refs. |
| 11 | README example `*.z01.azurefd.net` (legacy AFD Standard/Premium hostname) | Replaced with current AFD endpoint hostname `publix-poc-ep-dpgrdzajc3gqbpe6.b02.azurefd.net`. |

## Evidence

- Canonical demo log: `tests/results/probe-2026-04-28-failover-final.log` (28 primary / 24 fallback / 8 transient curl-fail rows; failover 38s, failback 77s).
- Probe-script contract verified against commits `872879a` and `b07fad5` (both already on `main`).
- SWA route verified against commit `f5f3f8e` (`sites/fallback/staticwebapp.config.json`).

## Status / next steps

- No follow-ups required for the runbook itself.
- Demo is operator-runnable from a cold start using only the runbook.
