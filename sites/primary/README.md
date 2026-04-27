# Primary stand-in site (GitHub Pages)

This is the **primary origin** for the resiliency POC. It simulates a
non-Azure customer site. Traffic Manager probes its `/health.html` endpoint
and routes traffic here as long as the probe returns HTTP 200.

> Visual cue: bright green banner reading **✅ PRIMARY ORIGIN (GitHub Pages)**.
> If you see this in a browser test, you hit the primary path.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Landing page with distinctive green branding and a render timestamp |
| `health.html` | Health endpoint — returns `OK - primary` (HTTP 200) |
| `404.html` | Minimal not-found page |

## Health endpoint — pick one, we picked `health.html`

GitHub Pages serves files as-is. There are two reasonable shapes:

| Shape | URL served | Notes |
|-------|------------|-------|
| `health.html` | `/health.html` | ✅ **Chosen.** Single file, no redirect, exact HTTP 200. |
| `health/index.html` | `/health/` | Reachable at `/health/` — but `/health` (no slash) returns a **301 redirect** to `/health/`. Some probes don't follow redirects. |

**Decision:** we ship `health.html` so the probe path is exactly `/health.html`
with no redirect chain. Naomi must use this exact path in the Traffic Manager
endpoint config.

## How to enable GitHub Pages

There are two equally valid options. **Option A is simpler — recommended for
the POC.**

### Option A — Publish from `main` branch, folder `/sites/primary` (recommended)

1. Repo → **Settings** → **Pages**
2. Source: **Deploy from a branch**
3. Branch: `main`, Folder: `/sites/primary`
4. Save. After ~1 minute the URL appears at the top of the Pages page.

### Option B — GitHub Actions workflow

If you'd rather use Actions, add a workflow that uses
`actions/upload-pages-artifact` + `actions/deploy-pages` pointed at
`sites/primary/`. Not included here to keep the POC small.

## Resulting URL pattern — ⚠️ subpath caveat ⚠️

For a project repo (which this is), GitHub Pages publishes at:

```
https://<owner>.github.io/<repo>/
```

…meaning the **repo name is part of every URL path**. For this repo that is:

```
https://jimpiquant.github.io/outage-poc/
https://jimpiquant.github.io/outage-poc/health.html
```

This affects Naomi's Traffic Manager config. The TM endpoint must be
configured as:

| Setting | Value |
|---------|-------|
| Target hostname | `<owner>.github.io` |
| Probe protocol | HTTPS / 443 |
| Probe path | `/outage-poc/health.html` ← **NOT** `/health.html` |

If you ever publish from a **user/organization site repo** (named
`<owner>.github.io`) or attach a custom domain via `CNAME`, the subpath
disappears and the probe path collapses to `/health.html`. We are explicitly
**not** doing custom domain in this POC (per Jim's decision).

**Recommendation:** stay on the subpath. Naomi just needs to know the probe
path is `/<repo>/health.html`.

## Verifying after publish

```bash
# Confirm both return HTTP 200
curl -I https://jimpiquant.github.io/outage-poc/
curl    https://jimpiquant.github.io/outage-poc/health.html
# Expected body: "OK - primary"
```
