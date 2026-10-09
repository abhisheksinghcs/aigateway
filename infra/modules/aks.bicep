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

output aksName string = aks.name
output aksResourceId string = aks.id
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL!
