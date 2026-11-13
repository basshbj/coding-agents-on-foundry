locals {
  scope_id    = uuidv5("dns", "${var.tenant_id}.${var.name_prefix}.Codex.Access")
  app_role_id = uuidv5("dns", "${var.tenant_id}.${var.name_prefix}.Codex.User")
  model_names = toset([for model in var.models : lower(trimspace(model))])
}

resource "azurerm_resource_group" "this" {
  name     = coalesce(var.resource_group_name, "${var.name_prefix}-rg")
  location = var.location
  tags     = var.tags
}

resource "azurerm_api_management" "this" {
  name                          = "${var.name_prefix}-apim"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  publisher_name                = var.publisher_name
  publisher_email               = var.publisher_email
  sku_name                      = var.apim_sku_name
  virtual_network_type          = "None"
  public_network_access_enabled = true
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_cognitive_account" "this" {
  name                          = "${var.name_prefix}-foundry"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = "${var.name_prefix}-foundry"
  project_management_enabled    = true
  local_auth_enabled            = false
  public_network_access_enabled = true
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Allow"
    bypass         = "None"
  }
}

resource "azurerm_cognitive_deployment" "this" {
  for_each = local.model_names

  name                   = each.key
  cognitive_account_id   = azurerm_cognitive_account.this.id
  version_upgrade_option = "NoAutoUpgrade"

  model {
    format = "OpenAI"
    name   = each.value
  }

  sku {
    name     = var.model_deployment_sku_name
    capacity = var.model_deployment_capacity
  }
}

resource "azurerm_role_assignment" "inference" {
  scope                = azurerm_cognitive_account.this.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-logs"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "apim" {
  name                       = "platform-metrics"
  target_resource_id         = azurerm_api_management.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "foundry" {
  name                       = "platform-metrics"
  target_resource_id         = azurerm_cognitive_account.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "AllMetrics"
  }
}
