#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/reset-admin-password.sh <admin-email>" >&2
  exit 1
fi

if [[ ! -t 0 ]]; then
  echo "Run this script in an interactive terminal for hidden password entry." >&2
  exit 1
fi

kubectl --context litellm-demo-aks --namespace litellm \
  exec -it deployment/litellm -- python -c '
import getpass
import json
import os
import re
import sys
import urllib.error
import urllib.request

base = "http://127.0.0.1:4000"
headers = {
    "Authorization": "Bearer " + os.environ["PROXY_MASTER_KEY"],
    "Content-Type": "application/json",
}

def safe_error_reason(error):
    try:
        body = json.load(error)
    except (ValueError, UnicodeDecodeError):
        return "The error response was not valid JSON; its body is withheld."
    if not isinstance(body, dict):
        return "Unrecognized error response; its body is withheld."
    detail = body.get("error", body.get("detail"))
    message = detail.get("message") if isinstance(detail, dict) else detail
    if not isinstance(message, str):
        return "Unrecognized error response; its body is withheld."
    policy_pattern = (
        r"Password does not meet the required policy: must "
        r"(?:be at least [0-9]{1,4} characters long|include an uppercase letter|"
        r"include a lowercase letter|include a number|include a special character)"
        r"(?:, (?:be at least [0-9]{1,4} characters long|include an uppercase letter|"
        r"include a lowercase letter|include a number|include a special character))*\."
    )
    if re.fullmatch(policy_pattern, message):
        return message
    if message == (
        "This password appears in known data breaches and cannot be used. "
        "Please choose a different password."
    ):
        return message
    return "Unrecognized error response; inspect server logs privately. Its body is withheld."

def request(path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(base + path, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        sys.exit(
            f"LiteLLM request to {path} failed (HTTP {error.code}). "
            + safe_error_reason(error)
        )
    except urllib.error.URLError:
        sys.exit("Cannot reach LiteLLM. Check deployment health before retrying.")

email = sys.argv[1].casefold()
matches = []
page = 1
while True:
    result = request(f"/user/list?page={page}&page_size=100")
    users = result if isinstance(result, list) else result["users"]
    matches.extend(u for u in users if (u.get("user_email") or "").casefold() == email)
    if len(users) < 100:
        break
    page += 1

if len(matches) != 1 or matches[0].get("user_role") != "proxy_admin":
    sys.exit("Expected exactly one matching proxy_admin account; nothing changed.")

print("Use a unique password. Default policy: at least 12 characters, with")
print("uppercase and lowercase letters, a number, and a special character.")
print("The server enforces the active policy and screens known breached passwords.")
password = getpass.getpass("New temporary Admin UI password: ")
confirmation = getpass.getpass("Confirm password: ")
if not password or password != confirmation:
    sys.exit("Passwords are empty or do not match; nothing changed.")

request("/user/update", {"user_id": matches[0]["user_id"], "password": password})
del password, confirmation
print("Password reset accepted. Sign in through the local port-forward.")
print("LiteLLM requires another password change at the next login.")
' "$1"
