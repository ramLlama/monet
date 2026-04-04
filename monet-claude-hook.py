#!/usr/bin/env python3
"""Claude Code lifecycle hook — routes events to Emacs via emacsclient."""

import json
import os
import subprocess
import sys
import tempfile

MONET_CTX_ENVVAR_PREFIX = "MONET_CTX_"

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError as e:
    print(f"monet-claude-hook: failed to parse stdin JSON: {e}", file=sys.stderr)
    sys.exit(1)

ctx: dict[str, str] = {
    k.removeprefix(MONET_CTX_ENVVAR_PREFIX).lower(): v
    for k, v in os.environ.items()
    if k.startswith(MONET_CTX_ENVVAR_PREFIX)
}

envelope: dict = {"hook_payload": payload, "monet_context": ctx}

emacs_socket = os.environ.get("MONET_EMACS_SOCKET")
with tempfile.NamedTemporaryFile(
    suffix=".json", prefix="monet-hook-", delete_on_close=False, mode="w"
) as f:
    json.dump(envelope, f)
    f.close()  # close the file, I'm done with writing to it for now

    # stay in the context manager to get the free deletion on completion/exception
    tmpfile = f.name
    escaped = tmpfile.replace("\\", "\\\\").replace('"', '\\"')
    cmd: list[str] = [
        "emacsclient",
        *(["-s", emacs_socket] if emacs_socket is not None else []),
        "-e",
        f'(monet-claude-hook-receive "{escaped}")',
    ]
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode != 0:
        print(
            f"monet-claude-hook: emacsclient failed: {result.stderr.decode()}",
            file=sys.stderr,
        )
        sys.exit(result.returncode)
