output "resource_group_name" {
  description = "Newly created resource group."
  value       = azurerm_resource_group.this.name
}

output "foundry_resource_name" {
  description = "Microsoft Foundry resource hosting the model deployments."
  value       = azurerm_cognitive_account.this.name
}

output "foundry_openai_base_url" {
  description = "Foundry OpenAI-compatible v1 endpoint used by APIM, not a project endpoint."
  value       = azurerm_api_management_api.responses.service_url
}

output "model_deployment_names" {
  description = "Allowed values for Codex's model setting."
  value       = sort(tolist(local.model_names))
}

output "codex_connection" {
  description = "Non-secret settings for a later Codex gateway configuration."
  value = {
    base_url             = "${azurerm_api_management.this.gateway_url}/openai/v1"
    wire_api             = "responses"
    requires_openai_auth = false
    tenant_id            = var.tenant_id
    gateway_audience     = azuread_application.gateway.client_id
    authorization_url    = "https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/authorize"
    token_url            = "https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/token"
    client_id            = azuread_application.codex.client_id
    scopes               = ["${azuread_application_identifier_uri.gateway.identifier_uri}/Codex.Access", "offline_access"]
    redirect_port        = var.oauth_redirect_port
    redirect_uri         = "http://127.0.0.1:${var.oauth_redirect_port}/callback"
  }
}
