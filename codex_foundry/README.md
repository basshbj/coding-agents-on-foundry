# Connect Codex to the Foundry gateway

The Azure deployment is only the backend. Codex also needs:

- [config.toml](./config.toml): select APIM as the Responses API provider and configure native Entra gateway OAuth.
- [models.json](./models.json): supply the local model picker and model metadata.

A separate catalog is optional when the exact model names and bundled metadata in your Codex version already match the gateway. This local catalog intentionally lists only the six deployments reported by Terraform state. It replaces the bundled catalog; it is not an OpenAI `/v1/models` response. Native gateway OAuth alone does not enable remote catalog discovery, so no additional APIM catalog route is needed.

## Configuration

The files use the deployed `codex_connection` values:

- Gateway: `https://xxxxx.azure-api.net/openai/v1`
- Default model: `gpt-5.6-luna`
- Public OAuth client: `XXXXX`
- Gateway scope: `api://XXXXX/Codex.Access`
- Loopback callback: `http://127.0.0.1:43127/callback`

Codex obtains and refreshes the gateway token through browser sign-in and sends it in `Authorization: Bearer ...`. `requires_openai_auth = false` means no ChatGPT sign-in is required; it does **not** disable gateway authentication. Do not add an API key, `env_key`, static bearer token, or an `Authorization` header override.

## Run on this Windows machine

Use **Codex CLI 0.166.0 or later** for gateway-only OAuth with default bearer delivery. These settings were checked against the 0.166.0 configuration schema; recheck compatibility if using a different release.

From the repository root, install the configuration in an isolated Codex home so it does not overwrite your existing settings:

```powershell
codex --version
$env:CODEX_HOME = Join-Path $env:USERPROFILE ".codex-foundry"
New-Item -ItemType Directory -Force -Path $env:CODEX_HOME | Out-Null
Copy-Item .\codex_foundry\codex_config\config.toml -Destination (Join-Path $env:CODEX_HOME "config.toml")
codex
```

The copy command overwrites only the config in that dedicated home; review or back it up if you have already customized it. Set `CODEX_HOME` again in each new shell, or merge the provider/top-level settings into your existing Codex configuration instead. Do not duplicate TOML keys or tables.

The catalog path in the supplied config points to this checkout:

```toml
model_catalog_json = '..\models.json'
```

Keep the file there, or change the setting to its actual **absolute** path. Codex does not expand environment variables inside this path. If running Codex in WSL/Linux or another checkout, use a path visible to that runtime rather than this Windows path.

Sign in when Codex prompts, using a user assigned the gateway's `Codex.User` role. Close the Python smoke test or another login listener if it occupies port 43127. Browser access to the loopback callback is required; remote/container sessions may need forwarding.

Use `/model` to select another catalog model, or start with:

```powershell
codex --model gpt-6.1-sol
```

Start a new conversation and ask for a short response, then test a local read-only tool call and a follow-up turn. Actual model requests are billable.

## Catalog scope and compatibility

The catalog includes `gpt-5.6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-6-astra`, `gpt-6-luna`, and `gpt-6.1-sol`. The failed/commented-out `gpt-6.1-terra` deployment is excluded.

This is a starter catalog, with basic coding instructions and shell/apply-patch tooling. Context limits, reasoning choices through `max`, verbosity, and truncation metadata were checked against the 0.166.0 bundled catalog. The initial setup deliberately exposes text input only, does not advertise experimental tools or service tiers, and omits `ultra`/automatic delegation. It does not reproduce the full model-specific instructions or advanced workflows of the bundled catalog. Azure model versions and supported parameters still need a live pilot; metadata does not grant capabilities or inference access.

Web search and WebSockets are disabled. The provider explicitly uses local compaction rather than an unverified remote-compaction protocol. The existing APIM API exposes only `POST /openai/v1/responses`; features needing other routes must be implemented and tested before enabling them.

After adding/removing Azure deployments, update the catalog's `slug` values to match the deployment names and APIM allowlist exactly. Keep the configured default model in the catalog. Restart Codex after catalog changes. Update OAuth/endpoint values from Terraform outputs after redeploying the environment.

## Verification limits

The TOML passed Codex's 0.166.0 JSON Schema, and the connection settings and catalog were checked against Terraform outputs and reference metadata. Codex is not installed in the current environment, so client startup, credential storage, sign-in, streaming, and tool execution have not been verified here. Passing the Python smoke test alone does not prove the full Codex workflow.

## References

- [Codex: connect to a gateway](https://learn.chatgpt.com/docs/enterprise/connect-to-a-gateway)
- [Codex: gateway rollout and local catalogs](https://learn.chatgpt.com/docs/enterprise/roll-out-a-gateway#start-with-a-local-modelsjson-file)
- [Codex 0.166.0 configuration schema](https://github.com/openai/codex/blob/rust-v0.166.0/codex-rs/core/config.schema.json)
- [Codex 0.166.0 model metadata types](https://github.com/openai/codex/blob/rust-v0.166.0/codex-rs/protocol/src/openai_models.rs)
- [Codex 0.166.0 bundled model metadata](https://github.com/openai/codex/blob/rust-v0.166.0/codex-rs/models-manager/models.json)
