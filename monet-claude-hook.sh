#! /usr/bin/env bash
# monet-claude-hook.sh --- Claude Code lifecycle hook script
#
# Invoked by Claude Code when lifecycle events fire (Stop, SubagentStop,
# Notification, etc.).  Reads JSON from stdin into a temp file, calls
# emacsclient to deliver it to monet-claude-hook-receive, then deletes the
# temp file.
#
# MONET_EMACS_SOCKET is injected by monet at Claude Code spawn time so that
# all hook invocations reach the correct Emacs instance automatically.

TMPFILE=$(mktemp /tmp/monet-hook-XXXXXX.json)
cat > "$TMPFILE"
emacsclient ${MONET_EMACS_SOCKET:+-s "$MONET_EMACS_SOCKET"} \
    -e "(monet-claude-hook-receive \"$TMPFILE\")" 2>/dev/null || true
rm -f "$TMPFILE"
