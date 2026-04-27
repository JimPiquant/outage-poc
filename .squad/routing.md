# Work Routing

How to decide who handles what for the publix Azure failover POC.

## Routing Table

| Work Type | Route To | Examples |
|-----------|----------|----------|
| Architecture, design, scope | Holden | Failover topology, probe design, AFD vs TM trade-offs, reviewer gate |
| Azure IaC (Bicep/azd) | Naomi | Front Door profile, Traffic Manager profile, SWA, DNS, custom domains, deploy scripts |
| Static fallback site | Alex | HTML/CSS for SWA, `staticwebapp.config.json`, SWA deploy workflow |
| Failover testing, chaos | Amos | Simulate primary outage, verify TM probe + cutover timing, runbooks |
| Code/IaC review | Holden | Reviewer gate on architectural correctness and resiliency |
| Resiliency review | Amos | Reviewer gate on "did we actually prove it fails over?" |
| Scope & priorities | Holden | What to build next, trade-offs, decisions |
| Session logging | Scribe | Automatic — never needs routing |
| Work queue / backlog | Ralph | Issue triage loop, keep team busy |

## Issue Routing

| Label | Action | Who |
|-------|--------|-----|
| `squad` | Triage: analyze issue, assign `squad:{member}` label | Holden |
| `squad:holden` | Architecture / design / review issues | Holden |
| `squad:naomi` | Bicep / Azure infra issues | Naomi |
| `squad:alex` | Static site / SWA issues | Alex |
| `squad:amos` | Test / chaos / validation issues | Amos |

### How Issue Assignment Works

1. When a GitHub issue gets the `squad` label, **Holden** triages it — analyzing content, assigning the right `squad:{member}` label, and commenting with triage notes.
2. When a `squad:{member}` label is applied, that member picks up the issue in their next session.
3. Members can reassign by removing their label and adding another member's label.

## Rules

1. **Eager by default** — spawn all agents who could usefully start work, including anticipatory downstream work (Amos can write test plans while Naomi writes Bicep).
2. **Scribe always runs** after substantial work, always as `mode: "background"`. Never blocks.
3. **Quick facts → coordinator answers directly.**
4. **When two agents could handle it**, pick the one whose domain is the primary concern.
5. **"Team, ..." → fan-out.** Spawn all relevant agents in parallel as `mode: "background"`.
6. **Anticipate downstream work.** When Naomi provisions Traffic Manager, Amos should already be drafting the chaos test for it.
