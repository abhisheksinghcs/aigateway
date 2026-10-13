targetScope = 'subscription'

param enableNodeAutoRecovery bool
param nodeResourceGroupName string
param nodeVmssName string

var nodeVmssResourceId = resourceId(
  subscription().subscriptionId,
  nodeResourceGroupName,
  'Microsoft.Compute/virtualMachineScaleSets',
  nodeVmssName
)

resource recoveryRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = if (enableNodeAutoRecovery) {
  name: guid(subscription().id, 'litellm-aks-vmss-start-operator')
  properties: {
    roleName: 'LiteLLM AKS VMSS Start Operator'
    description: 'Reads one AKS VMSS and starts deallocated instances for guarded node auto-recovery.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Compute/virtualMachineScaleSets/read'
          'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read'
          'Microsoft.Compute/virtualMachineScaleSets/start/action'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      nodeVmssResourceId
    ]
  }
}

output roleDefinitionId string = enableNodeAutoRecovery ? recoveryRole.id : ''
