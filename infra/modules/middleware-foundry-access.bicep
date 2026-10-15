param foundryAccountName string
param foundryProjectName string
param middlewareIdentityName string
param middlewarePrincipalId string
param userIdentityImpersonationRoleDefinitionId string

var foundryAgentConsumerRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'eed3b665-ab3a-47b6-8f48-c9382fb1dad6'
)

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  name: '${foundryAccountName}/${foundryProjectName}'
}

resource foundryConsumerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryProject
  name: guid(foundryProject.id, middlewareIdentityName, 'Foundry Agent Consumer')
  properties: {
    principalId: middlewarePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: foundryAgentConsumerRoleDefinitionId
  }
}

resource userIdentityImpersonationAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryProject
  name: guid(foundryProject.id, middlewareIdentityName, 'Foundry Agent User Identity Impersonation')
  properties: {
    principalId: middlewarePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: userIdentityImpersonationRoleDefinitionId
  }
}
