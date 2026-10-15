param identityName string
param oidcIssuerUrl string
param kubernetesNamespace string
param serviceAccountName string
param federatedCredentialName string = 'litellm-service-account'

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: identityName
}

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: identity
  name: federatedCredentialName
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: oidcIssuerUrl
    subject: 'system:serviceaccount:${kubernetesNamespace}:${serviceAccountName}'
  }
}

output federatedCredentialName string = federatedCredential.name
