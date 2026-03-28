# Monet

## What This Project Does

Monet is an Emacs package that implements the (undocumented) Claude Code IDE protocol, enabling Claude to interact with an Emacs environment through a WebSocket connection using MCP (Model Context Protocol). It allows Claude Code (running in any terminal or via claude-code.el) to see editor selections, display diffs for code review, access diagnostics from Flymake/Flycheck, and manage files -- all within Emacs.

## Tech Stack

- **Language**: Emacs Lisp (`monet.el` core + `monet-emacs-tools.el` extension)
- **Emacs version**: 30.0+ required (tree-sitter tools require 29+)
- **Dependencies**: `websocket` package (emacs-websocket 1.15+)
- **Built-in deps**: `cl-lib`, `diff`, `ediff`, `json`, `project`, `subr-x`, `xref`, `imenu`
- **Protocol**: JSON-RPC 2.0 over WebSocket, MCP protocol version `2024-11-05`
- **Build**: Makefile with `checkdoc`, `byte-compile`, and `test` (ERT) targets

## Repository Structure

```
monet/
  monet.el                      # Core implementation (~2160 lines)
  monet-emacs-tools.el          # Opt-in introspection tools (xref, imenu, treesit)
  monet-tests.el                # ERT test suite (30 tests)
  Makefile                      # Build: checkdoc + byte-compile + test targets
  README.md                     # User-facing documentation
  CHANGELOG.md                  # Version history (currently at 0.0.3)
  LICENSE                       # Project license
  context-aware-diff-hiding.md  # Design doc for diff visibility feature
  test-diff-visibility.el       # Manual test script for diff visibility
  .gitignore                    # Ignores .elc, backups, sockets-mcp/
```

## Key Concepts & Domain Model

### Sessions (`monet--session` struct)
Each Claude Code connection is a **session**, stored in `monet--sessions` hash table. A session owns:
- A WebSocket server (one per session, random port 10000-65535)
- A lockfile at `~/.claude/ide/<port>.lock` that Claude Code discovers
- Opened diffs (hash table keyed by `tab-name`)
- Deferred responses (for async diff accept/reject flows)
- Originating buffer/tab/frame context

### Tool Registry
Tools are managed via a dynamic registry (`monet--tool-registry`), an alist of `(name . spec-plist)`. Each spec has `:description`, `:schema`, `:handler`, `:set`, and `:enabled`.

**Public API** (defined in `monet.el`):
- `monet-make-tool &rest plist` -- add or replace a tool (`:name`, `:description`, `:schema`, `:handler`, `:set`)
- `monet-enable-tool NAME` / `monet-disable-tool NAME` -- toggle a single tool
- `monet-enable-tool-set SET &optional RESET` / `monet-disable-tool-set SET` -- toggle all tools in a set
- `monet-reset-tools` -- disable every tool
- `monet-register-core-tools` -- reset registry and register all built-ins (called by `monet-mode`)

**Tool sets:**
- `:core` -- enabled by default: getCurrentSelection, getLatestSelection, getDiagnostics, getOpenEditors, getWorkspaceFolders, checkDocumentDirty, saveDocument, openFile
- `:diff` -- enabled by default: openDiff, closeAllDiffTabs, close_tab
- `:emacs-tools` -- disabled by default (opt-in via `monet-emacs-tools.el`)
- Custom sets -- any keyword; disabled by default on first registration

**Overriding a tool (e.g. for Birbal):**
```elisp
(monet-make-tool :name "openDiff"
                 :description "..."
                 :schema '(...)
                 :handler #'birbal--open-diff-handler
                 :set :birbal)
```
Re-registering preserves the current `:enabled` state (ownership transfer).

**Restoring defaults:** `(monet-register-core-tools)` clears the entire registry and re-registers built-ins. Call extension registration functions after it.

### MCP Tools
The package exposes these tools to Claude Code via the MCP protocol:
- `getCurrentSelection` / `getLatestSelection` -- editor selection state
- `openFile` / `saveDocument` / `checkDocumentDirty` -- file operations
- `getOpenEditors` / `getWorkspaceFolders` -- workspace state
- `getDiagnostics` -- Flymake/Flycheck error collection
- `openDiff` / `closeAllDiffTabs` / `close_tab` -- diff display management

