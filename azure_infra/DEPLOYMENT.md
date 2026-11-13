# Terraform deployment

See the [architecture and acceptance criteria](./README.md) before provisioning. All commands below run in PowerShell. Authoring or validating these templates does not deploy resources.

## What is created

The [Terraform configuration](./src) creates:

- A **new resource group**, with an optional explicit name or a name derived from a prefix.
- Public **APIM Standard v2** with a system-assigned managed identity and no VNet integration.
- A **Microsoft Foundry resource** (`kind = "AIServices"`, plan `S0`) with project management enabled and its own system-assigned managed identity (required for project management), not a standalone Azure OpenAI account. No child project is created. This identity is separate from the APIM identity used for inference.
- One OpenAI model deployment in Foundry per model in the parameter list, using Azure's default version and a shared deployment SKU/capacity.
- The `Cognitive Services OpenAI User` role assignment for APIM on the Foundry resource.
- Two single-tenant Entra applications and their service principals, the delegated `Codex.Access` scope, the `Codex.User` app role, explicit user/group assignments, public-client loopback redirect, and client preauthorization.
- An APIM `POST /openai/v1/responses` API with OAuth scope/role validation, a model allowlist, per-user limits, managed-identity backend authentication, and streaming.
- A Log Analytics workspace and platform metrics diagnostics for APIM and Foundry.

Budget notifications, operational alert rules, request-level logging, and additional Responses operations are not provisioned yet. Codex client settings are supplied separately in the [Codex configuration guide](../codex_config/README.md), not provisioned by Terraform. Platform metrics diagnostics do not capture request headers or bodies.

### Public access and authentication

Both APIM and Foundry have public network access enabled. **Foundry allows all networks** (`default_action = "Allow"`), while local/key authentication is disabled. Entra authentication and Azure RBAC are required for inference.

Standard v2 without VNet integration has no dedicated, deterministic outbound public IP, so the former APIM-only IP firewall allowlist is not applicable. These templates do not add regional IP ranges, VNet resources, private endpoints, or trusted-service bypass rules.

This design does not enforce network-level gateway isolation. Any identity with direct Foundry inference permissions can bypass APIM's user/model policies. Restrict direct inference permissions to APIM and approved administrators; gateway users should not receive direct inference roles.

## 1. Prerequisites and permissions

- Terraform 1.7 or later, below 2.0, and Azure CLI.
- AzureRM 4.81.0 or later (below 5.0) and AzureAD 3.10.0 or later (below 4.0); initialize using the committed provider lock file.
- A subscription/region supporting Standard v2, Foundry, and the selected OpenAI model versions, with sufficient quota.
- Azure permissions to create the resource group and resources and assign Azure roles.
- Entra permissions to create applications/service principals, preauthorize the client, and assign users/groups to the gateway role.

For automation, app-registration permissions alone are insufficient for role assignments; the AzureAD provider documents `AppRoleAssignment.ReadWrite.All` and `Application.Read.All` for that operation. Have a tenant administrator approve the required directory permissions and consent. Group-based application assignment can require Entra licensing.

Email lookups additionally require `User.Read.All` (or `Directory.Read.All`) when running as a service principal. Group-name lookups require `Group.Read.All` (or `Directory.Read.All`). Interactive user access remains subject to tenant directory-read restrictions.

The templates create registrations rather than accepting existing ones. They do not create a client secret or authorize unassigned users. Client preauthorization and the required `Codex.User` token role are both enforced; nested-group membership is not a substitute for a supported application assignment.

## 2. Configure parameters

From the directory containing this guide:

```powershell
Set-Location .\src
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
```

Edit the local copy of [the parameter example](./src/terraform.tfvars.example):

