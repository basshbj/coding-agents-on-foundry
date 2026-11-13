mock_provider "azurerm" {
  mock_resource "azurerm_api_management" {
    defaults = {
      id                  = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/test-rg/providers/Microsoft.ApiManagement/service/test-apim"
      public_ip_addresses = []
      gateway_url         = "https://test-apim.azure-api.net"
      identity = {
        type         = "SystemAssigned"
        principal_id = "22222222-2222-2222-2222-222222222222"
        tenant_id    = "33333333-3333-3333-3333-333333333333"
      }
    }
  }

  mock_resource "azurerm_cognitive_account" {
    defaults = {
      id       = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/test-rg/providers/Microsoft.CognitiveServices/accounts/test-foundry"
      endpoint = "https://test-foundry.cognitiveservices.azure.com/"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test-logs"
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_user" {
    defaults = {
      object_id = "99999999-9999-9999-9999-999999999999"
    }
  }

  mock_data "azuread_group" {
    defaults = {
      object_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    }
  }

  mock_data "azuread_client_config" {
    defaults = {
      object_id = "44444444-4444-4444-4444-444444444444"
    }
  }

  mock_resource "azuread_application" {
    defaults = {
      id        = "/applications/55555555-5555-5555-5555-555555555555"
      client_id = "66666666-6666-6666-6666-666666666666"
    }
  }

  mock_resource "azuread_service_principal" {
    defaults = {
      object_id = "77777777-7777-7777-7777-777777777777"
    }
  }
}

variables {
  resource_group_name       = null
  tags                      = {}
  apim_sku_name             = "StandardV2_1"
  allowed_user_emails       = []
  allowed_group_names       = []
  oauth_redirect_port       = 43127
  requests_per_minute       = 60
  log_retention_days        = 30
  model_deployment_sku_name = "Standard"
  model_deployment_capacity = 1
  subscription_id           = "11111111-1111-1111-1111-111111111111"
  tenant_id                 = "33333333-3333-3333-3333-333333333333"
  name_prefix               = "codex-test"
  location                  = "eastus2"
  publisher_name            = "Test"
  publisher_email           = "test@example.com"
  allowed_principal_object_ids = [
    "88888888-8888-8888-8888-888888888888",
  ]
  models = ["Codex"]
}

run "public_standard_v2_foundry_baseline" {
  command = apply

  assert {
    condition     = azurerm_resource_group.this.name == "codex-test-rg"
    error_message = "The configuration must create a resource group derived from the prefix."
  }

  assert {
    condition     = azurerm_api_management.this.sku_name == "StandardV2_1" && azurerm_api_management.this.virtual_network_type == "None" && azurerm_api_management.this.public_network_access_enabled
    error_message = "Use public Standard v2 without a VNet."
  }

  assert {
    condition = (
      !azurerm_cognitive_account.this.local_auth_enabled &&
      azurerm_cognitive_account.this.kind == "AIServices" &&
      azurerm_cognitive_account.this.project_management_enabled &&
      azurerm_cognitive_account.this.name == "codex-test-foundry" &&
      azurerm_cognitive_account.this.public_network_access_enabled &&
      one(azurerm_cognitive_account.this.network_acls).default_action == "Allow" &&
      one(azurerm_cognitive_account.this.network_acls).bypass == "None" &&
      length(coalesce(one(azurerm_cognitive_account.this.network_acls).ip_rules, toset([]))) == 0
    )
    error_message = "Create a project-enabled Foundry resource with public network access, no APIM IP dependency, and disabled key authentication."
  }

  assert {
    condition     = length(azurerm_cognitive_account.this.identity) == 1 && azurerm_cognitive_account.this.identity[0].type == "SystemAssigned"
    error_message = "Project-enabled Foundry requires its own managed identity, separate from APIM's managed identity."
  }

  assert {
    condition = (
      azurerm_role_assignment.inference.scope == azurerm_cognitive_account.this.id &&
      azurerm_role_assignment.inference.principal_id == azurerm_api_management.this.identity[0].principal_id &&
      azurerm_role_assignment.inference.role_definition_name == "Cognitive Services OpenAI User"
    )
    error_message = "Grant the APIM identity, not Foundry's identity, inference access scoped to Foundry."
  }

  assert {
    condition = (
      azuread_application.gateway.api[0].requested_access_token_version == 2 &&
      azuread_application_pre_authorized.codex.authorized_client_id == azuread_application.codex.client_id &&
      azuread_application_pre_authorized.codex.permission_ids == toset([local.scope_id]) &&
      azuread_application.codex.public_client[0].redirect_uris == toset(["http://127.0.0.1:43127/callback"])
    )
    error_message = "OAuth must use v2 gateway tokens, the delegated scope, and the registered Codex loopback callback."
  }

  assert {
    condition     = azuread_service_principal.gateway.app_role_assignment_required && length(azuread_app_role_assignment.users) == 1
    error_message = "The gateway must require explicit user/group assignment."
  }

  assert {
    condition = (
      strcontains(azurerm_api_management_api_policy.responses.xml_content, "<value>Codex.Access</value>") &&
      strcontains(azurerm_api_management_api_policy.responses.xml_content, "<value>Codex.User</value>") &&
      strcontains(azurerm_api_management_api_policy.responses.xml_content, "buffer-response=\"false\"") &&
      strcontains(azurerm_api_management_api_policy.responses.xml_content, "preserveContent: true") &&
      strcontains(azurerm_api_management_api_policy.responses.xml_content, "authentication-managed-identity")
    )
    error_message = "The gateway must enforce user authorization, preserve the body, use managed identity, and stream responses."
  }

  assert {
    condition     = !azurerm_api_management_api.responses.subscription_required && azurerm_api_management_api.responses.service_url == "https://codex-test-foundry.services.ai.azure.com/openai/v1"
    error_message = "The API must use OAuth instead of keys and route to Foundry's OpenAI-compatible v1 endpoint exactly once."
  }

  assert {
    condition     = output.codex_connection.base_url == "https://test-apim.azure-api.net/openai/v1" && toset(output.model_deployment_names) == toset(["codex"])
    error_message = "Codex handoff values must match the provisioned API and deployments."
  }

  assert {
    condition     = output.foundry_resource_name == "codex-test-foundry" && output.foundry_openai_base_url == azurerm_api_management_api.responses.service_url
    error_message = "Foundry handoff outputs must match the created resource and routed endpoint."
  }
}

run "custom_resource_group" {
  command = plan

  variables {
    resource_group_name = "custom-new-rg"
    apim_sku_name       = "StandardV2_10"
  }

  assert {
    condition     = azurerm_resource_group.this.name == "custom-new-rg" && azurerm_api_management.this.sku_name == "StandardV2_10"
    error_message = "Resource group name and Standard v2 capacity must be configurable up to 10 units."
  }
}

run "reject_classic_standard" {
  command = plan

  variables {
    apim_sku_name = "Standard_1"
  }

  expect_failures = [var.apim_sku_name]
}

run "reject_excess_v2_capacity" {
  command = plan

  variables {
    apim_sku_name = "StandardV2_11"
  }

  expect_failures = [var.apim_sku_name]
}

run "reject_no_models" {
  command = plan

  variables {
    models = []
  }

  expect_failures = [var.models]
}

run "reject_no_authorized_users" {
  command = plan

  variables {
    allowed_principal_object_ids = []
  }

  expect_failures = [azuread_service_principal.gateway]
}

run "multiple_models_and_capacity" {
  command = apply

  variables {
    models                    = [" GPT-6-Sol ", "GPT-6-Luna"]
    model_deployment_sku_name = "GlobalStandard"
    model_deployment_capacity = 3
  }

  assert {
    condition = (
      length(azurerm_cognitive_deployment.this) == 2 &&
      azurerm_cognitive_deployment.this["gpt-6-sol"].model[0].name == "gpt-6-sol" &&
      azurerm_cognitive_deployment.this["gpt-6-sol"].name == "gpt-6-sol" &&
      azurerm_cognitive_deployment.this["gpt-6-sol"].sku[0].name == "GlobalStandard" &&
      azurerm_cognitive_deployment.this["gpt-6-luna"].sku[0].capacity == 3 &&
      output.model_deployment_names == tolist(["gpt-6-luna", "gpt-6-sol"]) &&
      strcontains(azurerm_api_management_api_policy.responses.xml_content, jsonencode(jsonencode(["gpt-6-luna", "gpt-6-sol"])))
    )
    error_message = "Each configured model and capacity must be deployed and included in the gateway allowlist."
  }
}

run "reject_placeholder_model" {
  command = plan

  variables {
    models = ["REPLACE_WITH_MODEL_NAME"]
  }

  expect_failures = [var.models]
}

run "reject_duplicate_models" {
  command = plan

  variables {
    models = ["GPT-6-Sol", " gpt-6-sol "]
  }

  expect_failures = [var.models]
}

run "reject_invalid_model_name" {
  command = plan

  variables {
    models = ["GPT 6 Sol"]
  }

  expect_failures = [var.models]
}

run "reject_invalid_model_plan" {
  command = plan

  variables {
    model_deployment_sku_name = "Unsupported"
  }

  expect_failures = [var.model_deployment_sku_name]
}

run "reject_fractional_model_capacity" {
  command = plan

  variables {
    model_deployment_capacity = 1.5
  }

  expect_failures = [var.model_deployment_capacity]
}

run "authorize_by_email_and_group_name" {
  command = apply

  variables {
    allowed_principal_object_ids = []
    allowed_user_emails          = [" Developer@Example.com "]
    allowed_group_names          = [" Codex Developers "]
  }

  assert {
    condition = (
      data.azuread_user.allowed["developer@example.com"].mail == "developer@example.com" &&
      data.azuread_group.allowed["Codex Developers"].display_name == "Codex Developers" &&
      data.azuread_group.allowed["Codex Developers"].security_enabled &&
      toset(keys(azuread_app_role_assignment.users)) == toset([
        "99999999-9999-9999-9999-999999999999",
        "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      ]) &&
      azuread_app_role_assignment.users["99999999-9999-9999-9999-999999999999"].principal_object_id == data.azuread_user.allowed["developer@example.com"].object_id
    )
    error_message = "Resolve normalized emails and trimmed security group names and assign the resolved object IDs."
  }
}

run "deduplicate_mixed_principals" {
  command = apply

  variables {
    allowed_principal_object_ids = ["99999999-9999-9999-9999-999999999999"]
    allowed_user_emails          = ["developer@example.com", " Developer@Example.com "]
    allowed_group_names          = ["Codex Developers"]
  }

  assert {
    condition     = length(data.azuread_user.allowed) == 1 && length(azuread_app_role_assignment.users) == 2
    error_message = "Emails and direct object IDs resolving to the same principal must produce only one assignment."
  }
}

run "authorize_email_only" {
  command = plan

  variables {
    allowed_principal_object_ids = []
    allowed_user_emails          = ["developer@example.com"]
  }

  assert {
    condition     = length(azuread_app_role_assignment.users) == 1
    error_message = "An email alone must be sufficient to authorize a user."
  }
}

run "authorize_group_only" {
  command = plan

  variables {
    allowed_principal_object_ids = []
    allowed_group_names          = ["Codex Developers"]
  }

  assert {
    condition     = length(azuread_app_role_assignment.users) == 1
    error_message = "A group name alone must be sufficient to authorize a group."
  }
}

run "reject_invalid_email" {
  command = plan

  variables {
    allowed_user_emails = ["not-an-email"]
  }

  expect_failures = [var.allowed_user_emails]
}

run "reject_blank_group" {
  command = plan

  variables {
    allowed_group_names = [" "]
  }

  expect_failures = [var.allowed_group_names]
}
