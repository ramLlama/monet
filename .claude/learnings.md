# Learnings

Append-only log of non-obvious lessons learned while working on monet. Newest entries at the bottom; timestamp each batch.

## 2026-06-11 — sandbox portability

- **Claude Code reaps IDE lockfiles whose pid is dead.** The lockfile's `pid` field is checked for liveness; a host Emacs pid does not exist inside a sandbox guest's pid namespace, so a guest claude silently *deleted* our lockfile — through the live `~/.claude` bind mount, erasing it host-side too. Writing pid 1 (alive in every pid namespace, launchd on the host) sidesteps this; monet manages its own lockfile lifecycle, so Claude-side reaping isn't load-bearing.
- **`ENABLE_IDE_INTEGRATION` must be the literal string `true`** — `t` is not recognized.
- **There is no env-var alternative to the lockfile auth token** (per official docs as of 2026-06): `CLAUDE_CODE_SSE_PORT` points claude at the port, but the token only travels via `~/.claude/ide/<port>.lock`. Sandboxed setups must share that directory.
- **Claude hook commands run through `/bin/sh`**, so `$HOME`-relative commands (`$HOME/.claude/hooks/…`) resolve correctly on host and guest despite different home directories. Registering repo-absolute script paths breaks any environment that doesn't mount the repo.
- **Path translation must be key-driven, never blanket.** Translating every string that looks like a path would corrupt `new_file_contents` (file bodies legitimately contain path strings). Translate only values under known protocol keys (`uri`, `old/new_file_path`, `filePath`, `workspaceFolders`), at exactly two choke points: inbound in `monet--on-message`, outbound in the send functions.
- **A websocket close destroys the session** (`monet--on-close-server` removes session + lockfile) — by design for the one-claude-per-session model, but invisible without the connect/disconnect messages added this round. When debugging "the lockfile vanished", check for a transient client connection first.
- **`cl-defstruct` accessors can't be stubbed with `cl-letf`** — call sites are eagerly macroexpanded/inlined at load time. Tests must build real struct instances instead (`make-monet--session :key … :port …`).