| Parameter | Purpose |
| --- | --- |
| `subscription_id`, `tenant_id` | Explicit deployment subscription and Entra tenant |
| `name_prefix` | Prefix for resource names; choose one making APIM and Foundry hostnames globally unique |
| `resource_group_name` | Optional name of the **new** group; null derives `<name_prefix>-rg` |
| `location` | Region supporting Standard v2, Foundry, and the selected models |
| `apim_sku_name` | Standard v2 plan/capacity: `StandardV2_1` through `StandardV2_10` |
| `publisher_name`, `publisher_email` | APIM publisher and operational contact |
| `models` | List of model names, for example `["GPT-6-Sol", "GPT-6-Luna"]`; names are trimmed and lowercased for catalog lookup and deployment naming |
| `model_deployment_sku_name` | Shared model deployment plan: `Standard`, `GlobalStandard`, or `DataZoneStandard` |
| `model_deployment_capacity` | Capacity per model deployment, in model/SKU-specific quota units |
| `allowed_user_emails` | Existing users' email addresses, resolved through the Entra `mail` attribute |
| `allowed_group_names` | Exact display names of existing Entra security groups |
| `allowed_principal_object_ids` | Optional user/group object IDs for direct assignment |
| `oauth_redirect_port` | Fixed port matching the generated Entra loopback callback |
| `requests_per_minute` | Approximate per-user gateway request limit |
| `log_retention_days`, `tags` | Workspace retention and Azure resource tags |

Replace the remaining account/access placeholders and edit the model list to select the models you want. The example lists the requested candidates, not a verified availability list. There is no separate model ID, version, or deployment-name map to maintain:

```hcl
models = ["GPT-6-Sol", "GPT-6-Luna"]
model_deployment_sku_name = "Standard"
model_deployment_capacity = 1
```

This creates deployments named `gpt-6-sol` and `gpt-6-luna`; these are also the names exposed to Codex and allowed by APIM. Reordering the list does not replace deployments. Case and surrounding whitespace are normalized; duplicate normalized names are rejected. Names must correspond to actual OpenAI catalog names after normalization: the templates do not resolve arbitrary display-name aliases or silently substitute another model.

Azure assigns the default model version at creation because the version parameter is omitted. This is not necessarily the newest version, and a model without an available default version can fail deployment. Automatic upgrades remain disabled (`NoAutoUpgrade`); inspect the assigned versions after apply and plan for retirement/upgrades. Newly created deployments can receive different defaults over time.

All listed models use the same plan and capacity. Verify that every model supports the selected plan in the chosen region and has sufficient quota; unsupported models or insufficient quota fail explicitly at Azure deployment time. Capacity units depend on the model/SKU. Verify data residency before choosing a Global or Data Zone deployment. Start with one model to validate the environment before deploying the full list.

### Authorize gateway users and groups

You can use email addresses or group names without looking up object IDs yourself:

```hcl
allowed_user_emails = ["developer@example.com"]
allowed_group_names = ["Codex Developers"]
```

Provide at least one entry across the email, group-name, and optional object-ID lists. Terraform resolves names during planning and combines/deduplicates the resolved IDs before assigning the `Codex.User` role. It does not create users or groups. Missing or ambiguous directory matches fail rather than selecting an arbitrary identity.

Email lookup uses the user's Entra `mail` attribute, not a UPN or an arbitrary email alias. When the sign-in address differs from `mail`, use the actual primary email or supply the object ID. Group names must uniquely identify a security-enabled group; use an object ID when display names are duplicated. Existing object-ID parameters and assignment addresses remain supported.

These settings grant access to the Codex gateway only, not Azure management permissions or direct Foundry inference access.

## 3. Validate and review

```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
terraform plan -out="deployment.tfplan"
```

The [tests](./src/tests/infrastructure.tftest.hcl) use mocked providers and explicitly define all input variables so local parameter files do not affect their assertions. They do not create Azure resources or prove live model availability, Entra sign-in, or APIM policy execution. Review the real plan before applying.

`terraform validate` checks syntax/schema, while mock tests check the declared configuration. Neither runs all provider planning hooks: for example, AzureRM's requirement that project-enabled Foundry have a managed identity is checked during a real plan. **Do not skip `terraform plan`**, and do not apply a saved plan produced before a configuration change; regenerate it first.

Check the plan for:

- A new resource group, public Standard v2 APIM, and a project-enabled `AIServices` Foundry resource.
- No VNet integration, private endpoints, private DNS resources, or APIM-IP firewall dependency.
- Explicit model deployments, identities, role assignments, and user/group access.
- Foundry public access from all networks, with key authentication disabled.
- Expected capacity, naming, tags, costs, and any replacements or deletions.

