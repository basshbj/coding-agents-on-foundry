from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs
import webbrowser

import msal
from openai import OpenAI


TENANT_ID = ""
CLIENT_ID = ""
SCOPE = "api://XXXXXX/Codex.Access"
BASE_URL = ""
REDIRECT_URI = "http://127.0.0.1:43127/callback"

callback = {}


class OAuthCallback(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/callback":
            self.send_error(404)
            return
        self.connection.settimeout(5)
        length = int(self.headers.get("Content-Length", "0"))
        if not 0 < length <= 16384:
            self.send_error(400, "Invalid callback length")
            return
        parameters = parse_qs(self.rfile.read(length).decode("utf-8"))
        callback.update({key: values[0] for key, values in parameters.items()})
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Return to the terminal to see the sign-in result.")

    def log_message(self, format, *args):
        pass  # Do not log authentication callback traffic.


app = msal.PublicClientApplication(
    CLIENT_ID,
    authority=f"https://login.microsoftonline.com/{TENANT_ID}",
    timeout=30,
)
flow = app.initiate_auth_code_flow(
    scopes=[SCOPE], redirect_uri=REDIRECT_URI, response_mode="form_post"
)

with HTTPServer(("127.0.0.1", 43127), OAuthCallback) as server:
    server.timeout = 300
    print("Sign in with a user authorized to use the Codex gateway.")
    if not webbrowser.open(flow["auth_uri"]):
        raise RuntimeError("Could not open the sign-in browser.")
    server.handle_request()

if not callback:
    raise RuntimeError("No sign-in callback received. Check the browser or callback port.")

# MSAL validates OAuth state and performs the PKCE authorization-code exchange.
result = app.acquire_token_by_auth_code_flow(flow, callback)
if "access_token" not in result:
    raise RuntimeError(result.get("error_description", "Sign-in did not return an access token."))

with OpenAI(
    base_url=BASE_URL,
    api_key=result["access_token"],
    max_retries=0,
    timeout=240,
) as client:
    response = client.responses.create(
        model="gpt-5.6-luna",
        input="explain the secret of the universe",
        store=False,
    )
    print(response.output_text)
