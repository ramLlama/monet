<!-- Last updated: hook transport migrated from emacsclient/temp-file to HTTP POST -->

# Claude Code Lifecycle Hooks

## Overview

Monet installs a Python script (`monet-claude-hook.py`) as a Claude Code lifecycle hook.
When Claude Code fires a lifecycle event, it invokes the script with a JSON payload on
stdin.  The script delivers the event to Emacs by POSTing it to a local HTTP server that
Monet runs, where registered Elisp handlers dispatch on the event name.

`monet-install-claude-hooks` copies `monet-claude-hook.py` into `~/.claude/hooks/` (mode
`0755`) and registers it in `settings.json` under the $HOME-relative command
`monet--claude-hook-command` (`"$HOME/.claude/hooks/monet-claude-hook.py"`).  The command
is deliberately `$HOME`-relative: Claude runs hook commands through `/bin/sh`, which
expands `$HOME`, so the same `settings.json` works on the host and inside a sandbox guest
whose home differs (given `~/.claude` is shared/mounted).  Install is idempotent by
prune-then-append; the remover matches the exact command.  There is no migration of any
legacy hook-command path (deliberate).

## Hook Pipeline

```
Claude Code
  → spawns monet-claude-hook.py (JSON on stdin)
     → reads payload from stdin
     → collects MONET_CTX_* env vars into ctx dict
     → builds envelope {"hook_payload": payload, "monet_context": ctx}
     → POSTs envelope to http://127.0.0.1:$MONET_HOOK_PORT/hook
        with header  Authorization: Bearer $MONET_HOOK_TOKEN
  → Emacs HTTP hook server (monet--hook-server)
     → monet--hook-connection-filter accumulates the request, validates the token
     → monet--hook-dispatch-envelope (parses envelope)
        → calls monet--log-hook (if logging enabled)
        → dispatches each handler with (event-name data ctx)
     → returns 200 OK (401 on bad token, 400 on unparseable body)
```

The Python script requires both `MONET_HOOK_PORT` and `MONET_HOOK_TOKEN` to be set in
its environment; it exits non-zero with a diagnostic on stderr if either is missing, if
stdin is not valid JSON, or if the HTTP request fails / returns non-200.

## HTTP Hook Server

A single shared HTTP server handles hook delivery for *all* sessions.  It is a raw
`make-network-process` server (not a full HTTP library) that parses just enough of the
request to read the `Content-Length`, `Authorization` header, and body.

State (module-level vars in `monet.el`):

| Var                  | Meaning                                              |
|----------------------|------------------------------------------------------|
| `monet--hook-server` | The server network process, or nil when not running. |
| `monet--hook-port`   | Port the server listens on (loopback only).          |
| `monet--hook-token`  | Bearer token clients must present (a generated UUID). |

Lifecycle:

- `monet--start-hook-server` — idempotent; if no server is running, picks a free port and
  a fresh UUID token, then starts a loopback (`:host 'local`, IPv4) server. Returns the
  port. Called once when `monet-mode` is enabled, and again (as a no-op safety call) from
  `monet-start-server-function`.
- `monet--stop-hook-server` — deletes the server process and clears all three vars. Called
  when `monet-mode` is disabled.

The server binds loopback-only and authenticates every request against
`monet--hook-token`, so the token is the sole authorization boundary.

## monet-start-server-function returns a plist

`monet-start-server-function` returns:

```elisp
(:env ("ENABLE_IDE_INTEGRATION=true"
       "CLAUDE_CODE_SSE_PORT=<mcp-port>"
       "MONET_HOOK_PORT=<hook-port>"
       "MONET_HOOK_TOKEN=<token>")
 :ports (<mcp-port> <hook-port>))
```

- `:env` — environment variable assignments the spawned Claude process needs. This is how
  `MONET_HOOK_PORT` / `MONET_HOOK_TOKEN` reach `monet-claude-hook.py`.
  `ENABLE_IDE_INTEGRATION` must be the string `"true"` — Claude Code does not recognize
  other truthy spellings (it was previously the Elisp `t`, i.e. `"t"`, which Claude
  ignored).
- `:ports` — the host ports the Claude process must be able to reach (MCP port + hook
  port). Useful for sandboxing / firewalling callers that need to allow-list ports.

This is a change from the previous bare-list return value.

`monet-start-server-function` (and `monet-start-server-in-directory`) also take an
optional `PATH-MAPPINGS` arg — an alist of `(HOST-PREFIX . GUEST-PREFIX)` threaded into
the session for sandbox path translation. See
[architecture.md](architecture.md#guesthost-path-mapping).

## Envelope Format

The JSON body POSTed by the Python script is:

```json
{
  "hook_payload": { "hook_event_name": "Stop", ... },
  "monet_context": { "baton_session": "claude-1", ... }
}
```

- `hook_payload` — the raw JSON payload Claude Code sent to stdin
- `monet_context` — key/value pairs derived from `MONET_CTX_*` environment variables

## Context Variable Convention

Environment variables prefixed with `MONET_CTX_` are collected by the Python script
and passed as the `ctx` alist to each handler.  The prefix is stripped and the
remaining key is lowercased:

| Env var                   | ctx alist key   |
|---------------------------|-----------------|
| `MONET_CTX_BATON_SESSION` | `baton_session` |
| `MONET_CTX_SESSION_KEY`   | `session_key`   |

Inject these vars at spawn time via an env-function registered with the session manager
(e.g. `baton-add-env-function`).

## Handler Contract

Handlers registered via `monet-add-claude-hook-handler` are called with three arguments:

```elisp
(lambda (event-name data ctx)
  ...)
```

- `event-name` — string, e.g. `"Stop"`, `"Notification"`, `"UserPromptSubmit"`
- `data` — alist of the full `hook_payload` JSON object
- `ctx` — alist of context key/value pairs (from `MONET_CTX_*` env vars)

Errors in individual handlers are caught by `condition-case` and logged to `*Messages*`;
a failing handler does not block subsequent handlers.

## Supported Events

Installed by `monet-install-claude-hooks` into `~/.claude/settings.json`:

| Event             | When it fires                         |
|-------------------|---------------------------------------|
| `Stop`            | Claude Code agent run completes       |
| `SubagentStop`    | A subagent run completes              |
| `Notification`    | Claude Code sends a user notification |
| `UserPromptSubmit`| User submits a prompt                 |

## Handler Registration

```elisp
;; Register
(monet-add-claude-hook-handler #'my-handler)

;; Deregister
(monet-remove-claude-hook-handler #'my-handler)
```

`monet--claude-hook-functions` holds the current handler list.

## Hook Logging

Hook events are logged to `monet-log-buffer-name` (`*Monet Log*`) via `monet--log-hook`.
Logging is controlled by the same flag as MCP traffic logging:

```elisp
M-x monet-enable-logging   ; turns on both MCP traffic and hook logging
M-x monet-disable-logging  ; turns off both
```

Each hook event produces one log line:
```
[TIMESTAMP] HOOK event=Stop data=... ctx=...
```

## Managing Hook Entries

```elisp
M-x monet-install-claude-hooks  ; idempotent; adds entries to ~/.claude/settings.json
M-x monet-remove-claude-hooks   ; removes only monet's entries; other hooks preserved
```
