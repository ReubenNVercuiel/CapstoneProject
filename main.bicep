param location string = resourceGroup().location
param nameSuffix string = 'mbrg-capstone-project-${(resourceGroup().id)}'

// Stack configuration

@description('The Things Stack Cluster HTTP Address')
param stackClusterAddress string = 'https://mdrgconsulting.nam1.cloud.thethings.industries/api/v3'

@description('The Things Stack Application ID')
param stackApplicationID string = 'capstone-smartfarming'

@secure()
@description('The Things Stack API Key')
param stackAPIKey string = 'NNSXS.IWGII4PFVCT2R3LTDMMPCMHLDFLARKZWXVT47DA.7SGK4F6ECTDY2U5BDO2NZJLF433X4UOULWBGK7532PCTCIPWYVQQ'

// B2C Creation
param b2cTenantName string = 'mbrg-capstone-project-B2C-Tenant'
param b2cLocation string = location

// SKU configuration
var eventHubNameSpaceSKU = 'Standard'
var iotHubSKU = 'F1'
var iotHubCapacity = 1
var storageAccountSKU = 'Standard_LRS'
var appServicePlanSKU = 'Y1'
var appServicePlanTier = 'Dynamic'
var b2cSKU = 'PremiumP1'
var b2cTier = 'A0'

// IoT Hub configuration
@description('If enabled, the default IoT Hub fallback route will be added')
param enableFallbackRoute bool = true

//Database admin Username and pass
param adminUsername string = 'sql-Admin'

@secure()
param adminPassword string = 'sql-Admin-Pass'

// Resource names
var functionAppName = 'fn-${nameSuffix}'
var appServicePlanName = 'aps-${nameSuffix}'
var appInsightsName = 'ai-${nameSuffix}'
var storageAccountName = 'fnstor${replace(nameSuffix, '-', '')}'
var eventHubNamespaceName = 'evhubns-${nameSuffix}'
var iotHubName = 'iothub-${nameSuffix}'

var functionName = 'SubmitEvents'
var functionFullName = '${functionApp.name}/${functionName}'
var eventHubName = 'Events'
var eventHubFullName = '${eventHubNamespace.name}/${eventHubName}'
var eventHubEndpointName = 'StackEvents'
var sqlServerName = 'sqp-${nameSuffix}'
var sqlDatabaseName = 'userDB-${nameSuffix}'


// Outputs
output iotHubHostname string = iotHub.properties.hostName
output iotHubOwnerKey string = iotHub.listKeys().value[0].primaryKey
output b2cTenantId string = b2c.properties.tenantId
output sqlDatabaseConnectionString string = 'Server=tcp:${sqlServerName}.database.windows.net,1433;Initial Catalog=${sqlDatabaseName};Persist Security Info=False;User ID=${adminUsername};Password=${adminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

// Resources
resource b2c 'Microsoft.AzureActiveDirectory/b2cDirectories@2023-05-17-preview' = {
  name:b2cTenantName
  location: b2cLocation
  properties: {
    createTenantProperties: {
      countryCode: 'CA'
      displayName: 'MBRG Consulting'
    }
  }
  sku: {
    name: b2cSKU
    tier: b2cTier
  }
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword:adminPassword
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview'= {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  properties: {
    collation:'SQL_Latin1_General_CP1_CI_AS'
  }
}

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubNamespaceName
  location: location
  sku: {
    name: eventHubNameSpaceSKU
  }
  properties: {}
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  name: eventHubFullName
  properties: {}
}

resource eventHubSendAuth 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2023-01-01-preview' = {
  parent: eventHub
  name: 'Send'
  properties: {
    rights: [
      'Send'
    ]
  }
}

resource eventHubListenAuth 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2023-01-01-preview' = {
  parent: eventHub
  name: 'Listen'
  properties: {
    rights: [
      'Listen'
    ]
  }
}

resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: iotHubName
  location: location
  sku: {
    name: iotHubSKU
    capacity: iotHubCapacity
  }
  properties: {
    routing: {
      endpoints: {
        eventHubs: [
          {
            name: eventHubEndpointName
            connectionString: eventHubSendAuth.listKeys().primaryConnectionString
          }
        ]
      }
      routes: [
        {
          name: 'TTSTwinChangeEvents'
          isEnabled: true
          source: 'TwinChangeEvents'
          condition: 'IS_OBJECT($body.properties.desired) OR IS_OBJECT($body.tags)'
          endpointNames: [
            eventHubEndpointName
          ]
        }
        {
          name: 'TTSDeviceLifecycleEvents'
          isEnabled: true
          source: 'DeviceLifecycleEvents'
          endpointNames: [
            eventHubEndpointName
          ]
        }
      ]
      fallbackRoute: enableFallbackRoute
        ? {
            name: 'FallbackRoute'
            isEnabled: true
            source: 'DeviceMessages'
            endpointNames: [
              'events'
            ]
          }
        : null
    }
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountSKU
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: appServicePlanSKU
    tier: appServicePlanTier
  }
  properties: {}
}

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${appInsights.properties.InstrumentationKey}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'EVENTHUB_CONNECTION_STRING'
          value: eventHubListenAuth.listKeys().primaryConnectionString
        }
        {
          name: 'STACK_BASE_URL'
          value: stackClusterAddress
        }
        {
          name: 'STACK_APPLICATION_ID'
          value: stackApplicationID
        }
        {
          name: 'STACK_API_KEY'
          value: stackAPIKey
        }
      ]
    }
    httpsOnly: true
  }
}

resource function 'Microsoft.Web/sites/functions@2022-09-01' = {
  name: functionFullName
  properties: {
    config: {
      disabled: false
      scriptFile: 'run.csx'
      bindings: [
        {
          type: 'eventHubTrigger'
          name: 'events'
          direction: 'in'
          eventHubName: eventHubName
          connection: 'EVENTHUB_CONNECTION_STRING'
          cardinality: 'many'
          consumerGroup: '$Default'
          dataType: 'binary'
        }
      ]
    }
    files: {
      'run.csx': loadTextContent('./fns/SubmitEvents/run.csx')
      'function.proj': loadTextContent('./fns/SubmitEvents/function.proj')
    }
  }
}
