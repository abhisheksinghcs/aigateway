param location string
param aksName string
param aksSubnetId string
param logAnalyticsWorkspaceId string
param tags object
param aksAdminPrincipalId string = ''

var aksRbacClusterAdminRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'
)

resource aks 'Microsoft.ContainerService/managedClusters@2025-01-01' = {
  name: aksName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    dnsPrefix: aksName
    enableRBAC: true
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    agentPoolProfiles: [
      {
        name: 'system'
        count: 2
        vmSize: 'Standard_D4as_v6'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: aksSubnetId
        enableAutoScaling: false
        maxPods: 110
        osDiskType: 'Managed'
        osDiskSizeGB: 64
        upgradeSettings: {
          maxSurge: '33%'
        }
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    autoUpgradeProfile: {
      nodeOSUpgradeChannel: 'NodeImage'
      upgradeChannel: 'patch'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
    }
  }
}

resource aksAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aksAdminPrincipalId)) {
  name: guid(aks.id, aksAdminPrincipalId, aksRbacClusterAdminRoleDefinitionId)
  scope: aks
  properties: {
    principalId: aksAdminPrincipalId
    principalType: 'User'
    roleDefinitionId: aksRbacClusterAdminRoleDefinitionId
    description: 'Grants the deployment principal administrative Kubernetes RBAC access to this demo cluster.'
  }
}

resource containerInsightsDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'MSCI-${location}-${aksName}'
  location: location
  kind: 'Linux'
  tags: tags
  properties: {
    dataSources: {
      extensions: [
        {
          extensionName: 'ContainerInsights'
          extensionSettings: {
            dataCollectionSettings: {
              enableContainerLogV2: true
            }
          }
          name: 'ContainerInsightsExtension'
          streams: [
            'Microsoft-ContainerInsights-Group-Default'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'la-workspace'
          workspaceResourceId: logAnalyticsWorkspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ContainerInsights-Group-Default'
        ]
        destinations: [
          'la-workspace'
        ]
      }
    ]
  }
}

resource containerInsightsAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'ContainerInsightsExtension'
  scope: aks
  properties: {
    dataCollectionRuleId: containerInsightsDcr.id
    description: 'Associates the Container Insights data collection rule with AKS.'
  }
}

resource controlPlaneDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'aks-control-plane'
  scope: aks
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
      }
      {
        category: 'kube-audit-admin'
        enabled: true
      }
      {
        category: 'kube-controller-manager'
        enabled: true
      }
      {
        category: 'kube-scheduler'
        enabled: true
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
      }
      {
        category: 'cloud-controller-manager'
        enabled: true
      }
      {
        category: 'guard'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output aksName string = aks.name
output aksResourceId string = aks.id
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL!
