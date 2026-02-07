@description('Azure region for deployment')
param location string = resourceGroup().location

@minLength(3)
@maxLength(10)
@description('Short prefix used for naming resources')
param prefix string = 'pese'

@description('Environment tag (dev/test/prod)')
param environment string = 'dev'

@description('Address space for the VNet')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Subnet prefix for Service Endpoint subnet')
param subnetServiceEndpointPrefix string = '10.20.1.0/24'

@description('Subnet prefix for Private Endpoint subnet')
param subnetPrivateEndpointPrefix string = '10.20.2.0/24'

@description('Subnet prefix for VM/test subnet')
param subnetVmPrefix string = '10.20.3.0/24'

@description('Name for the Storage Account (must be globally unique, 3-24 lowercase letters and numbers)')
@minLength(3)
@maxLength(24)
param storageAccountName string

@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
])
@description('Storage account SKU')
param storageSku string = 'Standard_LRS'

@allowed([
  'StorageV2'
])
@description('Storage account kind')
param storageKind string = 'StorageV2'

@description('Enable a small Linux VM to validate connectivity from inside the VNet')
param deployTestVm bool = false

@description('Admin username for the test VM (only used if deployTestVm=true)')
param vmAdminUsername string = 'azureuser'

@secure()
@description('Admin password for the test VM (only used if deployTestVm=true)')
param vmAdminPassword string = ''

@description('Allowed public IP CIDR(s) for SSH to the test VM (only used if deployTestVm=true). Example: ["1.2.3.4/32"]')
param allowedSshCidrs array = []

// --------------------
// Derived names
// --------------------
var vnetName = 'vnet-${prefix}-${environment}-${uniqueString(resourceGroup().id)}'
var snetSeName = 'snet-se'
var snetPeName = 'snet-pe'
var snetVmName = 'snet-vm'

var privateDnsZoneName = 'privatelink.blob.core.windows.net'
var privateEndpointName = 'pe-blob-${prefix}-${environment}'
var nicName = 'nic-${prefix}-${environment}'
var vmName = 'vm-${prefix}-${environment}'
var nsgVmName = 'nsg-${prefix}-${environment}-vm'

// --------------------
// VNet (NO inline subnets here)
// --------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: {
    env: environment
    project: 'service-endpoint-vs-private-endpoint'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

// --------------------
// Optional NSG for VM subnet (only if deployTestVm=true)
// --------------------
resource nsgVm 'Microsoft.Network/networkSecurityGroups@2023-11-01' = if (deployTestVm) {
  name: nsgVmName
  location: location
  tags: {
    env: environment
    project: 'service-endpoint-vs-private-endpoint'
  }
  properties: {
    securityRules: [
      for (cidr, i) in allowedSshCidrs: {
        name: 'Allow-SSH-${i}'
        properties: {
          priority: 100 + i
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: cidr
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// --------------------
// Subnets (defined ONCE, with full properties)
// --------------------
resource snetSe 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: snetSeName
  properties: {
    addressPrefix: subnetServiceEndpointPrefix
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
    ]
  }
}

resource snetPe 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: snetPeName
  properties: {
    addressPrefix: subnetPrivateEndpointPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource snetVm 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: snetVmName
  properties: {
    addressPrefix: subnetVmPrefix
    networkSecurityGroup: deployTestVm ? {
      id: nsgVm.id
    } : null
  }
}

// --------------------
// Storage Account (deny public access; allow via Service Endpoint subnet + Private Endpoint)
// --------------------
resource stg 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: storageKind
  sku: {
    name: storageSku
  }
  tags: {
    env: environment
    project: 'service-endpoint-vs-private-endpoint'
  }
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: snetSe.id
          action: 'Allow'
        }
      ]
      ipRules: []
    }
  }
}

// --------------------
// Private DNS Zone + VNet link
// --------------------
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: {
    env: environment
    project: 'service-endpoint-vs-private-endpoint'
  }
}

resource dnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-${vnet.name}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// --------------------
// Private Endpoint to Storage Blob + DNS Zone Group
// --------------------
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: privateEndpointName
  location: location
  tags: {
    env: environment
    project: 'service-endpoint-vs-private-endpoint'
  }
  properties: {
    subnet: {
      id: snetPe.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-blob'
        properties: {
          privateLinkServiceId: stg.id
          groupIds: [
            'blob'
          ]
          requestMessage: 'Private endpoint for Blob access'
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob-zone'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// --------------------
// Optional Test VM (Linux)
// --------------------
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = if (deployTestVm) {
  name: 'pip-${prefix}-${environment}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = if (deployTestVm) {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: snetVm.id
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = if (deployTestVm) {
  name: vmName
  location: location
  tags: {
    env: environment
    project: 'service-endpoint-vs-private-endpoint'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// --------------------
// Outputs
// --------------------
output vnetDeployedName string = vnet.name
output storageDeployedName string = stg.name
output privateEndpointId string = privateEndpoint.id
output privateDnsZone string = privateDnsZone.name
output testVmPublicIp string = deployTestVm ? publicIp.properties.ipAddress : 'not-deployed'
