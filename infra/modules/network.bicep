param location string
param vnetName string
param tags object

resource aksSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${vnetName}-snet-aks-nsg-${location}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowPublicIngressHttpHttps'
        properties: {
          description: 'Allow public HTTP and HTTPS traffic to the AKS ingress load balancer.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource privateEndpointSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${vnetName}-snet-private-endpoints-nsg-${location}'
  location: location
  tags: tags
}

module vnet 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'virtual-network'
  params: {
    name: vnetName
    location: location
    addressPrefixes: [
      '10.40.0.0/16'
    ]
    subnets: [
      {
        name: 'snet-aks'
        addressPrefix: '10.40.0.0/22'
        privateEndpointNetworkPolicies: 'Disabled'
        networkSecurityGroupResourceId: aksSubnetNsg.id
      }
      {
        name: 'snet-private-endpoints'
        addressPrefix: '10.40.4.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
        networkSecurityGroupResourceId: privateEndpointSubnetNsg.id
      }
    ]
    tags: tags
    enableTelemetry: false
  }
}

output vnetId string = vnet.outputs.resourceId
output aksSubnetId string = vnet.outputs.subnetResourceIds[0]
output privateEndpointSubnetId string = vnet.outputs.subnetResourceIds[1]
