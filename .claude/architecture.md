# Monet Architecture

## System Overview

Monet acts as an MCP (Model Context Protocol) server embedded in Emacs, communicating with Claude Code over WebSocket using JSON-RPC 2.0.

```
Claude Code (terminal/claude-code.el)
    |
    | WebSocket (JSON-RPC 2.0, "mcp" subprotocol)
    |
    v
monet.el WebSocket Server (one per session, localhost:<random-port>)
    |
    +-- Session Management (monet--sessions hash table)
    +-- MCP Protocol Handlers (initialize, tools/list, tools/call, etc.)
    +-- Tool Implementations (selection, diff, diagnostics, file ops)
    +-- Selection Tracking (post-command-hook -> debounced notifications)
    +-- Diff Display (simple diff-mode or ediff)
    +-- Logging (advice-based message tracing)
```

## Connection Lifecycle

1. **Server start** (`monet-start-server-in-directory`):
   - Find random free port (10000-65535)
   - Generate UUID auth token
   - Create `monet--session` struct
   - Start WebSocket server with `websocket-server`
   - Write lockfile to `~/.claude/ide/<port>.lock` (`pid` is LOCKFILE-PID when given -- sandboxed callers pass 1 -- else `(emacs-pid)`; `workspaceFolders` lists the host folder plus the guest path when path mappings apply)
   - Register `post-command-hook` for selection tracking

2. **Client connection** (`monet--on-open-server`):
   - Store client WebSocket reference in session
   - Message client-connected to `*Messages*` (observable)

3. **Handshake**:
   - Claude sends `initialize` request
   - Monet responds with capabilities (tools, prompts, resources)
   - Session marked as `initialized`
   - Monet sends `notifications/tools/list_changed`

4. **IDE connected** (`ide_connected` notification from Claude):
   - Start 30-second ping timer
   - Send initial selection state

5. **Normal operation**:
   - Claude calls tools via `tools/call`
   - Monet sends `selection_changed` notifications on cursor movement
   - Diff operations use deferred response pattern

6. **Shutdown** (`monet--on-close-server`):
   - Message client-disconnected to `*Messages*` (the session/lockfile removal is now observable)
   - Remove lockfile
   - Remove session from hash table
   - Clean up hooks if last session

## Message Routing

