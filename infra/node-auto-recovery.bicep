targetScope = 'subscription'

param location string = 'eastus2'
param resourceGroupName string = 'rg-litellm-gateway-demo-eus2'
param workspaceName string
param nodeResourceGroupName string
param nodeVmssName string
param alertEmail string = ''
param enableNodeAutoRecovery bool = false
param tags object = {
  environment: 'demo'
  workload: 'litellm-ai-gateway'
  managedBy: 'bicep'
}

var workspaceId = resourceId(
  subscription().subscriptionId,
  resourceGroupName,
  'Microsoft.OperationalInsights/workspaces',
  workspaceName
)
var nodeVmssResourceId = resourceId(
  subscription().subscriptionId,
  nodeResourceGroupName,
  'Microsoft.Compute/virtualMachineScaleSets',
  nodeVmssName
)

resource labResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: resourceGroupName
}

module nodeAutoRecovery 'modules/node-auto-recovery.bicep' = {
  name: 'aks-node-auto-recovery'
  scope: labResourceGroup
  params: {
    location: location
    enableNodeAutoRecovery: enableNodeAutoRecovery
    nodeVmssResourceId: nodeVmssResourceId
    tags: tags
  }
}

module alerts 'modules/alerts.bicep' = {
  name: 'aks-operational-alerts'
  scope: labResourceGroup
  params: {
    location: location
    workspaceId: workspaceId
    nodeResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', nodeResourceGroupName)
    alertEmail: alertEmail
    enableNodeAutoRecovery: enableNodeAutoRecovery
    autoRecoveryLogicAppId: nodeAutoRecovery.outputs.logicAppId
    autoRecoveryCallbackUrl: nodeAutoRecovery.outputs.triggerCallbackUrl
    tags: tags
  }
}

module vmssRecoveryRole 'modules/vmss-recovery-role.bicep' = {
  name: 'aks-vmss-recovery-role'
  params: {
    enableNodeAutoRecovery: enableNodeAutoRecovery
    nodeResourceGroupName: nodeResourceGroupName
    nodeVmssName: nodeVmssName
  }
}

module vmssRecoveryRoleAssignment 'modules/vmss-recovery-role-assignment.bicep' = {
  name: 'aks-vmss-recovery-role-assignment'
  scope: resourceGroup(nodeResourceGroupName)
  params: {
    enableNodeAutoRecovery: enableNodeAutoRecovery
    nodeVmssName: nodeVmssName
    logicAppPrincipalId: nodeAutoRecovery.outputs.logicAppPrincipalId
    roleDefinitionId: vmssRecoveryRole.outputs.roleDefinitionId
  }
}

output logicAppId string = nodeAutoRecovery.outputs.logicAppId
output actionGroupId string = alerts.outputs.autoRecoveryActionGroupId
