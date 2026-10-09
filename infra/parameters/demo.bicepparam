using '../main.bicep'

param location = 'eastus2'
param resourceGroupName = 'rg-litellm-gateway-demo-eus2'
param resourcePrefix = 'litellm-demo'
param modelResourceGroupName = 'MC-abhi'
param modelAccountName = 'Agent365-Teams-Agents'

param tags = {
  environment: 'demo'
  workload: 'litellm-ai-gateway'
  managedBy: 'bicep'
}
