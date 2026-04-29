# Squad Session Log

## 2026-04-28 — Failover POC: clean-evidence iteration cycle complete

**Date:** 2026-04-28 (21:53Z–22:21Z)  
**Participants:** Amos (SRE), Alex (Sites/Frontend)  
**Duration:** 28 min  
**Status:** ✅ CLOSED — demo-ready  

### Iteration summary

Three-phase cycle (rerun broken → fix → rerun final) resolved Finding #3 (probe.sh cannot classify AFD fallback leg).

**Phase 1 (Amos, 21:53Z):** Failover demo rerun with fresh probe instrument. RTO timings PASS (46s/96s), but probe evidence FAIL — 31/60 rows read `unknown/404` during fallback. Diagnosed: Bug A (CNAME chase walks into shared infra), Bug B (path assumption about AFD).

**Phase 2 (Alex, 22:10Z):** Fixed both bugs. Bug A: CNAME walk now stops at service-identity pattern match. Bug B: Empirically tested and corrected — AFD root `/` serves 200 with correct meta tag (not 404 as presumed). Amos's assumption was wrong, but Alex's fix is right anyway. Smoke tests 5/6 + 1 transient on fallback.

**Phase 3 (Amos, 22:21Z):** Final clean-evidence rerun. RTO PASS (38s/77s, faster than rerun 1). Evidence PASS — 28/24/8 tag distribution, all 8 unknowns are transient curl-fails (0 content-classification failures). Pre-flight validation: AFD path claim verified again (root 200, subpath 404). **Finding #3 CLOSED.**

### End state

- **Failover demo:** Demo-ready with clean evidence.
- **Timings:** 38s failover, 77s failback (both ≪ 240s RTO).
- **Evidence quality:** 28/24/8 tags; zero content-classification failures; all 8 unknowns are transient socket flakes (acceptable).
- **Both endpoints:** Online and correctly classified end-to-end.
- **Findings:** All 3 findings resolved (#1 TLS bug, #2 SWA route, #3 probe AFD leg).

### Next steps

Failover POC ready for external/management presentation. All infrastructure validated. Clean evidence captured.

---

## 2026-04-29 — Runbook refresh — post-validation

**Date:** 2026-04-29 (03:55Z)  
**Author:** Alex (Sites/Frontend) | **Merged by:** Scribe (housekeeping)  
**Duration:** N/A (inbox merge)  
**Status:** ✅ COMPLETE  

### Summary

Alex refreshed `tests/RUNBOOK.md` and `tests/README.md` for operator handoff. All 11 stale references fixed in place: RG name (`rg-publix-poc`), primary endpoint (`primary-external`), AFD path quirk documented, probe script contract codified (commits `872879a` + `b07fad5`), SWA route reference added (`f5f3f8e`), and measured RTO evidence captured and cited (failover 38s / failback 77s, last validated 2026-04-29). Findings #1, #2, #3 all marked CLOSED with commit references in new Findings history table (§10 of RUNBOOK).

### Deliverables

- **`tests/RUNBOOK.md`** — Complete refresh; 11 stale items resolved; live-infra table added (TM_FQDN, RG, profile, AFD, SWA, primary URL, subscription, probe path); hygiene rules added; Findings history table (all CLOSED).
- **`tests/README.md`** — Cross-checked; stale infra references fixed (RG, endpoint hostname, paths).
- **Canonical evidence** — Cited: `tests/results/probe-2026-04-28-failover-final.log` (28/24/8 tags; zero content-classification failures; RTO 38s/77s).

### Operator impact

Next engineer can run the failover demo cold-start from RUNBOOK without tribal knowledge. All prerequisites, manual chaos steps, expected outputs, AFD path quirk, and post-test cleanup documented and validated.
