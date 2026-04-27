# Squad Decisions

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
