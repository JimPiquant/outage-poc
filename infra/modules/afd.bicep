// =============================================================================
// Module: Azure Front Door Standard
// Purpose: Fronts the Static Web App. Provides the *.azurefd.net hostname that
//          Traffic Manager's Priority 2 (fallback) external endpoint targets.
//
// Topology: profile -> endpoint -> originGroup -> origin (SWA) -> route
// =============================================================================

@description('Name prefix used to derive AFD child resource names.')
param namePrefix string

@description('Resource tags applied to every resource.')
param tags object

@description('Hostname of the origin (the SWA defaultHostname, e.g. xxx.azurestaticapps.net).')
param originHostname string

@description('Health probe path on the origin. Should match what the fallback site exposes.')
param probePath string = '/'

// AFD profile is a global resource; ARM still requires location='global'.
resource profile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: '${namePrefix}-afd'
  location: 'global'
  tags: tags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: profile
  name: '${namePrefix}-ep'
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: profile
  name: '${namePrefix}-og'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: probePath
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 60
    }
    sessionAffinityState: 'Disabled'
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: '${namePrefix}-origin-swa'
  properties: {
    hostName: originHostname
    httpPort: 80
    httpsPort: 443
    // Forward the SWA hostname so SWA routes/SNI work correctly.
    originHostHeader: originHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'default-route'
  dependsOn: [
    origin
  ]
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
}

@description('Public *.azurefd.net hostname. This is the target for Traffic Manager Priority 2.')
output endpointHostname string = endpoint.properties.hostName

@description('AFD profile resource ID.')
output profileId string = profile.id
