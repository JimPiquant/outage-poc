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
