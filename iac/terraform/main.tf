###############################################
# Terraform for Claim Status API infrastructure
###############################################
# Components:
# - Resource Group (optional toggle)
# - ACR (optional)
# - Log Analytics
# - Container Apps Environment + Container App
# - API Management (Developer SKU) + Backend placeholder
# NOTE: Import OpenAPI & apply policies post-provision (pipeline)

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.90.0"
    }
  }
}

provider "azurerm" {
  features {}
}

###############################################
# Variables
###############################################
variable "resource_group_name" {}
variable "location" { default = "eastus" }
variable "name_prefix" { default = "claimapi" }
variable "deploy_acr" { type = bool default = true }
variable "container_image" { description = "Full image reference (registry/repo:tag)" }
variable "openai_endpoint" {}
variable "openai_deployment" {}
variable "apim_publisher_email" { default = "admin@example.com" }
variable "apim_publisher_name" { default = "Claims Team" }
variable "apim_sku" { default = "Developer" }
variable "container_cpu" { default = 0.5 }
variable "container_memory" { default = "1Gi" }
variable "min_replicas" { default = 1 }
variable "max_replicas" { default = 2 }
// CORS centralized at APIM; omit Container App CORS to avoid duplication

###############################################
# (Optional) Resource Group data / creation
###############################################
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

locals {
  acr_name  = lower(replace("${var.name_prefix}acr", "-", ""))
  law_name  = "${var.name_prefix}-law"
  cae_name  = "${var.name_prefix}-cae"
  app_name  = "${var.name_prefix}-app"
  apim_name = lower("${var.name_prefix}-apim")
}

###############################################
# ACR (optional)
###############################################
resource "azurerm_container_registry" "acr" {
  count                = var.deploy_acr ? 1 : 0
  name                 = local.acr_name
  resource_group_name  = data.azurerm_resource_group.rg.name
  location             = data.azurerm_resource_group.rg.location
  sku                  = "Basic"
  admin_enabled        = false
}

###############################################
# Log Analytics
###############################################
resource "azurerm_log_analytics_workspace" "law" {
  name                = local.law_name
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

###############################################
# Container Apps Environment
###############################################
resource "azapi_resource" "cae" {
  type      = "Microsoft.App/managedEnvironments@2023-05-01"
  name      = local.cae_name
  location  = data.azurerm_resource_group.rg.location
  parent_id = data.azurerm_resource_group.rg.id
  body = jsonencode({
    properties = {
      appLogsConfiguration = {
        destination = "log-analytics"
        logAnalyticsConfiguration = {
          customerId = azurerm_log_analytics_workspace.law.workspace_id
          sharedKey  = azurerm_log_analytics_workspace.law.primary_shared_key
        }
      }
    }
  })
}

###############################################
# Container App (with System MSI)
###############################################
resource "azapi_resource" "app" {
  type      = "Microsoft.App/containerApps@2023-05-01"
  name      = local.app_name
  location  = data.azurerm_resource_group.rg.location
  parent_id = data.azurerm_resource_group.rg.id
  identity = {
    type = "SystemAssigned"
  }
  body = jsonencode({
    properties = {
      managedEnvironmentId = azapi_resource.cae.id
      configuration = {
        ingress = {
          external   = true
          targetPort = 8080
          transport  = "auto"
        }
        secrets = [
          { name = "openai-endpoint", value = var.openai_endpoint },
          { name = "openai-deployment", value = var.openai_deployment }
        ]
      }
      template = {
        containers = [
          {
            name  = "api"
            image = var.container_image
            resources = {
              cpu    = var.container_cpu
              memory = var.container_memory
            }
            env = [
              { name = "OpenAI__Endpoint", secretRef = "openai-endpoint" },
              { name = "OpenAI__Deployment", secretRef = "openai-deployment" },
              { name = "ASPNETCORE_URLS", value = "http://+:8080" }
            ]
          }
        ]
        scale = {
          minReplicas = var.min_replicas
          maxReplicas = var.max_replicas
        }
      }
    }
  })
  depends_on = [azapi_resource.cae]
}

###############################################
# API Management
###############################################
resource "azurerm_api_management" "apim" {
  name                = local.apim_name
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  publisher_email     = var.apim_publisher_email
  publisher_name      = var.apim_publisher_name
  sku_name            = "${var.apim_sku}_1"
}

###############################################
# APIM Backend to Container App
###############################################
resource "azurerm_api_management_backend" "claims_backend" {
  name                = "claims-backend"
  resource_group_name = data.azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  protocol            = "http"
  url                 = "https://${azapi_resource.app.output.properties.configuration.ingress.fqdn}"
  description         = "Claims API Container App backend"
}

###############################################
# Outputs
###############################################
output "container_app_fqdn" {
  value = azapi_resource.app.output.properties.configuration.ingress.fqdn
}
output "log_analytics_id" { value = azurerm_log_analytics_workspace.law.id }
output "apim_name" { value = azurerm_api_management.apim.name }
