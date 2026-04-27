// =============================================================================
// publix — Resiliency POC — main entry point
// Scope: Resource Group (caller pre-creates the RG with `az group create`).
//
// Wires together:
//   1. Static Web App (fallback content host)
//   2. Azure Front Door Standard (fronts the SWA)
//   3. Traffic Manager (Priority routing: primary external -> AFD fallback)
//
// See docs/architecture.md for topology, probe math, and RTO targets.
// =============================================================================

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------

@description('Resource name prefix. All resources derive their names from this.')
param namePrefix string = 'publix-poc'

@description('Azure region for regional resources (SWA control plane). AFD and TM are global.')
param location string = 'eastus2'

@description('Hostname of the non-Azure primary origin. Update once Alex publishes the GitHub Pages stand-in.')
param primaryOriginHostname string = '<owner>.github.io'

@description('Traffic Manager DNS relative name. Becomes <value>.trafficmanager.net and must be globally unique.')
param tmDnsRelativeName string = 'publix-poc-tm'

@description('Health probe path used by both Traffic Manager and AFD. Must return HTTP 200 over HTTPS.')
param probePath string = '/health'

@description('DNS TTL on the Traffic Manager profile (seconds). 60s recommended for POC.')
param tmTtlSeconds int = 60

// -----------------------------------------------------------------------------
// Tags — applied to every resource for cost + ownership clarity.
// -----------------------------------------------------------------------------

var commonTags = {
  project: 'publix-poc'
  owner: 'jim'
  purpose: 'resiliency-poc'
}

// -----------------------------------------------------------------------------
// Modules
// -----------------------------------------------------------------------------

module swa 'modules/swa.bicep' = {
  name: 'swa-deploy'
  params: {
    name: '${namePrefix}-swa'
    location: location
    tags: commonTags
  }
}

module afd 'modules/afd.bicep' = {
  name: 'afd-deploy'
  params: {
    namePrefix: namePrefix
    tags: commonTags
    originHostname: swa.outputs.defaultHostname
    probePath: probePath
  }
}

module tm 'modules/trafficmanager.bicep' = {
  name: 'tm-deploy'
  params: {
    name: '${namePrefix}-tm'
    dnsRelativeName: tmDnsRelativeName
    tags: commonTags
    primaryHostname: primaryOriginHostname
    fallbackHostname: afd.outputs.endpointHostname
    probePath: probePath
    ttl: tmTtlSeconds
  }
}

// -----------------------------------------------------------------------------
// Outputs — surface the three URLs the team needs.
// -----------------------------------------------------------------------------

@description('SWA default hostname (origin behind AFD).')
output swaHostname string = swa.outputs.defaultHostname

@description('AFD endpoint hostname (fallback target for Traffic Manager).')
output afdHostname string = afd.outputs.endpointHostname

@description('Traffic Manager FQDN — the user-facing entry point for the POC.')
output trafficManagerFqdn string = tm.outputs.fqdn
