param location string
param enableNodeAutoRecovery bool
param nodeVmssResourceId string
param tags object

resource recoveryWorkflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'litellm-aks-node-auto-recovery'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: enableNodeAutoRecovery ? 'Enabled' : 'Disabled'
    definition: loadJsonContent('../workflows/node-auto-recovery.json')
    parameters: {
      vmssResourceId: {
        value: nodeVmssResourceId
      }
    }
  }
}

output logicAppId string = recoveryWorkflow.id
output logicAppPrincipalId string = recoveryWorkflow.identity.principalId
@secure()
output triggerCallbackUrl string = listCallbackUrl('${recoveryWorkflow.id}/triggers/Node_not_ready_alert', '2019-05-01').value
