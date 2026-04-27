# publix — Infra (Bicep)

This folder contains the Bicep IaC for the **publix resiliency POC**. It deploys:

1. **Azure Static Web App** (Free) — hosts the fallback site content.
2. **Azure Front Door Standard** — profile + endpoint + origin group + origin (SWA) + route.
3. **Azure Traffic Manager** — Priority routing across two `externalEndpoints`:
   - Priority 1: the non-Azure primary (GitHub Pages stand-in).
   - Priority 2: the AFD endpoint (fallback path to the SWA).

See `../docs/architecture.md` for the topology, probe math, and RTO targets.

> Content deploy (the actual HTML/CSS for the fallback site) is **decoupled** from this IaC. Alex publishes content via the SWA CLI / GitHub Actions out-of-band — Bicep only provisions the empty SWA shell.

---

## Layout

```
infra/
  main.bicep              # RG-scoped entry point. Composes the three modules.
  main.bicepparam         # Default parameters (publix-poc, eastus2, /health, ...).
  modules/
    swa.bicep             # Static Web App (Free)
    afd.bicep             # Azure Front Door Standard (profile/endpoint/originGroup/origin/route)
    trafficmanager.bicep  # TM profile (Priority routing) + 2 external endpoints
  README.md               # this file
```

---

## Prerequisites

- **Azure CLI** ≥ 2.50 — <https://learn.microsoft.com/cli/azure/install-azure-cli>
- **Bicep CLI** (bundled with az) — `az bicep install` or `az bicep upgrade`
- An authenticated Azure session: `az login`
- A subscription with rights to create resource groups + the resources above:
  ```sh
  az account set --subscription "<your-subscription-id-or-name>"
  ```

---

## Deploy

The deployment is **resource-group scoped**. Create the RG once, then run the deployment.

```sh
# 1. Create the resource group (one-time)
az group create -n rg-publix-poc -l eastus2

# 2. Preview what will change (no-op)
az deployment group what-if \
  -g rg-publix-poc \
  -f infra/main.bicep \
  -p infra/main.bicepparam

# 3. Apply
az deployment group create \
  -g rg-publix-poc \
  -f infra/main.bicep \
  -p infra/main.bicepparam
```

After a successful deploy, the deployment outputs surface the three hostnames:

- `swaHostname` — the SWA default hostname (origin behind AFD).
- `afdHostname` — the AFD endpoint hostname (used as TM Priority 2 target).
- `trafficManagerFqdn` — the user-facing entry point (`publix-poc-tm.trafficmanager.net`).

Retrieve them later with:

```sh
az deployment group show \
  -g rg-publix-poc \
  -n main \
  --query properties.outputs
```

---

## Updating the primary origin hostname

The `primaryOriginHostname` parameter ships with a placeholder (`<owner>.github.io`). Once Alex publishes the GitHub Pages stand-in:

1. Edit `infra/main.bicepparam` and set `primaryOriginHostname` to the real GitHub Pages host (host only — no `https://`, no path). Example: `jimwelch.github.io`.
2. Re-run the deploy (it's idempotent — only the TM endpoint will change):
   ```sh
   az deployment group what-if -g rg-publix-poc -f infra/main.bicep -p infra/main.bicepparam
   az deployment group create  -g rg-publix-poc -f infra/main.bicep -p infra/main.bicepparam
   ```

You can also override on the CLI without editing the file:

```sh
az deployment group create \
  -g rg-publix-poc \
  -f infra/main.bicep \
  -p infra/main.bicepparam \
  -p primaryOriginHostname=jimwelch.github.io
```

---

## Parameters

| Name | Default | Notes |
|------|---------|-------|
| `namePrefix` | `publix-poc` | Drives all resource names. |
| `location` | `eastus2` | SWA control-plane region. AFD + TM are global. |
| `primaryOriginHostname` | `<owner>.github.io` | **Placeholder** — set after Alex publishes GH Pages. |
| `tmDnsRelativeName` | `publix-poc-tm` | Becomes `<value>.trafficmanager.net`. Must be globally unique — change if collision. |
| `probePath` | `/health` | Both TM and AFD probe this path over HTTPS:443; must return 200. |
| `tmTtlSeconds` | `60` | DNS TTL on the TM profile. Lower = faster failover, higher DNS cost. |

---

## Teardown

The whole POC is contained in the RG, so teardown is one command:

```sh
az group delete -n rg-publix-poc --yes
```

(TM profile DNS names are released back to the global pool after deletion completes — usually within a few minutes.)

---

## Notes / gotchas

- **Custom domains are intentionally out of scope** for this POC — we use the Azure-generated `*.trafficmanager.net`, `*.azurefd.net`, and `*.azurestaticapps.net` hostnames.
- TM endpoints are both `externalEndpoints`: GitHub Pages must be external, and AFD endpoints aren't a first-class Azure endpoint type in TM either.
- The AFD origin uses `originHostHeader = swa.defaultHostname` so the SWA's SNI/host routing works correctly.
- The probe configuration in `trafficmanager.bicep` (HTTPS/443, 30s interval, 10s timeout, 3 tolerated failures, status 200 only) matches `docs/architecture.md` §3.3 exactly. If you change it there, change it here.