### If an earlier version was already deployed

Classic APIM cannot be upgraded in place to Standard v2. Plan a separate Standard v2 instance and migration rather than assuming a SKU update will work.

This revision also changes the model resource name/subdomain from `<prefix>-openai` to `<prefix>-foundry`, which can replace the resource and its deployments. The metrics diagnostic label changes as well. If you have existing state/resources, stop and review a migration plan before applying; do not approve unexpected replacements or deletions.

The former `model_deployments` map is replaced by `models` and shared plan/capacity parameters. Remove the old map from your local parameter file. Existing deployments with custom aliases (for example `codex`) will be replaced by model-named deployments unless migrated separately; review the plan before applying.

## 4. Apply after approval

Applying creates billable resources, including a continuously billed Standard v2 instance. After confirming the plan, availability/quota, permissions, and costs:

```powershell
terraform apply deployment.tfplan
terraform output codex_connection
terraform output model_deployment_names
terraform output foundry_resource_name
terraform output foundry_openai_base_url
```

The gateway routes to `https://<foundry-subdomain>.services.ai.azure.com/openai/v1`. It does not route to a project endpoint. Although the Foundry resource hosts OpenAI models and exposes an OpenAI-compatible API, the resource itself is `AIServices`, not `OpenAI`.

APIM provisioning and Azure RBAC/Entra propagation can take time. Complete the [acceptance checklist](./README.md#acceptance-checklist) before using the gateway; successful provisioning is not an end-to-end inference test.

Use the [Python APIM smoke test](../../tests/README.md) to sign in with Entra and send a Responses API request after deployment.

Then follow the [Codex configuration guide](../codex_config/README.md) to install the client settings and local model catalog. Compare the supplied endpoint, OAuth values, and catalog names with your own Terraform outputs before using them.

## 5. Destroy the deployed resources

**Destructive operation:** teardown removes the Terraform-managed resource group, APIM, Foundry resource and model deployments, Log Analytics workspace, role assignments, and Entra applications/service principals. Back up any data you need and obtain approval before proceeding. Deleting the resource group can also delete resources added to it outside Terraform; inspect its contents first.

Use the same configuration, parameter values, Terraform state/backend, and workspace used for deployment. Keep directory lookup inputs valid: planning can still resolve the configured user emails and group names. The executing identity needs permissions to delete both Azure resources and Entra objects.

From the directory containing this guide, enter the Terraform directory (skip this if already there):

```powershell
Set-Location .\src
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
terraform init
terraform workspace show
terraform state list
terraform plan -destroy -out="destroy.tfplan"
```

Confirm the tenant/subscription, workspace, state entries, resource group contents, and proposed deletions all match the environment you intend to remove. Stop if resources are missing from state or the plan targets another environment. After reviewing and approving the destroy plan:

```powershell
terraform apply "destroy.tfplan"
terraform state list
```

A successful teardown should leave no managed resource entries in this stack's state. Also verify the resource group and the deployment's Entra applications are removed in Azure/Entra. APIM deletion can take time; Azure may retain soft-deleted resources afterward, which can affect name reuse.

- Do not delete the resource group manually first: that does not remove the Entra applications and assignments.
- Do not delete state or its backend while destruction is in progress. If deletion fails, resolve the reported error and generate a new destroy plan using the remaining state.
- Separately bootstrapped remote-state storage is outside this stack and is not removed by its destroy plan.
- Treat the saved destroy plan as sensitive, and regenerate it after any configuration or state change.

## Terraform state

The initial configuration uses local state for a single-operator bootstrap. The local parameter file, state, provider cache, and saved plans are ignored by Git; commit the generated provider lock file. Treat state and plan files as sensitive even though connection outputs are non-secret.

Before shared or automated use, configure an Azure Storage remote state backend with Entra authentication, least-privilege access, and state locking. Bootstrap its storage separately from this stack and migrate with `terraform init -migrate-state`. Prefer workload identity/OIDC for automation.

Do not store a backend access key in the parameter file or commit state to Git. Terraform can retain Azure-generated credentials in provider-managed state even when local authentication is disabled. Provisioning and any teardown require explicit approval.
