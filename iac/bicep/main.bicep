// Main Bicep template for Claim Status API infra
// Deploys: Resource Group scope (use az deployment group create) components:
// - Azure Container Registry (optional toggle)
// - Log Analytics Workspace
// - Container Apps Environment
// - Container App (image supplied)
// - API Management (Developer SKU) with backend + API placeholder
// NOTE: OpenAPI import & policies typically automated post-deploy (pipeline step)

param location string = resourceGroup().location
param namePrefix string = 'claimapi'
param deployAcr bool = true
param containerImage string // e.g. myregistry.azurecr.io/claimstatusapi:123
param openAiEndpoint string
param openAiDeployment string
param apimPublisherEmail string = 'admin@example.com'
param apimPublisherName string = 'Claims Team'
param apimSkuName string = 'Developer' // Developer, Basic, Standard (consider cost)
param containerCpu double = 0.5
param containerMemory string = '1Gi'
param minReplicas int = 1
param maxReplicas int = 2
// CORS handled at APIM layer; removed duplicate Container App CORS configuration

// Basic naming
var acrName = toLower(replace('${namePrefix}acr','-',''))
var lawName = '${namePrefix}-law'
var caeName = '${namePrefix}-cae'
var caName = '${namePrefix}-app'
var apimName = toLower('${namePrefix}-apim')

// ACR (optional)
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = if (deployAcr) {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

// Log Analytics
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: lawName
  location: location
  properties: {
    retentionInDays: 30
    features: { legacy: 0 }
  }
  sku: { name: 'PerGB2018' }
}

// Container Apps Environment
resource cae 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: caeName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: listKeys(logAnalytics.id, '2022-10-01').primarySharedKey
      }
    }
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: caName
  location: location
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
      }
      secrets: [
        { name: 'openai-endpoint', value: openAiEndpoint }
        { name: 'openai-deployment', value: openAiDeployment }
      ]
      registries: deployAcr ? [
        {
          server: acr.properties.loginServer
          identity: 'system'
        }
      ] : []
    }
    template: {
      containers: [
        {
          name: 'api'
          image: containerImage
          resources: {
            cpu: containerCpu
            memory: containerMemory
          }
          env: [
            { name: 'OpenAI__Endpoint', secretRef: 'openai-endpoint' }
            { name: 'OpenAI__Deployment', secretRef: 'openai-deployment' }
            { name: 'ASPNETCORE_URLS', value: 'http://+:8080' }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Grant Container App AcrPull access to the registry
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployAcr) {
  name: guid(acr.id, containerApp.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// API Management (minimal)
resource apim 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: apimName
  location: location
  sku: {
    name: apimSkuName
    capacity: 1
  }
  properties: {
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
  }
}

// Backend pointing to Container App FQDN
resource apimBackend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  name: '${apim.name}/claims-backend'
  properties: {
    // Use actual deployed FQDN from Container App ingress
    url: 'https://${containerApp.properties.configuration.ingress.fqdn}'
    protocol: 'http'
  }
  dependsOn: [ apim, containerApp ]
}

// Placeholder API (empty). OpenAPI import will overwrite.
resource apimApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  name: '${apim.name}/claims-api'
  properties: {
    displayName: 'Claims API'
    path: 'claims'
    protocols: [ 'https' ]
  }
  dependsOn: [ apimBackend ]
}

output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output apimNameOut string = apim.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output containerAppPrincipalId string = containerApp.identity.principalId
output containerAppName string = containerApp.name