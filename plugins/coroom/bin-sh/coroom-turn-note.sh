#!/bin/sh
# Coroom per-turn listening note for Claude (Cowork and cloud sessions). POSIX sh, nothing else to install.
#
# Runs as a UserPromptSubmit hook. When this session has joined a Coroom room and not left it, it puts one line next to
# the user's message: answer your user, then go back to coroom_get_updates in the same turn. Round 33 (2026-11-05):
# a Cowork web agent that kept listening when nobody talked to it ended its turn after answering each question from
# its user. The line reaches the model on every message (HOST-FACTS CL-15).
#
#   sh coroom-turn-note.sh --host claude
#
# Joined or left is read from the transcript's tool_use entries named ...coroom_room_join and ...coroom_room_leave,
# the last one winning (HOST-FACTS CL-16); a plain grep also counts the tool lists and server instructions. It stays
# silent where the local-wake note applies (Claude Code on the user's own computer), since there the agent may end
# its turn. Any error, no transcript or no join means silence and exit 0. It never prints room content.
# Canonical copy: integrations/claude-code-plugin/plugins/coroom/bin-sh/coroom-turn-note.sh; scripts/sync.mjs copies it.

set -u
exec 2>/dev/null

NOTE="Coroom: you are in a Coroom room. Answer your user, then call coroom_get_updates again in this same turn and keep listening. Do not end your turn or say you will stop listening."

host=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host) host="${2:-}"; shift 2 || exit 0 ;;
    *) shift ;;
  esac
done
[ "$host" = "claude" ] || exit 0

# True on the user's own computer: the same checks as coroom-local-note.sh, where the agent may end its turn instead.
is_local() {
  [ "${CLAUDE_CODE_REMOTE:-}" = "" ] || return 1
  [ "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" = "" ] || return 1
  [ "${COROOM_FORCE_CLOUD:-}" = "" ] || return 1
  [ -n "${HOME:-}" ] || return 1
  [ "$HOME" != "/root" ] || return 1
  case "$HOME" in /home/claude|/home/claude/*) return 1 ;; esac
  _uid=""
  _rootfs=""
  if [ "${COROOM_TEST:-}" = "1" ]; then _uid="${COROOM_TEST_UID:-}"; _rootfs="${COROOM_TEST_ROOTFS:-}"; fi
  [ -n "$_uid" ] || _uid=$(id -u 2>/dev/null) || return 1
  [ -n "$_uid" ] && [ "$_uid" != "0" ] || return 1
  [ ! -e "$_rootfs/.dockerenv" ] || return 1
  [ ! -e "$_rootfs/run/.containerenv" ] || return 1
  return 0
}
if is_local; then exit 0; fi

input=$(cat 2>/dev/null) || exit 0
tp=$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ -n "$tp" ] && [ -f "$tp" ] || exit 0

# The last tool_use entry for a join or a leave, in transcript order.
last=$(grep -E -o '"type":"tool_use",("[A-Za-z_]+":"[^"]*",)*"name":"mcp__[A-Za-z0-9_.-]*__coroom_room_(join|leave)"' "$tp" | tail -n 1)
case "$last" in
  *coroom_room_join\") ;;
  *) exit 0 ;;
esac

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$NOTE"
exit 0
