// =============================================================================
// Module: Azure Traffic Manager (Priority routing)
// Purpose: DNS-based failover brain. Priority 1 = non-Azure primary (GitHub
//          Pages stand-in). Priority 2 = AFD endpoint (fallback path to SWA).
//
// Note: TM resources are 'global'. Both endpoints are modeled as
//       externalEndpoints because:
//         - GitHub Pages is non-Azure (must be external)
//         - AFD is not directly trackable as an Azure endpoint type in TM;
//           external w/ FQDN is the documented pattern.
// =============================================================================

@description('Name of the Traffic Manager profile resource.')
param name string

@description('DNS relative name. Becomes <relativeName>.trafficmanager.net.')
param dnsRelativeName string

@description('Resource tags applied to every resource.')
param tags object

@description('Hostname of the primary (non-Azure) origin. e.g. owner.github.io')
param primaryHostname string

@description('Hostname of the fallback origin (AFD endpoint, e.g. xxx.z01.azurefd.net).')
param fallbackHostname string

@description('Health probe path. Both endpoints must expose this path returning HTTP 200 over HTTPS.')
param probePath string = '/health'

@description('DNS TTL in seconds. 60s is the POC recommendation.')
param ttl int = 60

resource tm 'Microsoft.Network/trafficmanagerprofiles@2022-04-01' = {
  name: name
  location: 'global'
  tags: tags
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Priority'
    dnsConfig: {
      relativeName: dnsRelativeName
      ttl: ttl
    }
    monitorConfig: {
      // Probe config matches docs/architecture.md §3.3 exactly.
      protocol: 'HTTPS'
      port: 443
      path: probePath
      intervalInSeconds: 30
      timeoutInSeconds: 10
      toleratedNumberOfFailures: 3
      expectedStatusCodeRanges: [
        {
          min: 200
          max: 200
        }
      ]
    }
    trafficViewEnrollmentStatus: 'Disabled'
    endpoints: [
      {
        name: 'primary-external'
        type: 'Microsoft.Network/trafficManagerProfiles/externalEndpoints'
        properties: {
          target: primaryHostname
          endpointStatus: 'Enabled'
          priority: 1
          // EndpointLocation is required for performance routing only; harmless to omit for Priority.
        }
      }
      {
        name: 'fallback-afd'
        type: 'Microsoft.Network/trafficManagerProfiles/externalEndpoints'
        properties: {
          target: fallbackHostname
          endpointStatus: 'Enabled'
          priority: 2
        }
      }
    ]
  }
}

@description('Fully qualified DNS name of the Traffic Manager profile (the user-facing entry point).')
output fqdn string = tm.properties.dnsConfig.fqdn

@description('TM profile resource ID.')
output id string = tm.id
