param location string
param workspaceName string
param tags object

module workspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'log-analytics-workspace'
  params: {
    name: workspaceName
    location: location
    dataRetention: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    skuName: 'PerGB2018'
    tags: tags
    enableTelemetry: false
  }
}

output workspaceId string = workspace.outputs.resourceId
output workspaceName string = workspace.outputs.name
