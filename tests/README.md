# Call the APIM Responses API

From the repository root:

```powershell
.\.venv\Scripts\python.exe -m pip install -r .\tests\requirements.txt

.\.venv\Scripts\python.exe .\tests\call_apim.py
```

A browser opens for Entra sign-in. Use a user assigned the gateway's `Codex.User` role. The script uses MSAL authorization code flow with PKCE and listens for the registered callback at `http://127.0.0.1:43127/callback` for up to five minutes. Run it where the browser can reach this local port.

The [script](./call_apim.py) contains the deployed tenant, client ID, gateway scope, and APIM URL. Update them from `codex_connection` if you redeploy with different values. MSAL adds its standard OpenID/refresh-token scopes automatically; do not add `offline_access` to the MSAL scope list.

The OpenAI SDK's `api_key` argument contains the acquired **Entra bearer token**, not an API key. Tokens stay in memory. Edit `model` to use an existing deployment and `input` to change the prompt. Running it makes one billable model request.
