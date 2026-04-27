# Squad Team

> publix — Azure failover POC: non-Azure primary → Traffic Manager → Azure Front Door + Static Web App fallback.

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Squad | Coordinator | Routes work, enforces handoffs and reviewer gates. |

## Members

| Name   | Role                          | Charter                              | Status |
|--------|-------------------------------|--------------------------------------|--------|
| Holden | 🏗️ Lead / Azure Architect     | .squad/agents/holden/charter.md      | active |
| Naomi  | ⚙️ Cloud Infrastructure Engineer | .squad/agents/naomi/charter.md    | active |
| Alex   | ⚛️ Static Site Developer       | .squad/agents/alex/charter.md        | active |
| Amos   | 🧪 Tester / Chaos Engineer     | .squad/agents/amos/charter.md        | active |
| Scribe | 📋 Session Logger             | .squad/agents/scribe/charter.md      | active |
| Ralph  | 🔄 Work Monitor               | .squad/agents/ralph/charter.md       | active |

## Project Context

- **Owner:** Jim Welch
- **Project:** publix
- **Description:** Azure resiliency POC demonstrating failover from a non-Azure primary site to an Azure Static Web App via Azure Traffic Manager + Azure Front Door (Option #1 from the Azure Architecture Blog "Resiliency patterns for Azure Front Door — Field Lessons").
- **Stack:** Azure (Front Door, Traffic Manager, Static Web Apps), Bicep, HTML/CSS, GitHub Actions.
- **Created:** 2026-04-27
