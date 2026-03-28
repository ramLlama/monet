# Monet

> **Note:** This is a fork of [stevemolitor/monet](https://github.com/stevemolitor/monet) with significant, incompatible changes — most notably the replacement of `defcustom` tool variables with a dynamic tool registry API. If you're looking for the original project compatible with [claude-code.el](https://github.com/stevemolitor/claude-code.el), head there.

![Claude Monet Self Portrait](https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Autoportret_Claude_Monet.jpg/512px-Autoportret_Claude_Monet.jpg)

<sub>Self Portrait with a Beret, 1886 by Claude Monet. Source: Wikimedia Commons</sub>

Monet is an Emacs package that implements the (undocumented) [Claude Code](https://docs.anthropic.com/en/docs/claude-code) IDE protocol, enabling Claude to interact with your Emacs environment through a WebSocket connection.

You can use Monet with Claude Code running in your favorite terminal emulator (Ghostty, Kitty, iTerm2, WezTerm), or with packages like [baton](https://github.com/ramLlama/baton) that run Claude Code directly inside Emacs.

## Features

- Selection context: current selection in Emacs is automatically shared with Claude Code
- Send diagnostics from Flymake/Flycheck (and thus LSP in LSP modes) to Claude
- Create diff views in Emacs before Claude applies changes
- Project-aware session management
- Multiple concurrent sessions support
- Dynamic tool registry for overriding or extending MCP tools
- Optional introspection tools (xref, imenu, tree-sitter)

## Requirements

- Emacs 30.0 or later
- [websocket](https://github.com/ahyatt/emacs-websocket) package

## Installation

### Using use-package with :vc (Emacs 30+)

```elisp
(use-package monet
  :vc (:url "https://github.com/ramLlama/monet" :rev :newest))
```

### Using straight.el

```elisp
(straight-use-package
 '(monet :type git :host github :repo "ramLlama/monet"))
```

### Manual Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/ramLlama/monet.git
   ```

2. Add to your Emacs configuration:
   ```elisp
   (add-to-list 'load-path "/path/to/monet")
   (require 'monet)
   ```

## Usage

### Quick Start

1. Enable Monet mode:
   ```elisp
   M-x monet-mode
   ```

2. Start a Monet server:
   ```
   C-c m s    ; Start server in current project/directory
   ```

3. In Claude Code, start a new chat and use the /ide slash command to connect to your Emacs session.

To have Claude automatically connect to your Monet session set `ENABLE_IDE_IDE=t` before starting Claude.

If you have multiple Monet sessions for the same project you can do this to have Claude automatically connect to the desired instance:

```sh
ENABLE_IDE_INTEGRATION=t && CLAUDE_CODE_SSE_PORT=123456 && claude
```

Monet prints a message with the port number when you call `monet-start-server` (`C-c m s`). You can see the list of all running servers with their ports and directories via `monet-list-sessions` (`C-c m l`).

### Session Management

Sessions are automatically cleaned up (killed) when you exit the associated Claude session. When you exit Emacs all sessions are cleaned up. You can stop a session manually via `monet-stop-server` (`C-c m q`).

Monet automatically creates session keys based on your context:
- When in a project (via `project.el`), uses the project name
- Otherwise, uses the current directory name
- Automatically generates unique keys for multiple sessions (e.g., `project<2>`)

With a prefix argument (`C-u C-c m s`), you can manually select a directory.

### Example

Here's Monet in action - Claude running in Ghostty terminal communicating with Emacs:

![Claude running in Ghostty communicating with Emacs](https://cdn.zappy.app/d38bcc5c3ee4894795dbbc5c1cd062e4.png)

### Key Bindings

When `monet-mode` is enabled, the following key bindings are available (default prefix: `C-c m`):

- `C-c m s` - Start server
- `C-c m q` - Stop server (with completion)
- `C-c m Q` - Stop all servers
- `C-c m l` - List active sessions
- `C-c m L` - Enable logging
- `C-c m D` - Disable logging

### Using the Diff Tools

When Claude proposes code changes, Monet displays them in a diff view:

- **Simple Diff Tool** (default): A read-only diff view showing the proposed changes
  - Press `y` to accept Claude's changes exactly as shown
  - Press `q` to reject the changes

- **Ediff Tool**: An interactive diff view that allows you to edit the changes before accepting
  - Navigate between differences using `n` (next) and `p` (previous)
  - Edit the proposed changes directly in the buffer
  - Press `C-c C-c` to accept your edited version (your changes will be sent to Claude)
  - Press `q` to reject all changes

**Important**: With the ediff tool, any manual edits you make to the proposed changes are captured and sent to Claude when you accept. This allows you to refine Claude's suggestions before applying them.

### Customization

```elisp
;; Change the prefix key (default: "C-c m")
(setq monet-prefix-key "C-c C-m")

;; Or disable prefix key and use M-x commands only
(setq monet-prefix-key nil)

;; Change log buffer name
(setq monet-log-buffer-name "*My Monet Log*")

;; Customize diff keybindings
(setq monet-ediff-accept-key "C-c C-a")      ; Default: "C-c C-c"
(setq monet-ediff-quit-key "C-g")            ; Default: "q"
(setq monet-simple-diff-accept-key "C-c C-c")      ; Default: "y"
(setq monet-simple-diff-quit-key "C-g")      ; Default: "q"

;; Change ediff window split direction
(setq monet-ediff-split-window-direction 'vertical)  ; Default: 'horizontal

;; Hide diff buffers when editing unrelated files
(setq monet-hide-diff-when-irrelevant t)

;; Don't display diff buffers in tabs other than the originating tab
(setq monet-do-not-disturb t)
```

### Tool Registry

Monet uses a dynamic tool registry to manage all MCP tools. Tools are organized into **sets** identified by keywords.

#### Built-in Tool Sets

- **`:core`** (enabled by default): `getCurrentSelection`, `getLatestSelection`, `getDiagnostics`, `getOpenEditors`, `getWorkspaceFolders`, `checkDocumentDirty`, `saveDocument`, `openFile`
- **`:diff`** (enabled by default): `openDiff`, `closeAllDiffTabs`, `close_tab`
- **`:emacs-tools`** (disabled by default, opt-in via `monet-emacs-tools.el`): `xref_find_definitions`, `xref_find_references`, `imenu_list_symbols`, `treesit_info`

#### Overriding a Tool

Replace any built-in tool by re-registering it with `monet-make-tool`:

```elisp
;; Use ediff instead of the default simple diff
(monet-make-tool :name "openDiff"
                 :description "Show diff in ediff"
                 :schema monet-open-diff-tool-schema
                 :handler (monet-make-open-diff-handler #'monet-ediff-tool)
                 :set :diff)
```

Re-registering with the same `(set . name)` key replaces the definition while preserving its current enabled state.

#### Custom Tools

Register entirely new tools under a custom set:

```elisp
(monet-make-tool :name "myCustomTool"
                 :description "Does something custom"
                 :schema '((type . "object")
                           (properties . ((input . ((type . "string")
                                                    (description . "Input value"))))))
                 :handler #'my-custom-handler
                 :set :my-tools)

;; Enable your custom tool set
(monet-enable-tool-set :my-tools)
```

#### Managing Tool Sets

```elisp
;; Enable/disable entire sets
(monet-enable-tool-set :emacs-tools)
(monet-disable-tool-set :diff)

;; Enable/disable individual tools
(monet-enable-tool "getDiagnostics")
(monet-disable-tool "getDiagnostics")

;; Reset all tools to disabled
(monet-reset-tools)

;; Restore all built-in tools to defaults (clears custom tools!)
(monet-register-core-tools)
```

**Note:** `monet-register-core-tools` clears the entire registry and re-registers built-ins. Any custom tools (e.g. from `monet-emacs-tools.el`) must be re-registered after calling it.

#### Default Tool Implementations

Each built-in tool delegates to a public `monet-default-*` or `monet-*-tool` function. These are useful as building blocks when writing custom handlers:

- `monet-default-get-current-selection-tool`
- `monet-default-get-latest-selection-tool`
- `monet-default-open-file-tool`
- `monet-default-save-document-tool`
- `monet-default-check-document-dirty-tool`
- `monet-default-get-open-editors-tool`
- `monet-default-get-workspace-folders-tool`
- `monet-flymake-flycheck-diagnostics-tool`
- `monet-simple-diff-tool` / `monet-simple-diff-cleanup-tool`
- `monet-ediff-tool` / `monet-ediff-cleanup-tool`

### Introspection Tools (optional)

`monet-emacs-tools.el` provides additional tools that expose Emacs introspection capabilities to Claude:

- **xref_find_definitions** / **xref_find_references** — jump-to-definition and find-references via xref backends
- **imenu_list_symbols** — list symbols in a file via imenu
- **treesit_info** — tree-sitter node info at a position (requires Emacs 29+ with tree-sitter)

To enable:

```elisp
(require 'monet-emacs-tools)
(monet-register-emacs-tools)
(monet-enable-tool-set :emacs-tools)
```

Or enable individual tools:

```elisp
(require 'monet-emacs-tools)
(monet-register-emacs-tools)
(monet-enable-tool "imenu_list_symbols")
```

## How It Works

Monet creates a WebSocket server that Claude Code connects to via MCP. This allows Claude to:

- Browse and open files in your project
- See real-time diagnostics from your linters
- Create side-by-side diffs for code review
- Track your current selection/cursor position

Each session is isolated to a specific directory/project, ensuring Claude only accesses files within the intended scope.

## Troubleshooting

- **Check active sessions**: `C-c m l` to list all running servers
- **Enable logging**: `C-c m L` to see all MCP communication

## Images

### Simple Monet Diff Tool with Ghostty

![Monet and Ghostty Diff](https://cdn.zappy.app/99797ecef1d5a12fc36bb72b39aa8464.png)

### Monet Ediff Tool inside claude-code.el

![Monet Ediff in claude-code.el](https://cdn.zappy.app/9198756659a0fcfedda2a14bc6b5fdb0.png)