### Diff Tools
Two diff display implementations in `monet.el`:
1. **Simple diff** (default): Read-only `diff-mode` buffer, accept (`y`) or reject (`q`)
2. **Ediff** (`monet-ediff-tool`): Interactive ediff session

The active strategy is selected by which handler is registered for `openDiff` via `monet-make-tool`. Each diff tool returns a context alist that includes a `cleanup-fn` key; `monet--cleanup-diff` dispatches to it polymorphically (falls back to `monet-simple-diff-cleanup-tool`).

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
```bash
make test         # Run ERT test suite (monet-tests.el, 30 tests)
```

The ERT suite in `monet-tests.el` covers the tool registry API, dispatch, enable/disable semantics, ownership transfer, and introspection tool formatting. Tests use the `monet-test-with-clean-registry` macro to isolate the global registry.

`test-diff-visibility.el` is a separate manual integration test for diff visibility logic:
```bash
emacs --batch -L . -l test-diff-visibility.el
```

`make test` requires the `websocket` package to be installed (via `M-x package-install RET websocket`); it is discovered automatically via `(package-initialize)`.

### Loading for Development
```elisp
(add-to-list 'load-path "/path/to/monet")
(require 'monet)
(monet-mode 1)
```

## Critical Idiosyncrasies & Gotchas

1. **Multi-file package**: Core in `monet.el` (~2160 lines); opt-in introspection tools in `monet-emacs-tools.el`; ERT tests in `monet-tests.el`.

2. **Version mismatch**: `monet-version` constant is `"0.0.1"` but `Package-Requires` header says `Version: 0.0.3`. These are out of sync.

3. **Deferred response pattern**: `openDiff` does NOT return an immediate MCP response. The response ID is stashed in `deferred-responses` and sent later when the user accepts/rejects. This is critical to understand when modifying diff handling.

4. **Evil-mode compatibility**: Significant code exists to handle evil-mode keybinding conflicts in diff buffers. The package creates a `monet-diff-mode` minor mode specifically for this. Changes to keybinding logic must preserve evil-mode support.

5. **Tool customization via registry**: Override any built-in tool with `monet-make-tool`. The defcustom override variables (`monet-diff-tool`, `monet-open-file-tool`, etc.) have been removed — this is a breaking change from ≤0.0.3. Re-registering preserves `:enabled` state.

6. **`monet-register-core-tools` clears everything**: It does `(setq monet--tool-registry nil)` then re-registers built-ins. Any externally registered tools (e.g. `:emacs-tools` set) are lost. Always call extension registration functions *after* `monet-register-core-tools`.

7. **Polymorphic diff cleanup**: `monet--cleanup-diff` calls the `cleanup-fn` stored in the diff context alist. Both `monet-simple-diff-tool` and `monet-ediff-tool` set this. Custom `openDiff` handlers must include `cleanup-fn` in their returned context or cleanup will silently fall back to `monet-simple-diff-cleanup-tool`.

8. **Lockfile protocol**: Lockfiles at `~/.claude/ide/<port>.lock` contain JSON with `pid`, `workspaceFolders`, `ideName`, `transport`, and `authToken`. Claude Code discovers these to connect. Windows uses `USERPROFILE` instead of `~`.

9. **Selection tracking runs on `post-command-hook`**: Every keystroke triggers selection tracking logic (debounced at 50ms). This must remain lightweight.

10. **Ping keepalive**: A 30-second ping timer sends `notifications/tools/list_changed` as a keepalive. This is a workaround, not a real tools list change.

11. **Tab-bar integration**: Session tracks `originating-tab` for do-not-disturb mode. The code checks `tab-bar-mode` and `tab-bar--current-tab` (internal Emacs API).

12. **Emacs-specific tools are opt-in**: `monet-emacs-tools.el` must be loaded and `monet-register-emacs-tools` called, then `(monet-enable-tool-set :emacs-tools)`. The `treesit_info` tool requires tree-sitter support (Emacs 29+ with `--with-tree-sitter`).

## Context Files

- [Architecture Details](architecture.md)
- [Style Guide](style-guide.md)