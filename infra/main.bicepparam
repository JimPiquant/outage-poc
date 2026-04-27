// Default parameter set for the publix resiliency POC.
// Update `primaryOriginHostname` once Alex publishes the GitHub Pages stand-in.

using './main.bicep'

param namePrefix = 'publix-poc'
param location = 'eastus2'

// PLACEHOLDER — replace with the real GitHub Pages URL Alex sets up.
// Example: 'jimwelch.github.io' or 'jimwelch.github.io/publix-primary' (host only, no scheme/path).
param primaryOriginHostname = '<owner>.github.io'

param tmDnsRelativeName = 'publix-poc-tm'
param probePath = '/health'
param tmTtlSeconds = 60
