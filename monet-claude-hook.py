#!/usr/bin/env python3
"""Claude Code lifecycle hook — routes events to Emacs via HTTP."""

import json
import os
import sys
import urllib.error
import urllib.request

MONET_CTX_ENVVAR_PREFIX = "MONET_CTX_"

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(f"monet-claude-hook: failed to parse stdin JSON: {e}", file=sys.stderr)
    sys.exit(1)

hook_port = os.environ.get("MONET_HOOK_PORT")

if not hook_port:
    print("monet-claude-hook: MONET_HOOK_PORT must be set", file=sys.stderr)
    sys.exit(1)

ctx: dict[str, str] = {
    k.removeprefix(MONET_CTX_ENVVAR_PREFIX).lower(): v
    for k, v in os.environ.items()
    if k.startswith(MONET_CTX_ENVVAR_PREFIX)
}

envelope: dict = {"hook_payload": payload, "monet_context": ctx}
body = json.dumps(envelope).encode("utf-8")

url = f"http://127.0.0.1:{hook_port}/hook"
req = urllib.request.Request(
    url,
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)

try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        if resp.status != 200:
            print(
                f"monet-claude-hook: server returned {resp.status}",
                file=sys.stderr,
            )
            sys.exit(1)
except urllib.error.URLError as e:
    print(f"monet-claude-hook: HTTP request failed: {e}", file=sys.stderr)
    sys.exit(1)
