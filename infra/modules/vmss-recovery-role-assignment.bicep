param enableNodeAutoRecovery bool
param nodeVmssName string
param logicAppPrincipalId string
param roleDefinitionId string

resource nodeVmss 'Microsoft.Compute/virtualMachineScaleSets@2024-11-01' existing = {
  name: nodeVmssName
}

resource recoveryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableNodeAutoRecovery) {
  name: guid(nodeVmss.id, logicAppPrincipalId, roleDefinitionId)
  scope: nodeVmss
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: logicAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
