# Claude Code Lifecycle Hooks

## Overview

Monet installs a Python script (`monet-claude-hook.py`) as a Claude Code lifecycle hook.
When Claude Code fires a lifecycle event, it invokes the script with a JSON payload on
stdin.  The script delivers the event to Emacs via `emacsclient`, where registered
Elisp handlers dispatch on the event name.

## Hook Pipeline

```
Claude Code
  → spawns monet-claude-hook.py (JSON on stdin)
     → reads payload from stdin
     → collects MONET_CTX_* env vars into ctx dict
     → writes {"hook_payload": payload, "monet_context": ctx} to temp file
     → calls emacsclient -e '(monet-claude-hook-receive "/tmp/monet-hook-*.json")'
     → deletes temp file (finally block)
  → Emacs: monet-claude-hook-receive
     → parses envelope
     → calls monet--log-hook (if logging enabled)
     → dispatches each handler with (event-name data ctx)
```

## Envelope Format

The temp file written by the Python script contains:

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

## MONET_EMACS_SOCKET

If `MONET_EMACS_SOCKET` is set in the environment at Claude Code spawn time, the Python
script passes `-s <socket>` to `emacsclient`, routing events to the correct Emacs
instance.  `monet-start-server-function` injects this automatically.