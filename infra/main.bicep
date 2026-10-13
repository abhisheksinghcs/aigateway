targetScope = 'subscription'

@description('Azure region for the AI Gateway lab.')
param location string = 'eastus2'

@description('Dedicated resource group name.')
param resourceGroupName string = 'rg-litellm-gateway-demo-eus2'

@description('Short resource prefix used for globally scoped names.')
param resourcePrefix string = 'litellm-demo'

@description('Existing resource group that contains the Azure AI account.')
param modelResourceGroupName string = 'MC-abhi'

@description('Existing Azure AI Services account used by LiteLLM.')
param modelAccountName string = 'Agent365-Teams-Agents'

@description('Object ID that receives AKS RBAC Cluster Admin. Leave empty to skip the assignment.')
param aksAdminPrincipalId string = ''

@description('Email receiver for AKS operational alerts. Leave empty to deploy alerts without email notification.')
param alertEmail string = ''

@description('Enable one guarded Logic App recovery attempt when the AKS node-not-ready alert fires.')
param enableNodeAutoRecovery bool = false

@description('AKS node VMSS name. Required only when guarded node auto-recovery is enabled.')
param nodeVmssName string = ''

@description('Tags applied to resources created by this deployment.')
param tags object = {
  environment: 'demo'
  workload: 'litellm-ai-gateway'
  managedBy: 'bicep'
}

var suffix = uniqueString(subscription().id, resourceGroupName)
var vnetName = '${resourcePrefix}-vnet'
var workspaceName = '${resourcePrefix}-law-${suffix}'
var workloadIdentityName = '${resourcePrefix}-workload-id'
var aksName = '${resourcePrefix}-aks'
var nodeResourceGroupName = 'MC_${resourceGroupName}_${aksName}_${location}'
var nodeVmssResourceId = resourceId(
  subscription().subscriptionId,
  nodeResourceGroupName,
  'Microsoft.Compute/virtualMachineScaleSets',
  nodeVmssName
)

resource labResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module network 'modules/network.bicep' = {
  name: 'network'
  scope: labResourceGroup
  params: {
    location: location
    vnetName: vnetName
    tags: tags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: labResourceGroup
  params: {
    location: location
    workspaceName: workspaceName
    tags: tags
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: labResourceGroup
  params: {
    location: location
    identityName: workloadIdentityName
    tags: tags
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aks'
  scope: labResourceGroup
  params: {
    location: location
    aksName: aksName
    aksSubnetId: network.outputs.aksSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    aksAdminPrincipalId: aksAdminPrincipalId
    tags: tags
  }
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
    workspaceId: monitoring.outputs.workspaceId
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

resource subscriptionActivityDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'litellm-subscription-activity'
  properties: {
    workspaceId: monitoring.outputs.workspaceId
    logs: [
      {
        category: 'Administrative'
        enabled: true
      }
      {
        category: 'Security'
        enabled: true
      }
      {
        category: 'ServiceHealth'
        enabled: true
      }
      {
        category: 'Alert'
        enabled: true
      }
      {
        category: 'Recommendation'
        enabled: true
      }
      {
        category: 'Policy'
        enabled: true
      }
      {
        category: 'Autoscale'
        enabled: true
      }
      {
        category: 'ResourceHealth'
        enabled: true
      }
    ]
  }
}

module federation 'modules/federation.bicep' = {
  name: 'workload-identity-federation'
  scope: labResourceGroup
  params: {
    identityName: workloadIdentityName
    oidcIssuerUrl: aks.outputs.oidcIssuerUrl
    kubernetesNamespace: 'litellm'
    serviceAccountName: 'litellm'
  }
}

module modelRole 'modules/model-role.bicep' = {
  name: 'model-role-assignment'
  scope: resourceGroup(modelResourceGroupName)
  params: {
    modelAccountName: modelAccountName
    workloadPrincipalId: identity.outputs.principalId
  }
}

output aksName string = aks.outputs.aksName
output resourceGroup string = labResourceGroup.name
output workloadIdentityClientId string = identity.outputs.clientId
output workloadIdentityPrincipalId string = identity.outputs.principalId
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId
output actionGroupId string = alerts.outputs.actionGroupId
output nodeAutoRecoveryLogicAppId string = nodeAutoRecovery.outputs.logicAppId
output modelAccountResourceId string = modelRole.outputs.modelAccountResourceId
