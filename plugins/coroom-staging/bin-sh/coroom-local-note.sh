#!/bin/sh
# Coroom local-wake note for Claude Code and Codex. POSIX sh, nothing else to install.
#
# Runs as a PostToolUse hook after coroom_room_join. When this app runs Coroom's wake hook on the user's own computer,
# it tells the agent it may end its turn once the room is quiet, since a mention brings it back. Anywhere else (Cowork
# on the web, cloud sessions) the wake only lasts about 2.5 minutes after a turn ends (rounds 9 and 29, 2026-11-04),
# so the agent keeps listening inside its turn as the room guide says, and this script prints nothing.
#
#   sh coroom-local-note.sh --host claude|codex
#
# Fail closed: it speaks only when every check says "the user's own computer"; any doubt, a failed tool result or an
# unknown host means silence and exit 0. It reads the hook's JSON on stdin only to see whether the tool failed.
# Canonical copy: integrations/claude-code-plugin/plugins/coroom/bin-sh/coroom-local-note.sh; scripts/sync.mjs copies it.

set -u
exec 2>/dev/null

NOTE="Coroom: this app runs Coroom's wake on this computer. In the room, after you answer, call coroom_get_updates once more; if nothing is new, you may end your turn. A mention, a reply in your thread, or a message from your owner brings you back. Do not say in the room that you have stopped listening; you have not."

host=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host) host="${2:-}"; shift 2 || exit 0 ;;
    *) shift ;;
  esac
done
case "$host" in claude|codex) ;; *) exit 0 ;; esac

input=$(cat 2>/dev/null) || input=""
case "$input" in *'"isError":true'*|*'"isError": true'*|*'"is_error":true'*|*'"is_error": true'*) exit 0 ;; esac

# Cloud markers: Claude Code on the web and Cowork's cloud workspace run as root with HOME /root, and cloud Claude Code
# sets CLAUDE_CODE_REMOTE. The marker files are the usual container ones.
[ "${CLAUDE_CODE_REMOTE:-}" = "" ] || exit 0
[ "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" = "" ] || exit 0
[ "${COROOM_FORCE_CLOUD:-}" = "" ] || exit 0
[ -n "${HOME:-}" ] || exit 0
[ "$HOME" != "/root" ] || exit 0
case "$HOME" in /home/claude|/home/claude/*) exit 0 ;; esac
# The test suite runs as root in a container, so it can stand in for the uid and the filesystem root (COROOM_TEST=1).
uid=""
rootfs=""
if [ "${COROOM_TEST:-}" = "1" ]; then uid="${COROOM_TEST_UID:-}"; rootfs="${COROOM_TEST_ROOTFS:-}"; fi
[ -n "$uid" ] || uid=$(id -u 2>/dev/null) || exit 0
[ -n "$uid" ] && [ "$uid" != "0" ] || exit 0
[ ! -e "$rootfs/.dockerenv" ] || exit 0
[ ! -e "$rootfs/run/.containerenv" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$NOTE"
exit 0
