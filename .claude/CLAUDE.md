# Monet

## What This Project Does

Monet is an Emacs package that implements the (undocumented) Claude Code IDE protocol, enabling Claude to interact with an Emacs environment through a WebSocket connection using MCP (Model Context Protocol). It allows Claude Code (running in any terminal or via claude-code.el) to see editor selections, display diffs for code review, access diagnostics from Flymake/Flycheck, and manage files -- all within Emacs.

## Tech Stack

- **Language**: Emacs Lisp (single file: `monet.el`)
- **Emacs version**: 30.0+ required
- **Dependencies**: `websocket` package (emacs-websocket 1.15+)
- **Built-in deps**: `cl-lib`, `diff`, `ediff`, `json`, `project`, `subr-x`
- **Protocol**: JSON-RPC 2.0 over WebSocket, MCP protocol version `2024-11-05`
- **Build**: Makefile with `checkdoc` and `byte-compile` targets

## Repository Structure

```
monet/
  monet.el                      # Entire package implementation (~2140 lines)
  Makefile                      # Build: checkdoc linting + byte-compilation
  README.md                     # User-facing documentation
  CHANGELOG.md                  # Version history (currently at 0.0.3)
  LICENSE                       # Project license
  context-aware-diff-hiding.md  # Design doc for diff visibility feature
  test-diff-visibility.el       # Manual test script for diff visibility
  .gitignore                    # Ignores .elc, backups, sockets-mcp/
```

This is a single-file Emacs package -- all code lives in `monet.el`.

## Key Concepts & Domain Model

### Sessions (`monet--session` struct)
Each Claude Code connection is a **session**, stored in `monet--sessions` hash table. A session owns:
- A WebSocket server (one per session, random port 10000-65535)
- A lockfile at `~/.claude/ide/<port>.lock` that Claude Code discovers
- Opened diffs (hash table keyed by `tab-name`)
- Deferred responses (for async diff accept/reject flows)
- Originating buffer/tab/frame context

### MCP Tools
The package exposes these tools to Claude Code via the MCP protocol:
- `getCurrentSelection` / `getLatestSelection` -- editor selection state
- `openFile` / `saveDocument` / `checkDocumentDirty` -- file operations
- `getOpenEditors` / `getWorkspaceFolders` -- workspace state
- `getDiagnostics` -- Flymake/Flycheck error collection
- `openDiff` / `closeAllDiffTabs` / `close_tab` -- diff display management

### Diff Tools
Two diff display strategies, set via `monet-diff-tool`:
1. **Simple diff** (default): Read-only `diff-mode` buffer, accept (`y`) or reject (`q`)
2. **Ediff**: Interactive ediff session where user can edit proposed changes before accepting

### Deferred Responses
The `openDiff` tool uses a deferred response pattern: the MCP request is not immediately answered. Instead, the response ID is stored, and the actual response is sent when the user accepts or rejects the diff.

## Architecture Overview

See [architecture.md](architecture.md) for details.

The flow is:
1. User calls `monet-start-server` -- creates WebSocket server on random port, writes lockfile
2. Claude Code discovers the lockfile, connects via WebSocket
3. Claude sends JSON-RPC requests (`initialize`, `tools/list`, `tools/call`)
4. Monet dispatches to tool handlers, returns results
5. Monet proactively sends `selection_changed` notifications via `post-command-hook`
6. Diff interactions use deferred responses -- the MCP response is sent only when user acts

## Development Workflow

### Build & Lint
```bash
make              # Run checkdoc + byte-compile
make checkdoc     # Lint docstrings
make compile      # Byte-compile
make clean        # Remove .elc files
```

### Testing
There are no automated tests (no ERT test suite). The file `test-diff-visibility.el` is a manual integration test script that creates mock sessions and tests diff visibility logic. Run it with:
```bash
emacs --batch -L . -l test-diff-visibility.el
```

### Loading for Development
```elisp
(add-to-list 'load-path "/path/to/monet")
(require 'monet)
(monet-mode 1)
```

## Critical Idiosyncrasies & Gotchas

1. **Single-file package**: All ~2140 lines are in `monet.el`. No modular file organization.

2. **Version mismatch**: `monet-version` constant is `"0.0.1"` but `Package-Requires` header says `Version: 0.0.3`. These are out of sync.

3. **No automated tests**: Only a manual test script exists. Any changes should be tested by actually running Monet with Claude Code.

4. **Deferred response pattern**: `openDiff` does NOT return an immediate MCP response. The response ID is stashed in `deferred-responses` and sent later when the user accepts/rejects. This is critical to understand when modifying diff handling.

5. **Evil-mode compatibility**: Significant code exists to handle evil-mode keybinding conflicts in diff buffers. The package creates a `monet-diff-mode` minor mode specifically for this. Changes to keybinding logic must preserve evil-mode support.

6. **All tools are customizable**: Each MCP tool has a `defcustom` variable (e.g., `monet-diagnostics-tool`, `monet-open-file-tool`) that users can override with custom functions. The handler functions are thin adapters between MCP protocol and these customizable functions.

7. **Lockfile protocol**: Lockfiles at `~/.claude/ide/<port>.lock` contain JSON with `pid`, `workspaceFolders`, `ideName`, `transport`, and `authToken`. Claude Code discovers these to connect. Windows uses `USERPROFILE` instead of `~`.

8. **Selection tracking runs on `post-command-hook`**: Every keystroke triggers selection tracking logic (debounced at 50ms). This must remain lightweight.

9. **Ping keepalive**: A 30-second ping timer sends `notifications/tools/list_changed` as a keepalive. This is a workaround, not a real tools list change.

10. **Tab-bar integration**: Session tracks `originating-tab` for do-not-disturb mode. The code checks `tab-bar-mode` and `tab-bar--current-tab` (internal Emacs API).

## Context Files

- [Architecture Details](architecture.md)
- [Style Guide](style-guide.md)