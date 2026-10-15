targetScope = 'subscription'

@description('Azure region for the middleware identity and container registry.')
param location string = 'eastus2'

@description('Resource group containing the existing AKS cluster.')
param workloadResourceGroupName string = 'rg-litellm-gateway-demo-eus2'

@description('Dedicated user-assigned identity used only by the Foundry middleware.')
param middlewareIdentityName string = 'litellm-demo-foundry-middleware-id'

@description('Globally unique Azure Container Registry name.')
param registryName string = 'litellmdemokhtkwbank4rg6'

@description('Object ID of the existing AKS kubelet identity that pulls images.')
param aksKubeletPrincipalId string

@description('OIDC issuer URL of the existing AKS cluster.')
param aksOidcIssuerUrl string

@description('Resource group containing the existing Foundry account and project.')
param foundryResourceGroupName string = 'MC-abhi'

@description('Existing Foundry account name.')
param foundryAccountName string = 'Agent365-Teams-Agents'

@description('Existing Foundry project name.')
param foundryProjectName string = 'Agent365-Teams-Agents'

@description('Tags applied to middleware-owned Azure resources.')
param tags object = {
  environment: 'demo'
  workload: 'litellm-foundry-middleware'
  managedBy: 'bicep'
}

var foundryAccountResourceId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${foundryResourceGroupName}/providers/Microsoft.CognitiveServices/accounts/${foundryAccountName}'

resource workloadResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: workloadResourceGroupName
}

resource foundryResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: foundryResourceGroupName
}

module middlewareIdentity 'modules/identity.bicep' = {
  name: 'foundry-middleware-identity'
  scope: workloadResourceGroup
  params: {
    location: location
    identityName: middlewareIdentityName
    tags: tags
  }
}

module middlewareFederation 'modules/federation.bicep' = {
  name: 'foundry-middleware-federation'
  scope: workloadResourceGroup
  dependsOn: [
    middlewareIdentity
  ]
  params: {
    identityName: middlewareIdentityName
    oidcIssuerUrl: aksOidcIssuerUrl
    kubernetesNamespace: 'litellm'
    serviceAccountName: 'litellm-foundry-middleware'
    federatedCredentialName: 'foundry-middleware-service-account'
  }
}

module registry 'modules/middleware-registry.bicep' = {
  name: 'foundry-middleware-registry'
  scope: workloadResourceGroup
  params: {
    location: location
    registryName: registryName
    aksKubeletPrincipalId: aksKubeletPrincipalId
    tags: tags
  }
}

resource userIdentityImpersonationRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'foundry-agent-user-identity-impersonation')
  properties: {
    roleName: 'Foundry Agent User Identity Impersonation'
    description: 'Lets the trusted middleware delegate a validated end-user identity to a Foundry hosted agent.'
    type: 'CustomRole'
    permissions: [
      {
        actions: []
        notActions: []
        dataActions: [
          'Microsoft.CognitiveServices/accounts/AIServices/agents/endpoints/UserIdentityImpersonation/action'
        ]
        notDataActions: []
      }
    ]
    assignableScopes: [
      foundryAccountResourceId
    ]
  }
}

module foundryAccess 'modules/middleware-foundry-access.bicep' = {
  name: 'foundry-middleware-project-access'
  scope: foundryResourceGroup
  params: {
    foundryAccountName: foundryAccountName
    foundryProjectName: foundryProjectName
    middlewareIdentityName: middlewareIdentityName
    middlewarePrincipalId: middlewareIdentity.outputs.principalId
    userIdentityImpersonationRoleDefinitionId: userIdentityImpersonationRole.id
  }
}

output middlewareIdentityClientId string = middlewareIdentity.outputs.clientId
output middlewareIdentityPrincipalId string = middlewareIdentity.outputs.principalId
output registryLoginServer string = registry.outputs.loginServer