`monet--on-message` first translates inbound `params` to host paths (see [Guest/Host Path Mapping](#guesthost-path-mapping)), then dispatches based on the `method` field:

| Method | Handler | Notes |
|--------|---------|-------|
| `initialize` | `monet--handle-initialize` | Handshake, returns capabilities |
| `tools/list` | `monet--handle-tools-list` | Returns available tool definitions |
| `tools/call` | `monet--handle-tools-call` | Dispatches to tool handlers |
| `prompts/list` | (inline) | Returns empty list |
| `resources/list` | `monet--handle-resources-list` | Open buffers + recent files + project files |
| `resources/read` | `monet--handle-resources-read` | Read file content by URI |
| `ide_connected` | `monet--handle-ide-connected` | Start keepalive, send selection |
| `notifications/initialized` | (no-op) | Notification, no response |

## Tool Dispatch Architecture

Tools use a two-layer pattern:

1. **Protocol adapter** (e.g., `monet--tool-open-file-handler`): Extracts params from MCP request, calls the customizable function
2. **Customizable implementation** (e.g., `monet-default-open-file-tool`): Actual logic, replaceable via `defcustom`

`monet--get-tool-handler` maps tool names to protocol adapter functions. Diff tools are conditionally included based on `monet-diff-tool` being non-nil.

## Deferred Response Flow (Diff)

```
Claude: tools/call openDiff {old_file_path, new_file_path, new_file_contents, tab_name}
    |
    v
monet--tool-open-diff-handler:
    1. Create diff display (simple or ediff)
    2. Store request ID in deferred-responses[tab_name]
    3. Return {deferred: t, unique-key: tab_name} (NO MCP response sent yet)
    |
    v  [user interacts with diff buffer]
    |
    +-- User presses accept key:
    |     on-accept callback fires
    |     -> monet--complete-deferred-response(tab_name, FILE_SAVED + final_contents)
    |     -> MCP response sent with actual file contents
    |
    +-- User presses quit key:
          on-quit callback fires
          -> monet--complete-deferred-response(tab_name, DIFF_REJECTED)
          -> MCP response sent with rejection
          -> Diff cleaned up after 200ms delay
```

## Diff Visibility Management

When `monet-hide-diff-when-irrelevant` is enabled:
- `post-command-hook` triggers `monet--track-diff-visibility` (debounced at 100ms)
- For each active diff, checks if current buffer is "relevant" (same session directory or initiating file)
- Shows/hides diff windows by switching them to/from previous buffers

## Guest/Host Path Mapping

When Claude runs inside a sandbox (microVM guest), it sees the workspace at a guest path (e.g. `/workspace`) while Emacs/monet operate on the host path. A session may carry `path-mappings` -- an alist of `(HOST-PREFIX . GUEST-PREFIX)`. Path-bearing protocol fields are translated at the WebSocket boundary so every handler runs in host terms while Claude always sees guest terms.

Translation choke points (host is canonical internally):

| Direction | Where | What |
|-----------|-------|------|
| inbound → host | `monet--on-message` | the full `params` alist, once, before dispatch |
| outbound → guest | `monet--send-response` | the `result` payload |
| outbound → guest | `monet--send-notification` | the `params` payload |

Outbound functions recover the session via `monet--find-session-by-client` (they receive a websocket, not a session).

Translation is **key-driven**, not value-sniffing:
- `monet--path-keys` (`uri`, `old_file_path`, `new_file_path`, `filePath`, `path`) -- alist keys whose string value is a single path.
- `monet--path-list-keys` (`workspaceFolders`) -- alist keys whose value is a sequence of paths.
- `monet--translate-walk` deep-copies the payload, rewriting only values under those keys. Content fields (e.g. `new_file_contents`) are never touched even when they embed path-like text.
- `monet--translate-path` does the prefix rewrite: longest-prefix-first, matching only at path-segment boundaries (so `/ws/feat` does not match `/ws/feat-other`), and `file://`-aware (rewrites only the path part of a `file://` URI).
- `monet--translate-paths` is the entry point; it returns the payload **unchanged (eq, no copy)** when the session has no mappings, so non-sandboxed sessions pay nothing.

The lockfile also advertises the guest view of the session folder as an extra `workspaceFolders` entry (see [Connection Lifecycle](#connection-lifecycle)), so a sandboxed Claude matches the lockfile against its in-guest cwd.

## Selection Tracking

- `monet--track-selection-change` runs on every `post-command-hook`
- Debounced at 50ms via `monet--selection-timer`
- Only fires when buffer has a file and at least one initialized session exists
- Sends `selection_changed` notification with cursor/region position, file path, selected text
- Handles evil-mode visual line selection specially (adjusts start/end positions)

## Key Data Structures

### `monet--session` (cl-defstruct)
- `key`: Unique session identifier (project name or directory name, with `<N>` suffix for duplicates)
- `server`: WebSocket server process
- `client`: WebSocket client connection (set on connect)
- `directory`: Project/workspace root directory
- `port`: WebSocket server port
- `initialized`: Boolean, set after MCP handshake
- `auth-token`: UUID for connection authentication
- `opened-diffs`: Hash table of `tab-name -> diff-context` alist
- `deferred-responses`: Hash table of `unique-key -> request-id`
- `originating-buffer/tab/frame`: Context for do-not-disturb mode
- `path-mappings`: Alist of `(HOST-PREFIX . GUEST-PREFIX)` for sandbox path translation; nil for non-sandboxed sessions

### `monet--sessions` (hash table)
Global registry: `session-key -> monet--session`

### Diff context (alist)
Returned by diff tool functions, enhanced by the handler with session info:
- `diff-buffer`, `old-temp-buffer`, `new-temp-buffer` (simple diff)
- `control-buffer`, `new-buffer`, `old-buffer`, `window-config` (ediff)
- `initiating-file`, `session-directory`, `tab-name` (added by handler)