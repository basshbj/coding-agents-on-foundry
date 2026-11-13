data "azuread_client_config" "current" {}

data "azuread_user" "allowed" {
  for_each = toset([for email in var.allowed_user_emails : lower(trimspace(email))])
  mail     = each.value
}

data "azuread_group" "allowed" {
  for_each         = toset([for name in var.allowed_group_names : trimspace(name)])
  display_name     = each.value
  security_enabled = true
}

locals {
  allowed_principal_ids = toset(concat(
    [for id in var.allowed_principal_object_ids : lower(id)],
    [for user in data.azuread_user.allowed : lower(user.object_id)],
    [for group in data.azuread_group.allowed : lower(group.object_id)],
  ))
}

resource "azuread_application" "gateway" {
  display_name     = "${var.name_prefix}-gateway-api"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                         = local.scope_id
      value                      = "Codex.Access"
      type                       = "Admin"
      enabled                    = true
      admin_consent_display_name = "Use the Codex model gateway"
      admin_consent_description  = "Allow Codex to call the model gateway on behalf of the signed-in user."
    }
  }

  app_role {
    id                   = local.app_role_id
    value                = "Codex.User"
    display_name         = "Codex gateway user"
    description          = "Allows assigned users and groups to use the Codex model gateway."
    allowed_member_types = ["User"]
    enabled              = true
  }

  lifecycle {
    ignore_changes = [identifier_uris]
  }
}

resource "azuread_application_identifier_uri" "gateway" {
  application_id = azuread_application.gateway.id
  identifier_uri = "api://${azuread_application.gateway.client_id}"
}

resource "azuread_service_principal" "gateway" {
  client_id                    = azuread_application.gateway.client_id
  app_role_assignment_required = true
  owners                       = [data.azuread_client_config.current.object_id]

  lifecycle {
    precondition {
      condition     = length(var.allowed_user_emails) + length(var.allowed_group_names) + length(var.allowed_principal_object_ids) > 0
      error_message = "Authorize at least one user email, security group name, or principal object ID."
    }
  }
}

resource "azuread_application" "codex" {
  display_name     = "${var.name_prefix}-codex-client"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  public_client {
    redirect_uris = ["http://127.0.0.1:${var.oauth_redirect_port}/callback"]
  }

  required_resource_access {
    resource_app_id = azuread_application.gateway.client_id
    resource_access {
      id   = local.scope_id
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "codex" {
  client_id = azuread_application.codex.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_pre_authorized" "codex" {
  application_id       = azuread_application.gateway.id
  authorized_client_id = azuread_application.codex.client_id
  permission_ids       = [local.scope_id]
}

resource "azuread_app_role_assignment" "users" {
  for_each = local.allowed_principal_ids

  app_role_id         = local.app_role_id
  principal_object_id = each.value
  resource_object_id  = azuread_service_principal.gateway.object_id
}
