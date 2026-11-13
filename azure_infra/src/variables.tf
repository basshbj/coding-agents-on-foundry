variable "subscription_id" {
  description = "Azure subscription in which to create a new resource group."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant for the Azure subscription and both application registrations."
  type        = string
}

variable "name_prefix" {
  description = "Globally unique naming prefix. Resource names are derived from this prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.name_prefix)) && !endswith(var.name_prefix, "-")
    error_message = "Use 3-30 lowercase letters, digits, or hyphens, beginning with a letter and not ending with a hyphen."
  }
}

variable "location" {
  description = "Azure region supporting Standard v2 APIM, Microsoft Foundry, and the selected models."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the NEW resource group. Null derives <name_prefix>-rg; existing groups are not adopted."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to Azure resources."
  type        = map(string)
  default     = {}
}

variable "apim_sku_name" {
  description = "Standard v2 APIM plan and capacity, for example StandardV2_1. No VNet integration is configured."
  type        = string
  default     = "StandardV2_1"

  validation {
    condition     = can(regex("^StandardV2_([1-9]|10)$", var.apim_sku_name))
    error_message = "Choose StandardV2_1 through StandardV2_10."
  }
}

variable "publisher_name" {
  description = "Organization name required by APIM."
  type        = string
}

variable "publisher_email" {
  description = "Operational contact email required by APIM."
  type        = string
}

variable "models" {
  description = "OpenAI model names, for example GPT-6-Sol. Names are trimmed and lowercased for both the catalog name and deployment name; Azure selects its default version."
  type        = list(string)

  validation {
    condition = length(var.models) > 0 && alltrue([
      for model in var.models :
      can(regex("^[a-z0-9][a-z0-9_.-]{0,63}$", lower(trimspace(model)))) &&
      !startswith(lower(trimspace(model)), "replace_")
    ])
    error_message = "Provide at least one model name using 1-64 letters, digits, dots, underscores, or hyphens, beginning with a letter or digit. Replace placeholder names."
  }

  validation {
    condition     = length(distinct([for model in var.models : lower(trimspace(model))])) == length(var.models)
    error_message = "Model names must be unique after trimming whitespace and converting to lowercase."
  }
}

variable "model_deployment_sku_name" {
  description = "Shared deployment plan for all selected models. Verify availability and data residency."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "GlobalStandard", "DataZoneStandard"], var.model_deployment_sku_name)
    error_message = "Choose Standard, GlobalStandard, or DataZoneStandard."
  }
}

variable "model_deployment_capacity" {
  description = "Shared capacity per model deployment, in model/SKU-specific Azure quota units."
  type        = number
  default     = 1

  validation {
    condition     = var.model_deployment_capacity >= 1 && var.model_deployment_capacity == floor(var.model_deployment_capacity)
    error_message = "Use a positive integer deployment capacity."
  }
}

variable "allowed_principal_object_ids" {
  description = "Optional Entra user/group object IDs, combined with resolved email addresses and group names."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.allowed_principal_object_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id)) &&
      id != "00000000-0000-0000-0000-000000000000"
    ])
    error_message = "Each supplied object ID must be a nonzero Entra user/group GUID."
  }
}

variable "allowed_user_emails" {
  description = "Email addresses (Entra mail attribute) of existing users allowed to use the Codex gateway."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.allowed_user_emails :
      can(regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", trimspace(email)))
    ])
    error_message = "Each user email must be a valid email address."
  }
}

variable "allowed_group_names" {
  description = "Exact display names of existing Entra security groups allowed to use the Codex gateway. Each name must resolve uniquely."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for name in var.allowed_group_names : length(trimspace(name)) > 0])
    error_message = "Group names must not be empty or whitespace."
  }
}

variable "oauth_redirect_port" {
  description = "Fixed loopback callback port for native Codex gateway OAuth."
  type        = number
  default     = 43127

  validation {
    condition     = var.oauth_redirect_port >= 1024 && var.oauth_redirect_port <= 65535 && var.oauth_redirect_port == floor(var.oauth_redirect_port)
    error_message = "Use an integer port between 1024 and 65535."
  }
}

variable "requests_per_minute" {
  description = "APIM request limit per validated tenant/user. Limits are approximate, not a billing cap."
  type        = number
  default     = 60

  validation {
    condition     = var.requests_per_minute >= 1 && var.requests_per_minute == floor(var.requests_per_minute)
    error_message = "Use a positive integer request limit."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention. Only platform metrics are exported initially, not gateway bodies or headers."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && var.log_retention_days == floor(var.log_retention_days)
    error_message = "Use an integer retention between 30 and 730 days."
  }
}
