#!/bin/sh
# Coroom diagnostic hook, test only (2026-10-31, Cowork wake experiment 1). It reports where and how a host runs plugin
# hooks: HOME, PWD, the transcript path and size, and whether the transcript holds a Coroom wake URL (a count, never the
# URL). SessionStart and UserPromptSubmit put the last log lines into the model's context; Stop keeps a background
# process alive for up to 10 minutes and sends a beacon every 15 s to a path on staging that answers 404, so the server
# logs show how long a hook process lives after the turn ends. No room data, credentials or URLs are sent or printed.
set -u
mode=${1:-stop}
exec 2>/dev/null
input=
if [ ! -t 0 ]; then input=$(cat); fi
tp=$(printf '%s' "$input" | tr -d '\r\n' | sed -n -E 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')
dir=${HOME:-/tmp}/.coroom
mkdir -p "$dir"
log=$dir/diag.log
tag_file=$dir/diag.tag
if [ ! -s "$tag_file" ]; then od -An -N4 -tx4 /dev/urandom | tr -d ' \n' >"$tag_file"; fi
tag=$(cat "$tag_file")
size=-1
wake=0
probe=0
if [ -n "$tp" ] && [ -f "$tp" ]; then
  size=$(wc -c <"$tp" | tr -d ' ')
  wake=$(grep -c 'api/v1/wake/' "$tp")
  # CL-18: the agent's own shell calls of the probe script, counted only inside tool_use entries (the user's prompt
  # names the script too, as plain text).
  probe=$(grep -o '"type":"tool_use"[^}]*coroom-diag-probe' "$tp" | wc -l | tr -d ' ')
fi
printf '%s %s tag=%s home=%s pwd=%s tp=%s tp_size=%s wake_lines=%s probe_calls=%s pid=%s\n' \
  "$(date -u +%H:%M:%S)" "$mode" "$tag" "${HOME-}" "$PWD" "${tp:-none}" "$size" "$wake" "$probe" "$$" >>"$log"
beacon() { command -v curl >/dev/null && curl -q -s -o /dev/null --max-time 10 "https://staging.coroom.ai/api/v1/wake/diag/$tag-$1"; }
case $mode in
  post-tool)
    # CL-18 E: does a PostToolUse hook for a Coroom connector call get the tool's answer, and does it hold the wake
    # code? Counts and the tool's name only; the input is never written anywhere.
    tool=$(printf '%s' "$input" | tr -d '\r\n' | sed -n -E 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')
    resp=$(printf '%s' "$input" | grep -c '"tool_response"')
    codes=$(printf '%s' "$input" | grep -Eo 'cwk_[0-9A-Z]{26}_[A-Za-z0-9_-]{22}' | wc -l | tr -d ' ')
    printf '%s post-tool tag=%s tool=%s input_bytes=%s has_tool_response=%s wake_codes=%s\n' \
      "$(date -u +%H:%M:%S)" "$tag" "${tool:-none}" "${#input}" "$resp" "$codes" >>"$log"
    ;;
  session-start | prompt)
    ev=SessionStart
    if [ "$mode" = prompt ]; then ev=UserPromptSubmit; fi
    beacon "$mode"
    prev=$(tail -n 8 "$log" | tr '\n' ';' | tr -d '"\\')
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"Coroom diag (test only; report these lines when asked): %s"}}\n' "$ev" "$prev"
    ;;
  stop)
    beacon stop-0
    i=1
    while [ "$i" -le 40 ]; do
      sleep 15
      printf '%s alive t+%ss tag=%s\n' "$(date -u +%H:%M:%S)" $((i * 15)) "$tag" >>"$log"
      beacon "alive-$((i * 15))"
      i=$((i + 1))
    done
    ;;
esac
exit 0
