#!/bin/bash
# Stop hook: send iMessage notification when a Claude Code turn finishes.
# Reads stop-hook JSON on stdin; pings APPLE_ID via Messages.app if elapsed >= MIN_SECONDS.
# Configurable via ~/.claude/hooks/imessage-notify.conf — edit that file to tune.
#
# Message format (3 lines when data is available):
#   [Claude] <project> (<duration>)
#   📋 <session name>        ← the session's auto-generated ai-title
#   ✅ <what's done>         ← the 🎯 session-focus footer from the last reply (~10 words)
# Both enrichment lines are pulled from the session transcript; if either is
# missing the line is omitted, falling back to the original "turn done" wording.

# Defaults (overridden by config file if present)
APPLE_ID=""
MIN_SECONDS=300

CONFIG_FILE="$HOME/.claude/hooks/imessage-notify.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Resolve jq: macOS ships it via Homebrew (not /usr/bin, which is SIP-protected),
# and the hook's PATH may be minimal, so probe known locations explicitly.
JQ="$(command -v jq 2>/dev/null || true)"
for c in /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq; do [ -n "$JQ" ] && break; [ -x "$c" ] && JQ="$c"; done

input=$(cat)
session_id=""; cwd=""; transcript=""
if [ -n "$JQ" ]; then
  session_id=$(printf '%s' "$input" | "$JQ" -r '.session_id // ""' 2>/dev/null)
  cwd=$(printf '%s' "$input" | "$JQ" -r '.cwd // ""' 2>/dev/null)
  transcript=$(printf '%s' "$input" | "$JQ" -r '.transcript_path // ""' 2>/dev/null)
fi
[ -z "$cwd" ] && cwd=$(pwd)
project=$(basename "$cwd")

state_dir="$HOME/.claude/hooks/state"
mkdir -p "$state_dir" 2>/dev/null
start_file="$state_dir/start-${session_id}"

now=$(date +%s)
if [ -f "$start_file" ]; then
  start=$(cat "$start_file" 2>/dev/null)
  rm -f "$start_file" 2>/dev/null
else
  start=$now
fi

elapsed=$(( now - start ))
if [ "$elapsed" -lt "$MIN_SECONDS" ]; then
  exit 0
fi

# No destination configured — stay quiet rather than failing the turn.
[ -z "$APPLE_ID" ] && exit 0

mins=$(( elapsed / 60 ))
secs=$(( elapsed % 60 ))
duration="${mins}m${secs}s"

# --- enrichment: session name + a ~10-word "what's done", both from the transcript ---
session_name=""
whats_done=""
if [ -n "$JQ" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Session name = the most recent auto-generated session title.
  session_name=$("$JQ" -r 'select(.type=="ai-title") | .aiTitle // empty' "$transcript" 2>/dev/null | tail -1)
  # What's done = the latest 🎯 session-focus footer from an assistant reply,
  # with the emoji dropped and capped to ~14 words (the footer is ~6-12 by rule).
  whats_done=$("$JQ" -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$transcript" 2>/dev/null \
    | grep '^[[:space:]]*🎯' | tail -1 \
    | awk '{ out=""; cnt=0; for (i=2; i<=NF; i++) { if (cnt>=12) { out=out" …"; break } out=out (cnt>0?" ":"") $i; cnt++ } print out }')
fi

# --- build the message (single string, newline-separated) ---
if [ -n "$session_name" ] || [ -n "$whats_done" ]; then
  msg="[Claude] ${project} (${duration})"
  [ -n "$session_name" ] && msg="${msg}
📋 ${session_name}"
  [ -n "$whats_done" ] && msg="${msg}
✅ ${whats_done}"
else
  msg="[Claude] ${project}: turn done (${duration})"
fi

# Send via Messages.app. Pass the Apple ID and message as argv (NOT interpolated
# into the AppleScript source) so quotes/backslashes/newlines in a title can't
# break or inject into the script.
/usr/bin/osascript - "$APPLE_ID" "$msg" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set theId to item 1 of argv
    set theMsg to item 2 of argv
    tell application "Messages"
        set targetService to 1st service whose service type = iMessage
        set targetBuddy to buddy theId of targetService
        send theMsg to targetBuddy
    end tell
end run
APPLESCRIPT

exit 0
