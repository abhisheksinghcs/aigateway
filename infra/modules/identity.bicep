param location string
param identityName string
param tags object

module identity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'workload-identity'
  params: {
    name: identityName
    location: location
    tags: tags
    enableTelemetry: false
  }
}

output identityName string = identity.outputs.name
output identityId string = identity.outputs.resourceId
output clientId string = identity.outputs.clientId
output principalId string = identity.outputs.principalId
