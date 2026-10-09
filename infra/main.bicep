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
output modelAccountResourceId string = modelRole.outputs.modelAccountResourceId
