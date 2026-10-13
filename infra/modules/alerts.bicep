param location string
param workspaceId string
param nodeResourceGroupId string
param alertEmail string = ''
param tags object

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'litellm-aks-operations'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'aks-ops'
    enabled: true
    emailReceivers: empty(alertEmail)
      ? []
      : [
          {
            name: 'deployment-owner'
            emailAddress: alertEmail
            useCommonAlertSchema: true
          }
        ]
  }
}

resource nodeLifecycleAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'litellm-aks-node-compute-lifecycle'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [
      nodeResourceGroupId
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          anyOf: [
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/deallocate/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/powerOff/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/redeploy/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/reimage/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/restart/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/delete'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/write'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/deallocate/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/powerOff/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/redeploy/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/reimage/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/restart/action'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/delete'
            }
            {
              field: 'operationName'
              equals: 'Microsoft.Compute/virtualMachineScaleSets/virtualMachines/write'
            }
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
    description: 'Alerts on VMSS and VM instance lifecycle operations in the AKS managed resource group.'
  }
}

resource nodeResourceHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'litellm-aks-node-resource-health'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [
      nodeResourceGroupId
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          field: 'properties.currentHealthStatus'
          containsAny: [
            'Degraded'
            'Unavailable'
            'Unknown'
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
    description: 'Alerts when AKS-managed compute reports degraded, unavailable, or unknown Azure resource health.'
  }
}

resource nodeNotReadyAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'litellm-aks-node-not-ready'
  location: location
  tags: tags
  properties: {
    displayName: 'LiteLLM AKS node is not Ready or stopped reporting'
    description: 'Alerts when fewer than two AKS nodes report within ten minutes or the latest node state is not Ready.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [
      workspaceId
    ]
    criteria: {
      allOf: [
        {
          query: 'KubeNodeInventory | where TimeGenerated > ago(10m) | summarize arg_max(TimeGenerated, Status) by Computer | summarize ReportingNodes=count(), UnreadyNodes=countif(Status !~ "Ready") | where ReportingNodes < 2 or UnreadyNodes > 0'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

output actionGroupId string = actionGroup.id
