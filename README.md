# Coding Agents on Microsoft Foundry

Guides, Azure infrastructure, and client configuration for using coding agents with models hosted in **Microsoft Foundry**. The current implementation focuses on **Codex CLI**.

```text
Codex CLI -> Azure API Management -> Microsoft Foundry models
```

Users sign in with Microsoft Entra ID. API Management authenticates to Foundry using managed identity, without model API keys.

## What's in this repository

| Folder | Contents |
| --- | --- |
| [azure_infra](azure_infra/README.md) | Architecture and Terraform templates for Foundry model deployments, API Management, Entra authentication, and monitoring. |
| [codex_foundry](codex_foundry/README.md) | Codex configuration, gateway sign-in instructions, and a local model catalog. |
| [tests](tests/README.md) | Python gateway smoke test and a [PowerShell script](tests/codex_test/model_test.ps1) to test Codex models across reasoning levels. |

## Getting started

1. Follow the [deployment guide](azure_infra/DEPLOYMENT.md) to provision the Azure environment.
2. Run the [gateway smoke test](tests/README.md) to check sign-in and model access.
3. Follow the [Codex setup guide](codex_foundry/README.md), updating endpoint, identity, and local paths for your environment.

Azure resources and model requests incur costs; model availability depends on your region and quota.

**Planned:** Claude Code setup and a CLI tool to automate Codex and Claude Code configuration.