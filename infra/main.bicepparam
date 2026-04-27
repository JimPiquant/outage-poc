// Default parameter set for the publix resiliency POC.
// Update `primaryOriginHostname` once Alex publishes the GitHub Pages stand-in.

using './main.bicep'

param namePrefix = 'publix-poc'
param location = 'eastus2'

// Live as of 2026-04-27 — Alex published the primary stand-in to GitHub Pages.
// Repo: https://github.com/JimPiquant/outage-poc  →  https://jimpiquant.github.io/outage-poc/
// NOTE: this is a *project* Pages site, so the content lives under the /outage-poc/ subpath.
// The host alone (`jimpiquant.github.io`) is what TM/AFD point at; the subpath belongs in `probePath`.
param primaryOriginHostname = 'jimpiquant.github.io'

param tmDnsRelativeName = 'publix-poc-tm'
// Must include the project subpath because GH Pages serves under /outage-poc/.
// Both `/outage-poc/health` and `/outage-poc/health.html` return 200.
param probePath = '/outage-poc/health'
param tmTtlSeconds = 60
