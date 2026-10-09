param modelAccountName string
param workloadPrincipalId string

resource modelAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: modelAccountName
}

resource modelUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(modelAccount.id, workloadPrincipalId, 'Cognitive Services OpenAI User')
  scope: modelAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    )
    principalId: workloadPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allows the LiteLLM workload identity to invoke Azure OpenAI model deployments.'
  }
}

output modelAccountResourceId string = modelAccount.id
