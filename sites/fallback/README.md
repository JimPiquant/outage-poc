# Fallback site (Azure Static Web App)

This is the **fallback origin** for the Publix resiliency POC. Traffic Manager
routes here when the primary origin's health probe fails. End users see a
friendly "operating in fallback mode" page.

> Visual cue: amber/orange theme with a **⚠️ Operating in fallback mode** banner.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Friendly fallback landing page (non-technical tone, render timestamp) |
| `health.html` | Health endpoint body — `OK - fallback` |
| `404.html` | Friendly not-found page |
| `staticwebapp.config.json` | SWA config — exposes `/health` AND `/health.html` as `text/plain`, no-cache |

## Health endpoint — both `/health` and `/health.html` work

The SWA config rewrites `/health` → `/health.html` and forces
`Content-Type: text/plain` on both. So Naomi can use either path in the
Traffic Manager probe; we recommend `/health` for prettiness.

| Probe path | Status | Body | Content-Type |
|------------|--------|------|--------------|
| `/health` | 200 | `OK - fallback` | `text/plain; charset=utf-8` |
| `/health.html` | 200 | `OK - fallback` | `text/plain; charset=utf-8` |

This is the **routes-rule** approach (rather than a bare file). It costs us
nothing and gives a clean URL.

## Deploying

There is no build step — this is plain HTML. Two options:

### Option A — GitHub Actions (recommended)

The workflow `.github/workflows/deploy-swa.yml` deploys this directory to SWA
on every push to `main` that touches `sites/fallback/**`, and on manual
dispatch.

**One-time setup after Naomi creates the SWA resource:**

1. In Azure Portal → the SWA resource → **Overview** → **Manage deployment token** → copy the token.
2. In GitHub → repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:
   - **Name:** `AZURE_STATIC_WEB_APPS_API_TOKEN`
   - **Value:** *(paste the deployment token)*
3. Push a commit touching `sites/fallback/**`, or run the workflow manually
   via **Actions** → **Deploy fallback site to Azure Static Web Apps** →
   **Run workflow**.

### Option B — SWA CLI (local / ad-hoc)

```bash
npm install -g @azure/static-web-apps-cli
swa deploy ./sites/fallback \
  --deployment-token "$AZURE_STATIC_WEB_APPS_API_TOKEN" \
  --env production
```

## SWA hostname pattern

After deployment the SWA gets an auto-generated hostname like:

```
https://<random-words-and-id>.<region>.azurestaticapps.net
```

…for example `https://kind-pebble-0123abc04.6.azurestaticapps.net`. The exact
value is on the SWA resource's **Overview** page in the portal. Naomi will
register this hostname as the Azure Front Door origin.

## Verifying after deploy

```bash
SWA_HOST="<paste-the-hostname>.azurestaticapps.net"

curl -I  "https://$SWA_HOST/"           # expect HTTP 200, x-origin: fallback-swa
curl     "https://$SWA_HOST/health"     # expect body: OK - fallback
curl -I  "https://$SWA_HOST/health"     # expect 200 + content-type: text/plain
curl     "https://$SWA_HOST/health.html"  # also works, same body
```
