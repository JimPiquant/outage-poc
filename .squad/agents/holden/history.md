# Project Context

- **Owner:** Jim Welch
- **Project:** publix — Azure resiliency POC. Demonstrates failover from a non-Azure primary website to an Azure Static Web App (SWA) using Azure Traffic Manager (priority routing) in front of Azure Front Door. Reference design: techcommunity Azure Architecture Blog "Resiliency patterns for Azure Front Door — Field Lessons" Option #1.
- **Stack:** Azure (Front Door, Traffic Manager, Static Web Apps), Bicep (likely), HTML/CSS for the static fallback site, GitHub Actions for SWA deploy.
- **Created:** 2026-04-27

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-04-27: Option #1 Architecture Understanding

- **Failover brain location:** Traffic Manager owns the failover decision at the DNS layer. AFD does NOT make the failover decision in this pattern — it only serves traffic once TM routes to it.
- **Probe math matters:** RTO = (tolerated failures × interval) + timeout + DNS TTL propagation. Default config gives ~2–4 min RTO; aggressive tuning can hit ~1 min but risks false positives.
- **SNI gotcha:** TM probes include SNI hostname. If primary cert CN doesn't match the endpoint hostname TM is probing, the probe will fail TLS handshake. Configure explicit hostname header if needed.
- **Automatic failback:** TM automatically routes back to primary when it recovers — no manual intervention, but existing client connections stay on fallback until their DNS cache expires.
- **POC simplification:** Using GitHub Pages or Cloudflare Pages as the "non-Azure primary" is cheap and realistic enough. No need to spin up VMs or containers just to simulate external infrastructure.
