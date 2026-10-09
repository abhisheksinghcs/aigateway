param location string
param vnetName string
param tags object

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
      }
      {
        name: 'snet-private-endpoints'
        addressPrefix: '10.40.4.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
      }
    ]
    tags: tags
    enableTelemetry: false
  }
}

output vnetId string = vnet.outputs.resourceId
output aksSubnetId string = vnet.outputs.subnetResourceIds[0]
output privateEndpointSubnetId string = vnet.outputs.subnetResourceIds[1]
