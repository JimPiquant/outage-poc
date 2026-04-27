// =============================================================================
// Module: Azure Static Web App (Free tier)
// Purpose: Hosts the fallback site content. Content deploy is decoupled from
//          IaC — Alex will publish via SWA CLI / GitHub Actions, so we do NOT
//          bind a repository here.
// =============================================================================

@description('Name of the Static Web App resource.')
param name string

@description('Azure region for the SWA. Note: SWA is globally distributed at the edge; this is the control-plane region.')
param location string

@description('Resource tags applied to every resource.')
param tags object

resource swa 'Microsoft.Web/staticSites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    // No repo binding — content is pushed out-of-band via SWA CLI / GH Actions.
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Enabled'
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

@description('Default *.azurestaticapps.net hostname for the SWA. Used as the AFD origin host.')
output defaultHostname string = swa.properties.defaultHostname

@description('Resource ID of the SWA.')
output id string = swa.id
