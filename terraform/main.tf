terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Variables
variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "blue-green-deployment-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "app_service_name" {
  description = "Name of the App Service"
  type        = string
  default     = "bg-deployment-app"
}

variable "app_service_plan_name" {
  description = "Name of the App Service Plan"
  type        = string
  default     = "bg-deployment-plan"
}

variable "environment_tag" {
  description = "Environment tag"
  type        = string
  default     = "dev"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = var.environment_tag
    project     = "blue-green-deployment"
  }
}

# App Service Plan (S1 tier for blue/green deployment slots support)
# S1 tier is required for slot swap functionality
resource "azurerm_service_plan" "main" {
  name                = var.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "S1"  # S1 tier - required for deployment slots

  tags = {
    environment = var.environment_tag
  }
}

# App Service
resource "azurerm_linux_web_app" "main" {
  name                = var.app_service_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id

  https_only = true

  site_config {
    application_stack {
      node_version = "18-lts"
    }

    # Health check configuration
    health_check_path = "/health"
  }

  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = false
    ENVIRONMENT                          = "blue"
    APP_VERSION                          = "1.0.0"
  }

  tags = {
    environment = var.environment_tag
  }

  lifecycle {
    ignore_changes = [
      app_settings["ENVIRONMENT"],
      app_settings["APP_VERSION"],
      app_settings["SIMULATE_FAILURE"]
    ]
  }
}

# Deployment Slot (Green)
resource "azurerm_linux_web_app_slot" "green" {
  name           = "green"
  app_service_id = azurerm_linux_web_app.main.id

  site_config {
    application_stack {
      node_version = "18-lts"
    }

    health_check_path = "/health"
  }

  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = false
    ENVIRONMENT                          = "green"
    APP_VERSION                          = "1.0.0"
  }

  tags = {
    environment = var.environment_tag
  }

  lifecycle {
    ignore_changes = [
      app_settings["ENVIRONMENT"],
      app_settings["APP_VERSION"],
      app_settings["SIMULATE_FAILURE"]
    ]
  }
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.app_service_name}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    environment = var.environment_tag
  }
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "${var.app_service_name}-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "Node.JS"

  tags = {
    environment = var.environment_tag
  }
}

# Outputs
output "app_service_default_hostname" {
  value       = azurerm_linux_web_app.main.default_hostname
  description = "Default hostname of the App Service"
}

output "app_service_id" {
  value       = azurerm_linux_web_app.main.id
  description = "ID of the App Service"
}

output "green_slot_hostname" {
  value       = azurerm_linux_web_app_slot.green.default_hostname
  description = "Hostname of the green deployment slot"
}

output "application_insights_instrumentation_key" {
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
  description = "Application Insights instrumentation key"
}