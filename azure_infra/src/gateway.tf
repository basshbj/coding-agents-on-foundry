resource "azurerm_api_management_api" "responses" {
  name                  = "codex-responses"
  resource_group_name   = azurerm_resource_group.this.name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Codex Responses API"
  path                  = "openai/v1"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "https://${azurerm_cognitive_account.this.custom_subdomain_name}.services.ai.azure.com/openai/v1"
}

resource "azurerm_api_management_api_operation" "responses" {
  operation_id        = "create-response"
  api_name            = azurerm_api_management_api.responses.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  display_name        = "Create a response"
  method              = "POST"
  url_template        = "/responses"
}

resource "azurerm_api_management_api_policy" "responses" {
  api_name            = azurerm_api_management_api.responses.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content = templatefile("${path.module}/policies/responses.xml.tftpl", {
    tenant_id           = var.tenant_id
    gateway_client_id   = azuread_application.gateway.client_id
    codex_client_id     = azuread_application.codex.client_id
    allowed_models      = jsonencode(jsonencode(sort(tolist(local.model_names))))
    requests_per_minute = var.requests_per_minute
  })

  depends_on = [
    azurerm_api_management_api_operation.responses,
    azurerm_role_assignment.inference,
    azurerm_cognitive_deployment.this,
    azuread_app_role_assignment.users,
    azuread_application_pre_authorized.codex,
    azuread_application_identifier_uri.gateway,
    azuread_service_principal.codex,
  ]
}
